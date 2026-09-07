# A worked example: killer whales (Orcinus orca) in OBIS.
#
#     julia --project=examples examples/orcas.jl
#
# Covers the things a user actually does with a result once it is in hand — map it, group
# it, pivot it, and test a relationship — and shows where each of those goes wrong if the
# nature of the data is ignored.
#
# Plotting and analysis are not part of OBIS.jl. Everything below happens in DataFrames and
# CairoMakie, on a table the client handed over; that is the point of implementing
# Tables.jl rather than bundling this.

using OBIS
using CairoMakie
using GeoMakie
using NaturalEarth
using DataFrames
using Dates
using Statistics

const OUT = joinpath(@__DIR__, "figures")
const DOCS_ASSETS = joinpath(dirname(@__DIR__), "docs", "src", "assets")
const SPECIES = "Orcinus orca"

include(joinpath(@__DIR__, "theme.jl"))

rule(s) = println("\n", s, "\n", "-"^length(s))

# ---------------------------------------------------------------------------------------
rule("1. The query, and what it leaves out")

st = OBIS.statistics(SPECIES)
absences = OBIS.statistics(SPECIES; absence=:only)["records"]
dropped = OBIS.statistics(SPECIES; dropped=:only)["records"]

println("presence records returned by default : ", st["records"])
println("datasets                             : ", st["datasets"])
println(
    "year range                           : ", st["yearrange"][1], "–", st["yearrange"][2]
)
println("absence records, excluded by default : ", absences)
println("dropped records, excluded by default : ", dropped)

records = OBIS.occurrence(SPECIES; progress=true)
println(
    "\nretrieved ",
    OBIS.nrow(records),
    " records, accessed ",
    OBIS.metadata(records).accessed,
)

df = DataFrame(records)

# ---------------------------------------------------------------------------------------
rule("2. groupby: where do the records come from?")

# `combine` over a `groupby` is the ordinary DataFrames idiom; nothing about the OBIS
# result needs special handling, because the columns are already typed.
by_basis = combine(
    groupby(dropmissing(df, :basisOfRecord), :basisOfRecord),
    nrow => :records,
)
sort!(by_basis, :records; rev=true)
println(by_basis)

# Group on dataset_id, not on the citation text: citation strings are supplied by the
# provider and some are missing or shared, which would merge distinct datasets.
by_dataset = combine(groupby(df, :dataset_id), nrow => :records)
sort!(by_dataset, :records; rev=true)
println("\n", OBIS.nrow(records), " records come from ", nrow(by_dataset), " datasets ",
    "(statistics reports ", st["datasets"], "); the largest contributes ",
    by_dataset.records[1], " (",
    round(100 * by_dataset.records[1] / OBIS.nrow(records); digits=1), "%).")

# ---------------------------------------------------------------------------------------
rule("3. pivot: decade against hemisphere")

work = dropmissing(df, [:date_year, :decimalLatitude])
work.decade = (work.date_year .÷ 10) .* 10
work.hemisphere = ifelse.(work.decimalLatitude .>= 0, "northern", "southern")

pivot = unstack(
    combine(groupby(work, [:decade, :hemisphere]), nrow => :records),
    :decade, :hemisphere, :records; fill=0,
)
sort!(pivot, :decade)
recent = filter(:decade => >=(1950), pivot)
println(recent)

# ---------------------------------------------------------------------------------------
rule("4. a statistic worth computing, and one that is not")

# Not worth computing: a trend in record counts over time. It measures observers.
# Worth computing: whether apparent species richness tracks sampling effort across regions.
# One `statistics` call per region returns both, so this costs one request each.

areas = OBIS.area()
lme = [i for i in 1:OBIS.nrow(areas) if !ismissing(areas.type[i]) && areas.type[i] == "lme"]
sample_regions = lme[1:min(26, length(lme))]

region_name = String[]
region_records = Int[]
region_species = Int[]
for i in sample_regions
    s = try
        OBIS.statistics(; areaid=areas.id[i])
    catch err
        err isa OBIS.OBISError || rethrow()
        continue
    end
    (s["records"] > 0 && s["species"] > 0) || continue
    push!(region_name, String(areas.name[i]))
    push!(region_records, Int(s["records"]))
    push!(region_species, Int(s["species"]))
end

regions = DataFrame(; region=region_name, records=region_records, species=region_species)
sort!(regions, :records; rev=true)
println(first(regions, 8))

