using Documenter
using Documenter: Remotes
using Dates
using OBIS

DocMeta.setdocmeta!(OBIS, :DocTestSetup, :(using OBIS; using Dates); recursive=true)

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
        "Licensing and citation" => "licensing.md",
        "Large queries" => "large-queries.md",
        "Reproducibility" => "reproducibility.md",
        "Public API" => "api.md",
        "Internals" => "internals.md",
    ],
    checkdocs=:all,
)

deploydocs(; repo="github.com/dantebertuzzi/OBIS.jl", devbranch="main")
