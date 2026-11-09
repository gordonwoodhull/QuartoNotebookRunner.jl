@testitem "streams keep the order the cell wrote them in" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        println("one")
        println(stderr, "two")
        println("three")
        println("four")
        """
        response = QNW.render(code, "test.jl", 1; mod)
        @test response.cells[1].streams == [
            ("stdout", "one\n", 0, 0, ""),
            ("stderr", "two\n", 0, 0, ""),
            ("stdout", "three\nfour\n", 0, 0, ""),
        ]
    end
end

@testitem "log records go to stderr" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("@warn \"careful\"", "test.jl", 1; mod)
        name, text = only(response.cells[1].streams)
        @test name == "stderr"
        @test contains(text, "Warning:")
        @test contains(text, "careful")
    end
end

@testitem "subprocess output keeps its stream" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        script = "println(\\"out\\"); println(stderr, \\"err\\")"
        run(`\$(Base.julia_cmd()) --startup-file=no -e \$script`)
        nothing
        """
        response = QNW.render(code, "test.jl", 1; mod)
        streams = Dict(name => text for (name, text, _, _, _) in response.cells[1].streams)
        @test streams["stdout"] == "out\n"
        @test streams["stderr"] == "err\n"
    end
end

@testitem "warning false drops stderr and joins the stdout around it" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        println("one")
        @warn "hidden warning"
        @error "hidden error"
        println(stderr, "hidden direct write")
        println("two")
        """
        options = Dict{String,Any}("warning" => false)
        response = QNW.render(code, "test.jl", 1, options; mod)
        @test response.cells[1].streams == [("stdout", "one\ntwo\n", 0, 0, "")]
    end
end

@testitem "warning false still delivers records to the cell's own logger" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        buffer = IOBuffer()
        Base.CoreLogging.with_logger(Base.CoreLogging.SimpleLogger(buffer)) do
            @warn "kept"
        end
        contains(String(take!(buffer)), "kept")
        """
        options = Dict{String,Any}("warning" => false)
        response = QNW.render(code, "test.jl", 1, options; mod)
        @test String(response.cells[1].results["text/plain"].data) == "true"
    end
end

@testitem "a finished cell's streams write to the current cell" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        saved = stdout
        logger = Base.CoreLogging.SimpleLogger(stderr)
        nothing
        """
        QNW.render(code, "test.jl", 1; mod)
        code = """
        println(saved, "late")
        flush(saved)
        Base.CoreLogging.with_logger(() -> @warn("late warning"), logger)
        """
        response = QNW.render(code, "test.jl", 2; mod)
        @test response.cells[1].error === nothing
        @test first.(response.cells[1].streams) == ["stdout", "stderr"]
        @test response.cells[1].streams[1][2] == "late\n"
        @test contains(response.cells[1].streams[2][2], "late warning")
    end
end

@testitem "streams record how many displays came before them" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        println("before")
        display("first")
        println("between")
        println(stderr, "still between")
        display("second")
        display("third")
        println("after")
        """
        response = QNW.render(code, "test.jl", 1; mod)
        @test response.cells[1].streams == [
            ("stdout", "before\n", 0, 0, ""),
            ("stdout", "between\n", 1, 0, ""),
            ("stderr", "still between\n", 1, 0, ""),
            ("stdout", "after\n", 3, 0, ""),
        ]
        @test length(response.cells[1].display_results) == 3
    end
end

@testitem "warning false joins stdout only between the same displays" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        println("one")
        @warn "hidden"
        println("two")
        display("shown")
        println("three")
        """
        options = Dict{String,Any}("warning" => false)
        response = QNW.render(code, "test.jl", 1, options; mod)
        @test response.cells[1].streams ==
              [("stdout", "one\ntwo\n", 0, 0, ""), ("stdout", "three\n", 1, 0, "")]
    end
end

@testitem "a cell that writes nothing has no streams" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        response = QNW.render("1 + 1", "test.jl", 1; mod)
        @test isempty(response.cells[1].streams)
    end
end

@testitem "trace splits streams by expression and log kind" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        println("one")
        @warn "careful"
        @info "fyi"
        println(stderr, "raw")
        print("two")
        display("shown")
        println("three")
        """
        response = QNW.render(code, "test.jl", 1, Dict{String,Any}(); trace = true, mod)
        cell = response.cells[1]
        @test [(n, e, k) for (n, _, _, e, k) in cell.streams] == [
            ("stdout", 1, ""),
            ("stderr", 2, "warning"),
            ("stderr", 3, "message"),
            ("stderr", 4, ""),
            ("stdout", 5, ""),
            ("stdout", 7, ""),
        ]
        @test cell.expression_starts == collect(0:6)
        @test cell.display_expressions == [6]
        # Without a trace, the same cell gives the old three runs.
        plain = QNW.render(code, "test.jl", 1, Dict{String,Any}(); mod)
        @test [(n, e, k) for (n, _, _, e, k) in plain.cells[1].streams] ==
              [("stdout", 0, ""), ("stderr", 0, ""), ("stdout", 0, ""), ("stdout", 0, "")]
    end
end

@testitem "trace keeps stderr under warning false" begin
    import QuartoNotebookWorker as QNW

    QNW.NotebookState.with_test_context() do
        mod = QNW.NotebookState.notebook_module()

        code = """
        @warn "hidden by the presenter"
        println(stderr, "raw")
        """
        options = Dict{String,Any}("warning" => false)
        traced = QNW.render(code, "test.jl", 1, options; trace = true, mod)
        @test [k for (_, _, _, _, k) in traced.cells[1].streams] == ["warning", ""]
        untraced = QNW.render(code, "test.jl", 1, options; mod)
        @test isempty(untraced.cells[1].streams)
    end
end
