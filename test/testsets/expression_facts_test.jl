# OPR-4b: with `emitUnits`, each code cell reports where its top-level
# expressions start and which expression produced each output.

@testitem "expression facts are absent without emitUnits" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR
    import JSON

    mktempdir() do dir
        qmd = joinpath(dir, "off.qmd")
        write(
            qmd,
            """
            ---
            title: "Off"
            ---

            ```{julia}
            println("a")
            @warn "w"
            @info "i"
            println("b")
            ```
            """,
        )
        markdown = read(qmd, String)
        server = QNR.Server()
        absent = QNR.run!(server, qmd; markdown, showprogress = false)
        QNR.close!(server, qmd)
        off = QNR.run!(
            server,
            qmd;
            markdown,
            options = Dict{String,Any}("emitUnits" => false),
            showprogress = false,
        )
        QNR.close!(server, qmd)
        @test JSON.json(absent.cells) == JSON.json(off.cells)
        code = only(filter(c -> string(c.cell_type) == "code", off.cells))
        @test code.metadata == (;)
        # Stream runs are not split when the caller did not ask for units: the
        # warning, the info and the second `println` merge as before.
        streams = [(o.name, join(o.text)) for o in code.outputs if o.output_type == "stream"]
        @test [s[1] for s in streams] == ["stdout", "stderr", "stdout"]
    end
end

@testitem "expression facts for the twelve-expression cell" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "twelve.qmd")
        write(
            qmd,
            """
            ---
            title: "Twelve"
            ---

            ```{julia}
            println("hello")
            x = 1 + 1
            y = x + 1
            @warn "careful"
            z = 3
            w = 4
            v = 5
            display("image/svg+xml", "<svg xmlns='http://www.w3.org/2000/svg'/>")
            @info "fyi"
            println(stderr, "raw stderr")
            print("tail ")
            x * 10
            ```
            """,
        )
        server = QNR.Server()
        json = QNR.run!(
            server,
            qmd;
            markdown = read(qmd, String),
            options = Dict{String,Any}("emitUnits" => true),
            showprogress = false,
        )
        QNR.close!(server, qmd)
        cell = only(filter(c -> string(c.cell_type) == "code", json.cells))
        q = cell.metadata.quarto
        @test collect(q.expression_starts) == collect(0:11)
        @test collect(q.output_expressions) == [1, 4, 8, 9, 10, 11, 12]
        @test collect(q.output_anchors) == [1, 4, 8, 9, 10, 11, 12]
        @test collect(q.output_kinds) ==
              [nothing, "warning", nothing, "message", nothing, nothing, nothing]
        @test length(q.output_anchors) == length(cell.outputs)
        # The info and the raw stderr write stay separate runs.
        @test cell.outputs[4].output_type == "stream"
        @test cell.outputs[5].output_type == "stream"
    end
end

@testitem "expression starts are relative to the code after the options" tags =
    [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "options.qmd")
        write(
            qmd,
            """
            ---
            title: "Options"
            ---

            ```{julia}
            #| echo: true
            #| warning: true

            # a comment
            function f(x)
                x + 1
            end
            println("one")
            for i in 1:2
                println(i)
            end
            x = [1, 2,
                 3]
            f(2)
            ```
            """,
        )
        server = QNR.Server()
        json = QNR.run!(
            server,
            qmd;
            markdown = read(qmd, String),
            options = Dict{String,Any}("emitUnits" => true),
            showprogress = false,
        )
        QNR.close!(server, qmd)
        cell = only(filter(c -> string(c.cell_type) == "code", json.cells))
        q = cell.metadata.quarto
        # Code after the options is: blank, comment, function (lines 2-4),
        # println (5), for (6-8), x = [...] (9-10), f(2) (11).
        @test collect(q.expression_starts) == [2, 5, 6, 9, 11]
        # The loop's two prints belong to expression 3 and anchor at the next start.
        i = findfirst(==(3), collect(q.output_expressions))
        @test i !== nothing
        @test q.output_anchors[i] == 9
    end
end

@testitem "output from a subprocess and a late async print is attributed" tags =
    [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "attrib.qmd")
        write(
            qmd,
            """
            ---
            title: "Attribution"
            ---

            ```{julia}
            run(`echo from-subprocess`)
            @async (sleep(0.3); println("late"))
            sleep(1)
            println("end")
            ```
            """,
        )
        server = QNR.Server()
        json = QNR.run!(
            server,
            qmd;
            markdown = read(qmd, String),
            options = Dict{String,Any}("emitUnits" => true),
            showprogress = false,
        )
        QNR.close!(server, qmd)
        cell = only(filter(c -> string(c.cell_type) == "code", json.cells))
        q = cell.metadata.quarto
        sub = findfirst(
            o -> o.output_type == "stream" && occursin("from-subprocess", join(o.text)),
            cell.outputs,
        )
        @test sub !== nothing
        @test q.output_expressions[sub] == 1
        late = findfirst(o -> o.output_type == "stream" && occursin("late", join(o.text)), cell.outputs)
        @test late !== nothing
        # The async print lands during `sleep(1)`, expression 3.
        @test q.output_expressions[late] == 3
    end
end

@testitem "an error in the cell anchors at the end of the code" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "throws.qmd")
        write(
            qmd,
            """
            ---
            title: "Throws"
            ---

            ```{julia}
            #| error: true
            println("before")
            error("boom")
            println("never")
            ```
            """,
        )
        server = QNR.Server()
        json = QNR.run!(
            server,
            qmd;
            markdown = read(qmd, String),
            options = Dict{String,Any}("emitUnits" => true),
            showprogress = false,
        )
        QNR.close!(server, qmd)
        cell = only(filter(c -> string(c.cell_type) == "code", json.cells))
        q = cell.metadata.quarto
        @test collect(q.expression_starts) == [0, 1, 2]
        err = findfirst(o -> o.output_type == "error", cell.outputs)
        @test err !== nothing
        # The throwing expression is 2; its anchor is the line count (3), not
        # a start of the never-run expression 3 (line 2).
        @test q.output_expressions[err] == 2
        @test q.output_anchors[err] == 3
    end
end

@testitem "warning: false keeps stderr under emitUnits and drops it otherwise" tags =
    [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "nowarn.qmd")
        write(
            qmd,
            """
            ---
            title: "No warning"
            ---

            ```{julia}
            #| warning: false
            @warn "careful"
            @info "fyi"
            println(stderr, "raw")
            println("out")
            ```
            """,
        )
        markdown = read(qmd, String)
        server = QNR.Server()
        run(opts) = begin
            json = QNR.run!(server, qmd; markdown, options = opts, showprogress = false)
            QNR.close!(server, qmd)
            only(filter(c -> string(c.cell_type) == "code", json.cells))
        end
        off = run(Dict{String,Any}())
        stderr_off = [o for o in off.outputs if o.output_type == "stream" && o.name == "stderr"]
        @test isempty(stderr_off)

        on = run(Dict{String,Any}("emitUnits" => true))
        text = join(join(o.text) for o in on.outputs if o.output_type == "stream" && o.name == "stderr")
        @test occursin("careful", text)
        @test occursin("fyi", text)
        @test occursin("raw", text)
        q = on.metadata.quarto
        @test "warning" in collect(q.output_kinds)
        @test "message" in collect(q.output_kinds)
    end
end