# Spearman's rank correlation: monotone association without assuming a functional form.
# Implemented here rather than pulled in as a dependency, since it is three lines.
function spearman(x, y)
    rank(v) = invperm(sortperm(v))
    rx, ry = float.(rank(x)), float.(rank(y))
    return cor(rx, ry)
end

rho = spearman(regions.records, regions.species)
# A straight line through the logs: species ~ records^b, the species–effort relationship.
lx, ly = log10.(regions.records), log10.(regions.species)
b = cov(lx, ly) / var(lx)
a = mean(ly) - b * mean(lx)

println("\nacross ", nrow(regions), " large marine ecosystems")
println("  Spearman's rho (records vs species) : ", round(rho; digits=3))
println("  slope of log10(species) on log10(records) : ", round(b; digits=3))
println(
    """
Reading: richness rises with effort, and the slope is well below 1, so a region with ten
times the records does not hold ten times the species — it has been looked at harder.
Any comparison of regional richness that does not account for this is measuring budgets.""",
)

# ---------------------------------------------------------------------------------------
rule("5. Figures")

lon = collect(records.decimalLongitude)
lat = collect(records.decimalLatitude)
keep = .!ismissing.(lon) .& .!ismissing.(lat)

function figure_global(p::Palette)
    fig = Figure(; size=(900, 560))
    Label(fig[1, 1], "$(SPECIES): every record in OBIS"; color=p.ink, fontsize=15,
        font=:bold, halign=:left, tellwidth=false)
    Label(fig[2, 1],
        "$(OBIS.nrow(records)) records from $(st["datasets"]) datasets · accessed $(OBIS.metadata(records).accessed)";
        color=p.ink2, fontsize=12, halign=:left, tellwidth=false)

    ga = GeoAxis(fig[3, 1]; dest="+proj=robin", xgridcolor=p.grid, ygridcolor=p.grid,
        xticklabelsvisible=false, yticklabelsvisible=false)
    poly!(ga, NaturalEarth.naturalearth("land", 110).geometry;
        color=p.land, strokecolor=p.axis, strokewidth=0.5)
    scatter!(ga, lon[keep], lat[keep]; color=(p.series1, 0.35), markersize=3, strokewidth=0)

    Label(fig[4, 1],
        "A cosmopolitan species, but the map is also a map of who is looking: dense off \
        northwest Europe, the Pacific Northwest and Antarctica, thin across the tropics \
        and the southern Indian Ocean.";
        color=p.muted, fontsize=11, halign=:left, justification=:left, tellwidth=false,
        word_wrap=true)
    rowsize!(fig.layout, 3, Relative(0.84))
    rowgap!(fig.layout, 1, 2)
    rowgap!(fig.layout, 2, 8)
    rowgap!(fig.layout, 3, 4)
    return fig
end

# Four seas, each on its own scale, so regional structure is visible where a world map
# shows only a smudge.
# Boxes are chosen to have comparable width-to-height ratios once longitude is scaled by
# cos(latitude), so the four panels come out the same size instead of one being a strip.
const REGIONS = [
    ("Norwegian and Barents Seas", (0.0, 44.0, 62.0, 80.0), 6, 4),
    ("Gulf of Alaska and British Columbia", (-160.0, -122.0, 47.0, 62.0), 6, 3),
    ("Antarctic Peninsula", (-72.0, -50.0, -70.0, -60.0), 4, 2),
    ("Northwest Europe", (-14.0, 12.0, 48.0, 62.0), 4, 2),
]

"Whole-degree tick positions. GeoAxis takes values only; labels come from a formatter."
function degree_ticks(lo, hi, step)
    return collect((ceil(lo / step) * step):step:(floor(hi / step) * step))
end

# Rounding in the formatter is what removes the 2.09e-15 that GeoMakie otherwise prints
# where a tick lands on zero.
degree_labels(vals) = [string(Int(round(v)), "°") for v in vals]

