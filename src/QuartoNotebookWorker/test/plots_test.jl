@testitem "Plots extension renders" tags = [:integration, :julia110] begin
    import QuartoNotebookWorker as QNW
    import Plots

    options = Dict{String,Any}("format" => Dict("execute" => Dict("fig-dpi" => 100)))
    QNW.NotebookState.with_test_context(; options) do
        mod = QNW.NotebookState.notebook_module()
        QNW.run_package_loading_hooks()

        p = Plots.plot([1, 2, 3])
        result = QNW.render_mimetypes(p, mod, Dict{String,Any}())

        @test haskey(result, "image/png")
        png_data = result["image/png"].data
        @test length(png_data) > 8
        @test png_data[1:8] == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    end
end

@testitem "Plots figure is attributed to its expression" tags = [:integration, :julia110] begin
    import QuartoNotebookWorker as QNW
    import Plots

    options = Dict{String,Any}("format" => Dict("execute" => Dict("fig-dpi" => 100)))
    QNW.NotebookState.with_test_context(; options) do
        mod = QNW.NotebookState.notebook_module()
        QNW.run_package_loading_hooks()

        code = """
        import Plots
        println("before")
        display(Plots.plot([1, 2, 3]))
        println("after")
        """
        response = QNW.render(code, "test.jl", 1, Dict{String,Any}(); trace = true, mod)
        cell = response.cells[1]
        @test cell.expression_starts == [0, 1, 2, 3]
        @test cell.display_expressions == [3]
        @test haskey(cell.display_results[1], "image/png")
        @test [(e, c) for (_, _, c, e, _) in cell.streams] == [(2, 0), (4, 1)]
    end
end
