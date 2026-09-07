# Regenerate the figures shown in the README.
#
#     julia --project=examples examples/figures.jl
#
# Plotting is not part of OBIS.jl. CairoMakie and GeoMakie are dependencies of this
# example environment only, so installing the package stays small. The script queries the
# live API, so the exact numbers move as OBIS ingests data; the shapes do not.
#
# Each figure is written twice, for light and dark reading. The dark variant is stepped for
# the dark surface rather than being an inverted copy of the light one.

using OBIS
using CairoMakie
using GeoMakie
using NaturalEarth
using Dates
using Statistics

const OUT = joinpath(@__DIR__, "figures")
const BOX = "POLYGON ((2.0 52.5, 2.0 51.0, 4.5 51.0, 4.5 52.5, 2.0 52.5))"
const SPECIES = "Abra alba"

# --- Theme ------------------------------------------------------------------------------
# Two categorical hues, validated for colour-vision deficiency against both surfaces.
# Identity is never carried by colour alone: every figure also has a legend or direct
# labels.

struct Palette
    surface::String
    ink::String
    ink2::String
    muted::String
    grid::String
    axis::String
    series1::String
    series2::String
    land::String
    sea::String
end

const LIGHT = Palette(
    "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7",
    "#2a78d6", "#eb6834", "#eeece6", "#f7f7f5",
)
const DARK = Palette(
    "#1a1a19", "#ffffff", "#c3c2b7", "#898781", "#2c2c2a", "#383835",
    "#3987e5", "#d95926", "#26262340", "#212120",
)

function theme_for(p::Palette)
    return Theme(;
        backgroundcolor=p.surface,
        textcolor=p.ink,
        fontsize=13,
        figure_padding=18,
        Axis=(
            backgroundcolor=p.surface,
            xgridcolor=p.grid,
            ygridcolor=p.grid,
            xgridwidth=1,
            ygridwidth=1,
            leftspinevisible=false,
            rightspinevisible=false,
            topspinevisible=false,
            bottomspinecolor=p.axis,
            xtickcolor=p.muted,
            ytickcolor=p.muted,
            xticklabelcolor=p.ink2,
            yticklabelcolor=p.ink2,
            xlabelcolor=p.ink2,
            ylabelcolor=p.ink2,
            titlecolor=p.ink,
            titlealign=:left,
            titlesize=15,
            subtitlecolor=p.ink2,
            subtitlesize=12,
            subtitlegap=6,
        ),
        Legend=(
            framevisible=false,
            labelcolor=p.ink2,
            labelsize=12,
            patchsize=(12, 12),
        ),
    )
end

save_both(name, build) =
    for (suffix, p) in (("", LIGHT), ("-dark", DARK))
        with_theme(theme_for(p)) do
            fig = build(p)
            path = joinpath(OUT, string(name, suffix, ".png"))
            save(path, fig; px_per_unit=2)
            println("  wrote ", relpath(path, dirname(@__DIR__)))
        end
    end

# --- Data -------------------------------------------------------------------------------

println("Querying OBIS…")
records = OBIS.occurrence(; scientificname=SPECIES, geometry=BOX)
years = OBIS.statistics_years(SPECIES)
license_summary = OBIS.licenses(records)
println("  ", OBIS.nrow(records), " records, accessed ", OBIS.metadata(records).accessed)

flagged(fs, flag) = flag in fs

# --- Figure 1: where the records are, and which ones the pipeline flagged ----------------
#
# The map earns its place by showing something a table cannot: the ON_LAND records are not
# scattered at random, they sit on the coast and in estuaries, which is what a
# georeferencing error looks like.

function figure_map(p::Palette)
    lon = collect(records.decimalLongitude)
    lat = collect(records.decimalLatitude)
    onland = [flagged(fs, "ON_LAND") for fs in records.flags]
    keep = .!ismissing.(lon) .& .!ismissing.(lat)

    clean = keep .& .!onland
    dirty = keep .& onland

    fig = Figure(; size=(780, 660))
    Label(
        fig[1, 1], "$(SPECIES) in the southern North Sea";
        color=p.ink, fontsize=15, font=:bold, halign=:left, tellwidth=false,
    )
    Label(
        fig[2, 1],
        "$(OBIS.nrow(records)) records from $(length(unique(skipmissing(records.dataset_id)))) datasets · accessed $(OBIS.metadata(records).accessed)";
        color=p.ink2, fontsize=12, halign=:left, tellwidth=false,
    )

    ga = GeoAxis(
        fig[3, 1];
        dest="+proj=merc",
        limits=(1.8, 4.7, 50.9, 52.6),
        xgridcolor=p.grid,
        ygridcolor=p.grid,
        xticklabelcolor=p.ink2,
        yticklabelcolor=p.ink2,
        xticklabelsize=11,
        yticklabelsize=11,
    )
    # Filled land at 10 m resolution. A coastline drawn as a bare line reads as an
    # arbitrary diagonal at this zoom; the fill is what makes the figure a map.
    land = NaturalEarth.naturalearth("land", 10)
    poly!(ga, land.geometry; color=p.land, strokecolor=p.axis, strokewidth=0.8)

    scatter!(
        ga, lon[clean], lat[clean];
        color=(p.series1, 0.5), markersize=5, strokewidth=0,
        label="no ON_LAND flag  ($(count(clean)))",
    )
    scatter!(
        ga, lon[dirty], lat[dirty];
        color=p.series2, markersize=7, strokewidth=0.7, strokecolor=p.surface,
        label="flagged ON_LAND  ($(count(dirty)))",
    )
    translate!(ga.scene.plots[end], 0, 0, 10)

    # The legend gets its own row, so it can never collide with the axis or the title.
    Legend(
        fig[4, 1], ga;
        orientation=:horizontal, framevisible=false,
        labelcolor=p.ink2, labelsize=12, patchsize=(12, 12), padding=(0, 0, 4, 0),
        halign=:left,
    )
    Label(
        fig[5, 1],
        "A marine bivalve mapped onto land is a georeferencing error, not a range extension. \
        The flagged records cluster on the coast and in estuaries, and a default query returns them.";
        color=p.muted, fontsize=11, halign=:left, justification=:left, tellwidth=false,
        word_wrap=true,
    )

    rowsize!(fig.layout, 3, Relative(0.82))
    rowgap!(fig.layout, 1, 2)
    rowgap!(fig.layout, 2, 8)
    rowgap!(fig.layout, 3, 4)
    rowgap!(fig.layout, 4, 2)
    return fig