function figure_regions(p::Palette)
    fig = Figure(; size=(940, 700))
    Label(fig[1, 1:2], "$(SPECIES) by region"; color=p.ink, fontsize=15, font=:bold,
        halign=:left, tellwidth=false)
    Label(fig[2, 1:2],
        "Same records, four scales. Each panel is labelled with the count inside its box.";
        color=p.ink2, fontsize=12, halign=:left, tellwidth=false)

    land = NaturalEarth.naturalearth("land", 50).geometry
    for (k, (title, (w, e, s, n), xstep, ystep)) in enumerate(REGIONS)
        row, col = divrem(k - 1, 2) .+ (3, 1)
        inbox = keep .& (lon .>= w) .& (lon .<= e) .& (lat .>= s) .& (lat .<= n)
        ga = GeoAxis(fig[row, col]; dest="+proj=merc", limits=(w, e, s, n),
            title="$(title)  ·  $(count(inbox)) records",
            titlesize=12, titlecolor=p.ink2, titlealign=:left,
            xgridcolor=p.grid, ygridcolor=p.grid,
            xticks=degree_ticks(w, e, xstep), yticks=degree_ticks(s, n, ystep),
            xtickformat=degree_labels, ytickformat=degree_labels,
            xticklabelsize=9, yticklabelsize=9,
            xticklabelcolor=p.muted, yticklabelcolor=p.muted)
        poly!(ga, land; color=p.land, strokecolor=p.axis, strokewidth=0.6)
        scatter!(ga, lon[inbox], lat[inbox]; color=(p.series1, 0.5), markersize=4,
            strokewidth=0)
    end
    rowgap!(fig.layout, 1, 2)
    rowgap!(fig.layout, 2, 10)
    rowgap!(fig.layout, 3, 14)
    colgap!(fig.layout, 1, 24)
    return fig
end

function figure_pivot(p::Palette)
    dec = recent.decade
    north = recent.northern
    south = recent.southern

    fig = Figure(; size=(800, 430))
    ax = Axis(fig[1, 1];
        title="$(SPECIES) records per decade, by hemisphere",
        subtitle="The pivot table from step 3. Both curves are observer effort, not population size",
        xlabel="decade", ylabel="records", xgridvisible=false)
    barplot!(ax, dec .- 1.6, north; width=3.2, color=p.series1, label="northern")
    barplot!(ax, dec .+ 1.6, south; width=3.2, color=p.series2, label="southern")
    axislegend(ax; position=:lt, framevisible=false, labelcolor=p.ink2, labelsize=11,
        patchsize=(12, 12))
    Label(fig[2, 1],
        "The 2020s bar is short because recent surveys have not been published to OBIS \
        yet, not because sightings fell.";
        color=p.muted, fontsize=11, halign=:left, justification=:left, tellwidth=false,
        word_wrap=true)
    rowgap!(fig.layout, 1, 4)
    return fig
end

function figure_effort(p::Palette)
    fig = Figure(; size=(800, 500))
    ax = Axis(fig[1, 1];
        title="Apparent species richness tracks sampling effort",
        subtitle="One point per large marine ecosystem · Spearman's ρ = $(round(rho; digits=2)), slope = $(round(b; digits=2))",
        xlabel="records in OBIS (log scale)", ylabel="species recorded (log scale)",
        xscale=log10, yscale=log10)

    xs = range(minimum(lx), maximum(lx); length=64)
    lines!(ax, 10 .^ xs, 10 .^ (a .+ b .* xs); color=p.series2, linewidth=2,
        linestyle=:dash, label="fitted power law")
    scatter!(ax, regions.records, regions.species; color=(p.series1, 0.8), markersize=10,
        strokewidth=1, strokecolor=p.surface, label="large marine ecosystem")

    # Label the extremes only; a name on every point would be unreadable. Each label points
    # inward, so neither runs off its edge of the axis.
    hi, lo = argmax(regions.records), argmin(regions.records)
    text!(ax, regions.records[hi], regions.species[hi]; text=regions.region[hi] * " ",
        align=(:right, :center), color=p.ink2, fontsize=10, offset=(-8, 0))
    text!(ax, regions.records[lo], regions.species[lo]; text=" " * regions.region[lo],
        align=(:left, :center), color=p.ink2, fontsize=10, offset=(8, 0))
    axislegend(ax; position=:lt, framevisible=false, labelcolor=p.ink2, labelsize=11,
        patchsize=(12, 12))

    Label(fig[2, 1],
        "A slope below 1 means a region with ten times the records does not hold ten times \
        the species. Comparing regional richness without accounting for effort measures \
        survey budgets.";
        color=p.muted, fontsize=11, halign=:left, justification=:left, tellwidth=false,
        word_wrap=true)
    rowgap!(fig.layout, 1, 4)
    return fig
end

mkpath(OUT)
save_both("orca-global", figure_global)
save_both("orca-regions", figure_regions)
save_both("orca-pivot", figure_pivot)
save_both("richness-vs-effort", figure_effort)

mkpath(DOCS_ASSETS)
for f in readdir(OUT)
    endswith(f, ".png") && cp(joinpath(OUT, f), joinpath(DOCS_ASSETS, f); force=true)
end
println("\nDone.")
