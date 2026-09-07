using Documenter
using Documenter: Remotes
using Dates
using OBIS

DocMeta.setdocmeta!(OBIS, :DocTestSetup, :(using OBIS; using Dates); recursive=true)

# Embed the example scripts verbatim, read from the files themselves, so the manual cannot
# drift from the code it documents. The page is generated, not committed.
function write_example_scripts()
    examples = joinpath(dirname(@__DIR__), "examples")
    scripts = [
        (
            "orcas.jl",
            "The killer whale session: retrieval, groupby, pivot, maps, and the \
             richness-against-effort analysis.",
        ),
        (
            "figures.jl",
            "The three figures shown in the README and in the manual's other pages.",
        ),
        ("theme.jl", "The shared colour palette and Makie theme both scripts include."),
    ]
    open(joinpath(@__DIR__, "src", "example-scripts.md"), "w") do io
        println(io, "# Example scripts\n")
        println(
            io,
            """
The scripts behind the figures and the worked example, in full and exactly as they
are in the repository — this page is generated from the files at build time, so it
cannot fall out of step with them.

They live in `examples/`, which has its own environment: CairoMakie, GeoMakie,
NaturalEarth and DataFrames are dependencies of the examples, never of OBIS.jl. Run
them with `julia --project=examples examples/<script>.jl`; each one queries the live
API.
""",
        )
        for (file, blurb) in scripts
            println(io, "## `examples/", file, "`\n")
            println(io, blurb, "\n")
            println(io, "```julia")
            print(io, read(joinpath(examples, file), String))
            println(io, "```\n")
        end
    end
    return nothing
end

write_example_scripts()

makedocs(;
    modules=[OBIS],
    authors="Dante Bertuzzi",
    sitename="OBIS.jl",
    # Named explicitly so the build works from a source tree with no configured git
    # remote — a fresh clone, a release tarball, or a repository that has not been pushed
    # yet — while still producing correct "edit on GitHub" links.
    remotes=Dict(dirname(@__DIR__) => Remotes.GitHub("dantebertuzzi", "OBIS.jl")),
    format=Documenter.HTML(;
        canonical="https://dantebertuzzi.github.io/OBIS.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Getting started" => "getting-started.md",
        "Interpreting OBIS data" => "interpreting.md",
        "Worked example: killer whales" => "worked-example.md",
        "Example scripts" => "example-scripts.md",
        "Licensing and citation" => "licensing.md",
        "Large queries" => "large-queries.md",
        "Reproducibility" => "reproducibility.md",
        "Public API" => "api.md",
        "Internals" => "internals.md",
    ],
    checkdocs=:all,
)

deploydocs(; repo="github.com/dantebertuzzi/OBIS.jl", devbranch="main")