end

# --- Figure 2: record counts follow sampling effort --------------------------------------
#
# One series, so no legend: the title names it. The annotation is the point of the figure.

function figure_years(p::Palette)
    yr = [Int(e["year"]) for e in years]
    n = [Int(e["records"]) for e in years]
    ord = sortperm(yr)
    yr, n = yr[ord], n[ord]

    fig = Figure(; size=(760, 400))
    ax = Axis(
        fig[1, 1];
        title="Records of $(SPECIES) per year, worldwide",
        subtitle="Counts track survey programmes and digitization, not abundance",
        xlabel="year", ylabel="records",
        xgridvisible=false,
    )
    band!(ax, yr, zeros(length(yr)), n; color=(p.series1, 0.15))
    lines!(ax, yr, n; color=p.series1, linewidth=2)

    peak = argmax(n)
    scatter!(ax, [yr[peak]], [n[peak]]; color=p.series1, markersize=9,
        strokewidth=1.5, strokecolor=p.surface)
    text!(
        ax, yr[peak], n[peak];
        text=" $(yr[peak]): $(n[peak]) records",
        align=(:left, :center), color=p.ink2, fontsize=11, offset=(6, 0),
    )
    # The fall at the right-hand end is publication lag: recent surveys have not been
    # published to OBIS yet. Saying so is the whole point of the figure.
    recent = maximum(yr)
    text!(
        ax, recent, maximum(n) * 0.30;
        text="the fall at this end is\npublication lag, not decline",
        align=(:right, :top), color=p.muted, fontsize=11, offset=(-6, 0),
    )
    xlims!(ax, minimum(yr) - 2, maximum(yr) + 6)
    ylims!(ax, 0, maximum(n) * 1.16)
    return fig
end

# --- Figure 3: what the result may be used for -------------------------------------------
#
# Two hues carry one binary fact — may this be used commercially — and every bar is
# directly labelled, so the colour is reinforcement rather than the only channel.

function figure_licenses(p::Palette)
    lic = collect(license_summary.license)
    rec = collect(license_summary.records)
    com = collect(license_summary.permits_commercial_use)
    ord = sortperm(rec)
    lic, rec, com = lic[ord], rec[ord], com[ord]

    nc_datasets = sum(license_summary.datasets[.!license_summary.permits_commercial_use])
    nc_records = sum(license_summary.records[.!license_summary.permits_commercial_use])

    fig = Figure(; size=(760, 400))
    ax = Axis(
        fig[1, 1];
        title="Licences in one query",
        subtitle="$(sum(rec)) records · $(nc_datasets) of the $(sum(license_summary.datasets)) datasets \
                  ($(nc_records) records) may not be used commercially, which constrains the whole result",
        xlabel="records",
        yticks=(1:length(lic), lic),
        ygridvisible=false,
    )
    barplot!(
        ax, 1:length(lic), rec;
        direction=:x,
        color=[c ? p.series1 : p.series2 for c in com],
        width=0.62,
    )
    for (i, v) in enumerate(rec)
        text!(ax, v, i; text=" $(v)", align=(:left, :center), color=p.ink2, fontsize=11)
    end
    xlims!(ax, 0, maximum(rec) * 1.18)
    hidespines!(ax, :l)

    Legend(
        fig[2, 1],
        [PolyElement(; color=p.series1), PolyElement(; color=p.series2)],
        ["commercial use permitted", "commercial use not permitted"];
        orientation=:horizontal, framevisible=false, labelcolor=p.ink2, labelsize=11,
        patchsize=(12, 12), halign=:left, padding=(0, 0, 0, 0),
    )
    Label(
        fig[3, 1],
        "\"unknown\" is a rights statement the package could not identify. It is reported \
        rather than assumed permissive, because the values behind it include the literal \
        string \"Restricted\".";
        color=p.muted, fontsize=11, halign=:left, justification=:left, tellwidth=false,
        word_wrap=true,
    )
    rowgap!(fig.layout, 1, 4)
    rowgap!(fig.layout, 2, 2)
    return fig
end

# --- Run ---------------------------------------------------------------------------------

mkpath(OUT)
println("Rendering…")
save_both("map-north-sea", figure_map)
save_both("records-per-year", figure_years)
save_both("licenses", figure_licenses)

# The documentation shows the same figures, so it reads from one copy rather than a second
# set that could drift out of step with the README.
const DOCS_ASSETS = joinpath(dirname(@__DIR__), "docs", "src", "assets")
mkpath(DOCS_ASSETS)
for f in readdir(OUT)
    endswith(f, ".png") && cp(joinpath(OUT, f), joinpath(DOCS_ASSETS, f); force=true)
end
println("  copied ", count(endswith(".png"), readdir(OUT)), " figures to docs/src/assets")
println("Done.")
