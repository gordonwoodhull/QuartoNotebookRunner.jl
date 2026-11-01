@testitem "handledLanguages cedes foreign cells" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "handled_cells.qmd")
        write(
            qmd,
            """
            ---
            title: "Handled cells"
            ---

            ```{julia}
            1 + 1
            ```

            ```{r}
            summary(cars)
            ```
            """,
        )

        server = QNR.Server()
        options = Dict{String,Any}("handledLanguages" => ["r"])
        json = QNR.run!(
            server,
            qmd;
            options,
            markdown = read(qmd, String),
            showprogress = false,
        )

        sources = [join(cell.source) for cell in json.cells]
        # The `r` fence is left verbatim in a markdown cell, never executed.
        @test any(contains("```{r}\nsummary(cars)\n```"), sources)
        # The `julia` cell still runs.
        code_cells = filter(c -> string(c.cell_type) == "code", json.cells)
        @test length(code_cells) == 1
        @test join(only(code_cells).source) == "1 + 1"
        @test only(code_cells).outputs[1].data["text/plain"] == "2"
        QNR.close!(server, qmd)
    end
end

@testitem "handledLanguages cedes foreign inline spans" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "handled_spans.qmd")
        write(
            qmd,
            """
            ---
            title: "Handled spans"
            ---

            ```{julia}
            a = 1
            ```

            Julia span `{julia} a + 1` and python span `{python} 1 + 1`.
            """,
        )

        server = QNR.Server()
        options = Dict{String,Any}("handledLanguages" => ["python"])
        json = QNR.run!(
            server,
            qmd;
            options,
            markdown = read(qmd, String),
            showprogress = false,
        )

        text = join(
            join(cell.source) for
            cell in json.cells if string(cell.cell_type) == "markdown"
        )
        @test contains(text, "Julia span 2")
        # A span in a language another engine owns stays literal.
        @test contains(text, "`{python} 1 + 1`")
        QNR.close!(server, qmd)
    end
end

@testitem "span language without an owner stays literal" tags = [:notebook] begin
    import QuartoNotebookRunner as QNR

    mktempdir() do dir
        qmd = joinpath(dir, "unowned_span.qmd")
        write(
            qmd,
            """
            ---
            title: "Unowned span"
            ---

            ```{julia}
            a = 1
            ```

            Unowned `{r} 1 + 1` and owned `{julia} a + 1`.
            """,
        )

        server = QNR.Server()
        # Core lists a language no engine owns in `handledLanguages`; Julia must not run it.
        options = Dict{String,Any}("handledLanguages" => ["r", "python"])
        json = QNR.run!(
            server,
            qmd;
            options,
            markdown = read(qmd, String),
            showprogress = false,
        )

        text = join(
            join(cell.source) for
            cell in json.cells if string(cell.cell_type) == "markdown"
        )
        @test contains(text, "`{r} 1 + 1`")
        @test contains(text, "owned 2")
        QNR.close!(server, qmd)
    end
end
