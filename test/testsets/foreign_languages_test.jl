# Tests that evaluate `{python}` and `{r}` spans and cells. They need a Julia project
# with PythonCall and RCall, a Python interpreter and R, so they are skipped unless:
#
#   QNR_TEST_FOREIGN_PROJECT   a directory holding a Project.toml (and Manifest.toml)
#                              that has PythonCall and RCall
#   JULIA_PYTHONCALL_EXE       the Python to use, with JULIA_CONDAPKG_BACKEND=Null
#
# For example, with uv (the project must have been resolved once with the same settings):
#
#   uv venv /tmp/foreign/.venv
#   export JULIA_CONDAPKG_BACKEND=Null JULIA_PYTHONCALL_EXE=/tmp/foreign/.venv/bin/python
#   julia --project=/tmp/foreign -e 'import Pkg; Pkg.add(["PythonCall", "RCall"])'
#   export QNR_TEST_FOREIGN_PROJECT=/tmp/foreign
@testmodule ForeignSetup begin
    import QuartoNotebookRunner as QNR

    project = get(ENV, "QNR_TEST_FOREIGN_PROJECT", "")
    available =
        isfile(joinpath(project, "Project.toml")) &&
        haskey(ENV, "JULIA_PYTHONCALL_EXE") &&
        Sys.which("Rscript") !== nothing

    # Run `body` in a temporary directory that holds the foreign project and `qmd`.
    function run_qmd(qmd_text; options = Dict{String,Any}())
        mktempdir() do dir
            for name in ("Project.toml", "Manifest.toml")
                isfile(joinpath(project, name)) &&
                    cp(joinpath(project, name), joinpath(dir, name))
            end
            qmd = joinpath(dir, "foreign.qmd")
            write(qmd, qmd_text)
            server = QNR.Server()
            json = QNR.run!(server, qmd; options, markdown = qmd_text, showprogress = false)
            QNR.close!(server, qmd)
            return json
        end
    end

    markdown_text(json) =
        join(join(c.source) for c in json.cells if string(c.cell_type) == "markdown")

    const LOAD = """
        ```{julia}
        using PythonCall, RCall
        ```
        """
end

@testitem "handledLanguages absent keeps all three languages" tags = [:notebook] setup =
    [ForeignSetup] skip = !haskey(ENV, "QNR_TEST_FOREIGN_PROJECT") begin
    import .ForeignSetup as FS

    json = FS.run_qmd("""
        ---
        title: "All three"
        ---

        $(FS.LOAD)

        ```{julia}
        a = 1
        ```

        Julia `{julia} a + 1`, python `{python} 1 + 1` and r `{r} 1 + 1`.
        """)

    text = FS.markdown_text(json)
    @test contains(text, "Julia 2,")
    @test contains(text, "python 2 ")
    @test contains(text, r"r 2\\?\.0")
    @test !contains(text, "`{python}")
    @test !contains(text, "`{r}")
end

@testitem "span language absent from the handled list still evaluates" tags = [:notebook] setup =
    [ForeignSetup] skip = !haskey(ENV, "QNR_TEST_FOREIGN_PROJECT") begin
    import .ForeignSetup as FS

    # Only `r` is handled elsewhere, so the python span is still ours.
    json = FS.run_qmd(
        """
        ---
        title: "Absent from the list"
        ---

        $(FS.LOAD)

        Python `{python} 1 + 1` and r `{r} 1 + 1`.
        """;
        options = Dict{String,Any}("handledLanguages" => ["r"]),
    )

    text = FS.markdown_text(json)
    @test contains(text, "Python 2 ")
    @test contains(text, "`{r} 1 + 1`")
end

@testitem "emitUnits marks code prefix cells" tags = [:notebook] setup = [ForeignSetup] skip =
    !haskey(ENV, "QNR_TEST_FOREIGN_PROJECT") begin
    import .ForeignSetup as FS

    json = FS.run_qmd(
        """
        ---
        title: "Prefix"
        ---

        $(FS.LOAD)

        ```{python}
        1 + 1
        ```
        """;
        options = Dict{String,Any}("emitUnits" => true),
    )

    prefix = filter(c -> endswith(c.id, "_code_prefix"), json.cells)
    @test length(prefix) == 1
    quarto = only(prefix).metadata.quarto
    @test quarto.role == "code_prefix"
    # The setup cell is unit 1; the python cell is unit 2 and the prefix belongs to it.
    @test quarto.unit == 2
    python = only(
        filter(
            c -> string(c.cell_type) == "code" && c.metadata.quarto.unit == 2,
            json.cells,
        ),
    )
    @test python.metadata.quarto.language == "python"
end
