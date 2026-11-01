@testitem "emitUnits default options leave the notebook unchanged" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR
    import JSON

    mktempdir() do dir
        qmd = joinpath(dir, "default.qmd")
        write(
            qmd,
            """
            ---
            title: "Default"
            ---

            ```{julia}
            a = 1
            ```

            Inline `{julia} a + 1`.
            """,
        )
        markdown = read(qmd, String)
        server = QNR.Server()
        absent = QNR.run!(server, qmd; markdown, showprogress = false)
        QNR.close!(server, qmd)
        explicit_off = QNR.run!(
            server,
            qmd;
            markdown,
            options = Dict{String,Any}("emitUnits" => false, "handledLanguages" => []),
            showprogress = false,
        )
        QNR.close!(server, qmd)

        @test JSON.json(absent.cells) == JSON.json(explicit_off.cells)
        for cell in absent.cells
            @test cell.metadata == (;)
        end
    end
end

@testitem "emitUnits annotates code cells" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "units.qmd")
        write(
            qmd,
            """
            ---
            title: "Units"
            ---

            ```{julia}
            a = 1
            ```

            ```{julia}
            #| eval: false
            b = 2
            ```

            Prose between.

            ```{julia}
            c = 3
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

        code = filter(c -> string(c.cell_type) == "code", json.cells)
        @test length(code) == 3
        # `unit` is 1-based in document order and counts the `eval: false` cell.
        @test [c.metadata.quarto.unit for c in code] == [1, 2, 3]
        @test all(c -> c.metadata.quarto.language == "julia", code)
        @test all(c -> c.metadata.quarto.file == qmd, code)
        # `line` is the fence line (1-based) in the file.
        @test [c.metadata.quarto.line for c in code] == [5, 9, 16]
    end
end

@testitem "emitUnits annotates inline results" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "inline.qmd")
        write(
            qmd,
            """
            ---
            title: "Inline"
            ---

            ```{julia}
            a = 1
            ```

            Two spans `{julia} a + 1` and `{julia} a + 2`.
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

        md = filter(c -> string(c.cell_type) == "markdown", json.cells)
        annotated = filter(c -> haskey(c.metadata, :quarto), md)
        cell = only(annotated)
        # The cell source stays the substituted text.
        @test contains(join(cell.source), "Two spans 2 and 3.")
        inline = cell.metadata.quarto.inline
        @test length(inline) == 2
        @test [i.language for i in inline] == ["julia", "julia"]
        @test [i.code for i in inline] == ["a + 1", "a + 2"]
        @test all(i -> i.line == 9, inline)
        @test inline[1].outputs[1].output_type == "execute_result"
        @test inline[1].outputs[1].data["text/plain"] == "2"
        @test inline[2].outputs[1].data["text/plain"] == "3"
    end
end

@testitem "emitUnits marks expansion cells" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "expansion.qmd")
        write(
            qmd,
            """
            ---
            title: "Expansion"
            ---

            ```{julia}
            import QuartoNotebookWorker: Cell, expand
            struct Two
                cells::Any
            end
            expand(t::Two) = t.cells
            ```

            ```{julia}
            Two([Cell(() -> 1; code = "1", options = Dict()), Cell(() -> 2; code = "2", options = Dict())])
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

        code = filter(c -> string(c.cell_type) == "code", json.cells)
        # The setup cell, the mock cell holding the original source, then the two expansions.
        @test length(code) == 4
        @test code[1].metadata.quarto.unit == 1
        @test code[2].metadata.quarto.unit == 2
        @test code[2].metadata.quarto.role == "expansion_source"
        expansions = code[3:4]
        @test all(c -> c.metadata.quarto.unit == 2, expansions)
        @test [c.metadata.quarto.expansion for c in expansions] == [1, 2]
    end
end

@testitem "emitUnits ignores inline code in fences" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "fence.qmd")
        write(
            qmd,
            """
            ---
            title: "Fence"
            ---

            ````markdown
            Not evaluated `{julia} 1 + 1`.
            ````

            ```{julia}
            a = 1
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

        text = join(join(c.source) for c in json.cells if string(c.cell_type) == "markdown")
        @test contains(text, "`{julia} 1 + 1`")
        for c in json.cells
            string(c.cell_type) == "markdown" || continue
            @test !haskey(c.metadata, :quarto)
        end
    end
end

@testitem "emitUnits is part of the cache key" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "cached.qmd")
        write(
            qmd,
            """
            ---
            title: "Cached"
            ---

            ```{julia}
            1 + 1
            ```
            """,
        )
        markdown = read(qmd, String)
        cache = Dict{String,Any}(
            "format" =>
                Dict{String,Any}("execute" => Dict{String,Any}("cache" => true)),
        )
        run(emit) = begin
            server = QNR.Server()
            options = merge(cache, Dict{String,Any}("emitUnits" => emit))
            json = QNR.run!(server, qmd; markdown, options, showprogress = false)
            QNR.close!(server, qmd)
            json
        end

        first_run = run(false)
        @test !haskey(
            only(filter(c -> string(c.cell_type) == "code", first_run.cells)).metadata,
            :quarto,
        )
        # Turning `emitUnits` on must not reuse the cached, unannotated cells.
        second_run = run(true)
        @test only(
            filter(c -> string(c.cell_type) == "code", second_run.cells),
        ).metadata.quarto.unit == 1
        # And turning it off again must not keep the annotation.
        third_run = run(false)
        @test !haskey(
            only(filter(c -> string(c.cell_type) == "code", third_run.cells)).metadata,
            :quarto,
        )
    end
end

@testitem "old cache entries are ignored after the schema bump" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR
    import JSON

    mktempdir() do dir
        qmd = joinpath(dir, "schema.qmd")
        write(
            qmd,
            """
            ---
            title: "Schema"
            ---

            ```{julia}
            rand()
            ```
            """,
        )
        markdown = read(qmd, String)
        options = Dict{String,Any}(
            "format" =>
                Dict{String,Any}("execute" => Dict{String,Any}("cache" => true)),
        )
        output() = begin
            server = QNR.Server()
            json = QNR.run!(server, qmd; markdown, options, showprogress = false)
            QNR.close!(server, qmd)
            only(filter(c -> string(c.cell_type) == "code", json.cells)).outputs[1].data["text/plain"]
        end

        first_value = output()
        @test output() == first_value

        # Rewrite every cache entry as if written by schema 1.0.0.
        for file in readdir(joinpath(dir, ".cache"); join = true)
            entry = JSON.parsefile(file; dicttype = Dict{String,Any})
            entry["qnr_schema_version"] = "1.0.0"
            write(file, JSON.json(entry))
        end
        @test output() != first_value
    end
end
