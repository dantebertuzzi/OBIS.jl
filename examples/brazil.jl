# Four maps of the Brazilian coast.
#
#     julia --project=examples examples/brazil.jl
#
# The maps in figures.jl and orcas.jl all do the same thing: retrieve a query and plot its
# records as points. These four deliberately do not.
#
#   1. A choropleth of sampling effort and apparent richness, built entirely from
#      `statistics` — one cheap request per grid cell, not one occurrence downloaded.
#   2. The same cells with effort divided out, which is the only version of a richness map
#      that is about biology rather than about budgets.
#   3. One download read at two taxonomic ranks, which turn out to answer two different
#      questions about where Brazil's reefs are.
#   4. A depth-coloured map with its own marginal, showing which part of the Brazilian
#      exclusive economic zone OBIS actually covers.
#
# The first run makes about 600 small requests and retrieves some 26 000 records, which
# takes a few minutes. It caches into `~/.cache/OceanBIS.jl`, so a second run costs nothing and
# rebuilds exactly the same figures from exactly the same responses — that is what
# `QueryCache` is for, and a script that queries this many times is the case it was written
# for.
#
# Plotting is not part of OceanBIS.jl. CairoMakie, GeoMakie and DataFrames belong to the
# example environment only.

using OceanBIS
using CairoMakie
using GeoMakie
using NaturalEarth
using DataFrames
using Statistics
using Printf

const OUT = joinpath(@__DIR__, "figures")
const DOCS_ASSETS = joinpath(dirname(@__DIR__), "docs", "src", "assets")

include(joinpath(@__DIR__, "theme.jl"))

# Cache every response. Beyond saving the reruns, it is what makes the figures
# reproducible: OBIS ingests continuously, so without this the same script run tomorrow
# draws different maps and there is no copy of what today's were based on.
OceanBIS.configure!(cache=OceanBIS.QueryCache(), progress=true)

rule(s) = println("\n", s, "\n", "-"^length(s))

# The three OBIS areas that cover the Brazilian shelf, north to south. Using the areas
# rather than a hand-drawn bounding box means the region is OBIS's own definition, and the
# same one their statistics are reported against.
const SHELVES = [
    (40017, "North Brazil Shelf"),
    (40016, "East Brazil Shelf"),
    (40015, "South Brazil Shelf"),
]

# The box the choropleth is gridded over, and the cell size.
const W, E, S, N = -54.0, -27.0, -35.0, 5.0
const CELL = 1.0

# The extent the maps are drawn at, a little wider than the box so the coast is not against
# the frame. GeoMakie draws a GeoAxis's frame through its outermost ticks rather than at its
# limits, so the extent and the ticks are chosen to coincide; otherwise the axis labels end
# up printed across the middle of the map.
const EXTENT = (-55.0, -25.0, -35.0, 5.0)
const XTICKS = [-55.0, -45.0, -35.0, -25.0]
const YTICKS = [-35.0, -25.0, -15.0, -5.0, 5.0]

# Places worth naming, so the maps can be read by someone who does not already know the
# coast. `align` and `offset` push each label into open water rather than over the land.
const PLACES = [
    ("Foz do Amazonas", -48.5, 0.6, (:left, :center), (7, 0)),
    ("Fernando de Noronha", -32.4, -3.9, (:right, :bottom), (-7, 5)),
    ("Recife", -34.9, -8.1, (:left, :center), (7, 0)),
    ("Todos os Santos", -38.5, -13.0, (:left, :center), (7, 0)),
    ("Abrolhos", -38.7, -17.9, (:left, :center), (7, 0)),
    ("Trindade", -29.3, -20.5, (:right, :center), (-7, 0)),
    ("Cabo Frio", -42.0, -22.9, (:left, :bottom), (7, 4)),
    ("São Sebastião", -45.4, -23.8, (:right, :top), (-7, -4)),
    ("Rio Grande", -52.1, -32.1, (:left, :top), (7, -4)),
]

# ---------------------------------------------------------------------------------------
rule("1. The region, priced before anything is downloaded")

for (id, name) in SHELVES
    st = OceanBIS.statistics(; areaid=id)
    @printf(
        "%-20s %8d records  %6d species  %4d datasets  %d–%d\n",
        name, st["records"], st["species"], st["datasets"],
        st["yearrange"][1], st["yearrange"][2],
    )
end

# ---------------------------------------------------------------------------------------
rule("2. A choropleth without downloading a single record")

# `statistics` honours `geometry`, so one request per cell returns that cell's record and
# species counts. Six hundred requests is a lot of requests but almost no data: the whole
# grid below costs less than a single page of occurrences.
#
# Requesting every cell of a 27° × 40° box would be 1080 requests, most of them over the
# Amazon basin or the open South Atlantic. Instead the grid is masked to a corridor around
# the coastline and around the oceanic islands — five degrees, roughly the width of the
# exclusive economic zone plus a margin. The coastline below is a coarse polyline, adequate
# for a mask and not pretending to be a boundary.
const COASTLINE = [
    (-51.6, 4.4), (-50.0, 2.0), (-48.5, 0.0), (-47.0, -0.7), (-44.3, -2.5),
    (-42.0, -2.8), (-38.5, -3.7), (-37.0, -4.9), (-35.2, -5.8), (-34.8, -7.1),
    (-34.9, -8.05), (-35.7, -9.7), (-37.0, -11.0), (-38.5, -13.0), (-39.0, -15.0),
    (-39.2, -17.7), (-40.3, -20.3), (-41.0, -21.8), (-42.0, -22.9), (-43.2, -23.0),
    (-45.1, -23.4), (-46.3, -24.0), (-48.5, -25.5), (-48.5, -27.6), (-49.7, -29.3),
    (-52.1, -32.1), (-53.4, -33.7),
]
# The three island groups far enough offshore to fall outside that corridor. They are in
# the grid because they are the most distinctive thing on the finished map.
const OFFSHORE = [(-32.42, -3.85), (-29.35, 0.92), (-29.33, -20.5)]

"Distance in degrees from `(x, y)` to the segment `a–b`, with longitude scaled by cos φ."
function segment_distance(x, y, ax, ay, bx, by)
    k = cosd((ay + by) / 2)
    dx, dy = (bx - ax) * k, by - ay
    len2 = dx^2 + dy^2
    t = len2 == 0 ? 0.0 : clamp(((x - ax) * k * dx + (y - ay) * dy) / len2, 0.0, 1.0)
    return hypot((x - (ax + t * (bx - ax))) * k, y - (ay + t * (by - ay)))
end

function in_corridor(x, y)
    coast = minimum(
        segment_distance(x, y, COASTLINE[i]..., COASTLINE[i + 1]...)
        for i in 1:(length(COASTLINE) - 1)
    )
    coast <= 5.0 && return true
    return minimum(hypot((x - a) * cosd(b), y - b) for (a, b) in OFFSHORE) <= 2.5
end

cell_wkt(w, s) =
    "POLYGON (($w $s, $(w + CELL) $s, $(w + CELL) $(s + CELL), " *
    "$w $(s + CELL), $w $s))"

struct GridCell
    w::Float64
    s::Float64
    records::Int
    species::Int
end

const ORIGINS = [
    (w, s)
    for w in W:CELL:(E - CELL), s in S:CELL:(N - CELL)
    if in_corridor(w + CELL / 2, s + CELL / 2)
]

function build_grid()
    cells = GridCell[]
    for (w, s) in ORIGINS
        st = try
            OceanBIS.statistics(; geometry=cell_wkt(w, s))
        catch err
            err isa OceanBIS.OBISError || rethrow()
            continue
        end
        push!(cells, GridCell(w, s, Int(st["records"]), Int(st["species"])))
    end
    return cells
end

# The progress indicator is for paging through occurrences; six hundred tiny requests print
# nothing useful, so it is off for this stretch.
OceanBIS.configure!(progress=false)
println("querying ", length(ORIGINS), " cells…")
grid = build_grid()
OceanBIS.configure!(progress=true)

nonempty = filter(c -> c.records > 0 && c.species > 0, grid)
println(
    length(grid), " cells queried, ", length(nonempty), " with records; ",
    "the busiest holds ", maximum(c -> c.records, nonempty), " records and ",
    "the emptiest ", minimum(c -> c.records, grid), ".",
)

# Effort spans five orders of magnitude across cells, which is why every colour scale below
# is logarithmic. On a linear scale the whole coast would be one colour and São Sebastião
# another.
let top = sort(nonempty; by=c -> -c.records)[1:6]
    println("\nthe six busiest cells:")
    for c in top
        @printf(
            "  %5.1f°–%5.1f°  %5.1f°–%5.1f°   %7d records  %5d species\n",
            c.w, c.w + CELL, c.s, c.s + CELL, c.records, c.species
        )
    end
end

# ---------------------------------------------------------------------------------------
rule("3. Dividing the effort out")

# Species counts rise with record counts along a power law — the species–effort relation
# that examples/orcas.jl fits across large marine ecosystems. Fitting it across cells and
# taking the residual gives, for each cell, how much richer or poorer it is than a cell of
# its sampling intensity usually is. That residual is the part of a richness map that is
# not simply a map of where the boats went.
#
# A residual computed on a cell holding four records is noise, and a map of noise is
# indistinguishable from a map of nothing. Cells below this are left out of both the fit
# and the figure, which is a choice worth stating rather than hiding.
const MIN_RECORDS = 100
const FITTED = filter(c -> c.records >= MIN_RECORDS && c.species > 0, grid)

const LOGREC = log10.([c.records for c in FITTED])
const LOGSPP = log10.([c.species for c in FITTED])
const SLOPE = cov(LOGREC, LOGSPP) / var(LOGREC)
const INTERCEPT = mean(LOGSPP) - SLOPE * mean(LOGREC)
const RESIDUAL = LOGSPP .- (INTERCEPT .+ SLOPE .* LOGREC)

@printf(
    "log10(species) = %.2f + %.2f · log10(records)   across the %d cells with at least \
%d records, r² = %.2f\n",
    INTERCEPT, SLOPE, length(FITTED), MIN_RECORDS, cor(LOGREC, LOGSPP)^2
)
println(
    "A slope of ", round(SLOPE; digits=2), " means a cell with ten times the records ",
    "holds ", round(10^SLOPE; digits=1), " times the species, not ten times. What is ",
    "left over is the map worth looking at.",
)

# ---------------------------------------------------------------------------------------
rule("4. Two taxa, retrieved once each per shelf")

"Retrieve `name` across the three shelves as one DataFrame, with the access date the
tables carry. The date belongs to the data, not to the day the figure was drawn."
function shelf_records(name)
    tables = [OceanBIS.occurrence(name; areaid=id) for (id, _) in SHELVES]
    accessed = maximum(OceanBIS.metadata(t).accessed for t in tables)
    return vcat(DataFrame.(tables)...), accessed
end

corals, corals_accessed = shelf_records("Scleractinia")
sharks, sharks_accessed = shelf_records("Chondrichthyes")
println("\nScleractinia   : ", nrow(corals), " records, accessed ", corals_accessed)
println("Chondrichthyes : ", nrow(sharks), " records, accessed ", sharks_accessed)

# `Scleractinia` is an order, and querying at that rank quietly answers a different
# question than "where are the reefs". The order contains the zooxanthellate reef builders
# and also the solitary, azooxanthellate deep-water corals, which live in cold water and
# reach the southern end of the coast. `Mussismilia` — endemic to Brazil, and the genus the
# Abrolhos reefs are built from — is the reef half of the answer.
const CORALS_SOUTH = filter(
    :decimalLatitude => x -> !ismissing(x) && x < -27.0, corals
)
const SOUTHERN_FAMILIES = sort(
    combine(groupby(dropmissing(CORALS_SOUTH, :family), :family), nrow => :records),
    :records; rev=true,
)
const REEF = filter(:genus => isequal("Mussismilia"), corals)

println("\nof the ", nrow(corals), " Scleractinia records, ", nrow(REEF),
        " are Mussismilia, the endemic reef-building genus.")
println("south of 27°S there are ", nrow(CORALS_SOUTH), " Scleractinia records and ",
        count(x -> !ismissing(x) && x < -27.0, REEF.decimalLatitude),
        " of them are Mussismilia; the families down there are")
for r in eachrow(first(SOUTHERN_FAMILIES, 4))
    @printf("  %-18s %4d\n", r.family, r.records)
end
println(
    "none of which build the Brazilian reefs. Read at the order, the data say corals ",
    "reach 34°S; read at the genus, the reefs stop in the tropics.",
)

# Depth of the seabed under each shark record. `bathymetry` is filled by the OBIS pipeline
# from a global grid, so it is present on essentially every record even where the provider
# reported no depth of its own.
const SHARK_BATHY = collect(skipmissing(sharks.bathymetry))
# The shallowest band opens downward rather than starting at zero: some records sit where
# the global depth grid says dry land, because a grid cell is coarser than a coastline.
# They belong in the shallow band, not in a footnote, and certainly not silently dropped —
# every band would then be a share of a total that is not the number of records.
const DEPTH_BANDS = [
    ("0–50 m", -Inf, 50.0),
    ("50–200 m", 50.0, 200.0),
    ("200–1000 m", 200.0, 1000.0),
    ("1000–3000 m", 1000.0, 3000.0),
    ("> 3000 m", 3000.0, Inf),
]
const BAND_COUNTS = [count(d -> lo <= d < hi, SHARK_BATHY) for (_, lo, hi) in DEPTH_BANDS]
println("\nseabed depth under the Chondrichthyes records:")
for ((label, _, _), n) in zip(DEPTH_BANDS, BAND_COUNTS)
    @printf("  %-12s %6d  %5.1f%%\n", label, n, 100n / length(SHARK_BATHY))
end
println(
    "the shallowest band includes ", count(<=(0), SHARK_BATHY),
    " records the depth grid places above sea level.",
)

# ---------------------------------------------------------------------------------------
rule("5. Figures")

const LAND = NaturalEarth.naturalearth("land", 10).geometry

"A cell as a polygon. Cell edges are lines of constant longitude and latitude, which stay
straight under Mercator, so four corners are exact rather than an approximation."
cell_polygon(c::GridCell) = Makie.Polygon(
    Point2f[
        (c.w, c.s),
        (c.w + CELL, c.s),
        (c.w + CELL, c.s + CELL),
        (c.w, c.s + CELL),
    ],
)

# GeoMakie 0.7 does not clip a plot to the axis limits: a land polygon drawn under a
# regional map bleeds across the rest of the figure and paints over the tick labels, which
# is why the panels below stack their content at explicit depths and then cover whatever
# escaped. Decorations sit at z = 0, so everything the map draws goes below that.
const Z_CELLS, Z_LAND, Z_POINTS, Z_MASK = -40, -30, -20, -10

"Position `v` on `grad`, clamped to `[lo, hi]`."
ramp_at(grad, v, lo, hi) = grad[clamp((v - lo) / (hi - lo), 0, 1)]

"A GeoAxis over the Brazilian coast, at the shared extent and ticks."
function coast_axis(
    p::Palette, pos; limits=EXTENT, xticks=XTICKS, yticks=YTICKS, kwargs...,
)
    ga = GeoAxis(
        pos;
        dest="+proj=merc",
        limits=limits,
        xticks=xticks,
        yticks=yticks,
        xgridcolor=p.grid,
        ygridcolor=p.grid,
        xticklabelsize=10,
        yticklabelsize=10,
        xticklabelcolor=p.muted,
        yticklabelcolor=p.muted,
        kwargs...,
    )
    return ga
end

function draw_land!(ga, p::Palette; strokewidth=0.6)
    plt = poly!(ga, LAND; color=p.landfill, strokecolor=p.axis, strokewidth=strokewidth)
    translate!(plt, 0, 0, Z_LAND)
    return plt
end

"Hide everything that escaped the axis limits, behind the tick labels and the grid."
function mask_outside!(ga, p::Palette, limits=EXTENT)
    w, e, s, n = limits
    rect(x0, x1, y0, y1) =
        Makie.Polygon(Point2f[(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    plt = poly!(
        ga,
        [
            rect(-179.9, w, -85.0, 85.0),
            rect(e, 179.9, -85.0, 85.0),
            rect(w, e, -85.0, s),
            rect(w, e, n, 85.0),
        ];
        color=p.surface, strokewidth=0,
    )
    translate!(plt, 0, 0, Z_MASK)
    return plt
end

"Name the places inside the axis limits. Every label is a dot plus text, never a colour.

Each label is drawn twice. Makie strokes a glyph *over* its fill, so asking one `text!` for
dark letters with a pale halo produces pale letters; the halo has to be its own pass
underneath. Without it a label crossing from a filled cell onto the background changes from
legible to invisible halfway through the word."
function label_places!(ga, p::Palette; limits=EXTENT, fontsize=10, only=nothing)
    w, e, s, n = limits
    for (name, x, y, align, offset) in PLACES
        only === nothing || name in only || continue
        (w <= x <= e && s <= y <= n) || continue
        text!(
            ga, x, y;
            text=name, align=align, offset=offset, fontsize=fontsize, color=p.surface,
            strokecolor=p.surface, strokewidth=2.5,
        )
        text!(
            ga, x, y;
            text=name, align=align, offset=offset, fontsize=fontsize, color=p.ink,
        )
        scatter!(
            ga, [x], [y];
            color=p.ink, markersize=4, strokewidth=1, strokecolor=p.surface,
        )
    end
    return nothing
end

# --- Figure 1: effort and apparent richness, side by side --------------------------------
#
# Two panels of the same cells on two sequential scales. The point is that they are the
# same map: whatever OBIS says about where Brazilian marine biodiversity is, it says first
# about where the marine laboratories are.

function figure_grid(p::Palette)
    grad = cgrad(Makie.to_color.(p.seq))
    polys = cell_polygon.(grid)

    fig = Figure(; size=(900, 780))
    Label(
        fig[1, 1:2], "The Brazilian shelf, one degree at a time";
        color=p.ink, fontsize=15, font=:bold, halign=:left, tellwidth=false,
    )
    Label(
        fig[2, 1:2],
        "$(length(grid)) cells, each priced by one `statistics` request · no occurrence \
        record was downloaded for this figure";
        color=p.ink2, fontsize=12, halign=:left, tellwidth=false,
    )

    for (col, (counts, title)) in enumerate((
        ([c.records for c in grid], "records"),
        ([c.species for c in grid], "species"),
    ))
        lo, hi = 0.0, log10(maximum(counts))
        colors = [
            v == 0 ? Makie.to_color(p.surface) : ramp_at(grad, log10(v), lo, hi)
            for v in counts
        ]
        ga = coast_axis(
            p, fig[3, col];
            title=title, titlesize=12, titlecolor=p.ink2, titlealign=:left,
        )
        # Cells first, land over them, so the corridor's inland half is hidden and the
        # coastline stays the reference the eye uses.
        cells = poly!(
            ga, polys; color=colors, strokecolor=(p.grid, 0.55), strokewidth=0.3
        )
        translate!(cells, 0, 0, Z_CELLS)
        draw_land!(ga, p)
        mask_outside!(ga, p)
        col == 1 && label_places!(ga, p)
        Colorbar(
            fig[4, col];
            colormap=grad, colorrange=(1, maximum(counts)), scale=log10,
            vertical=false, flipaxis=false, height=9, ticklabelsize=9,
            ticklabelcolor=p.muted, tickcolor=p.muted, spinewidth=0,
            label="$(title) per cell", labelsize=10, labelcolor=p.ink2,
        )
    end

    Label(
        fig[5, 1:2],
        "The bright cells are not the richest stretches of coast, they are the ones with a \
        marine laboratory on them — São Sebastião, Cabo Frio, Todos os Santos — plus the \
        oceanic islands, where a single expedition's records have nowhere else to fall. \
        Cells drawn in the background colour were queried and returned nothing.";
        color=p.muted, fontsize=11, halign=:left, justification=:left, tellwidth=false,
        word_wrap=true,
    )

    rowsize!(fig.layout, 3, Relative(0.80))
    rowgap!(fig.layout, 1, 2)
    rowgap!(fig.layout, 2, 10)
    rowgap!(fig.layout, 3, 6)
    rowgap!(fig.layout, 4, 6)
    colgap!(fig.layout, 1, 20)
    return fig
end

# --- Figure 2: what is left once effort is divided out -----------------------------------
#
# A diverging scale, because the quantity has a meaningful zero: a cell exactly as rich as
# its record count predicts. Neutral grey is that zero, and it has to read as nothing.

function figure_residual(p::Palette)
    grad = cgrad(Makie.to_color.(p.div))
    span = maximum(abs, RESIDUAL)
    colors = [ramp_at(grad, r, -span, span) for r in RESIDUAL]

    fig = Figure(; size=(600, 840))
    Label(
        fig[1, 1], "Richer or poorer than its sampling predicts";
        color=p.ink, fontsize=15, font=:bold, halign=:left, tellwidth=false,
    )
    Label(
        fig[2, 1],
        @sprintf(
            "slope %.2f · r² %.2f · the %d cells holding at least %d records",
            SLOPE, cor(LOGREC, LOGSPP)^2, length(FITTED), MIN_RECORDS
        );
        color=p.ink2, fontsize=12, halign=:left, tellwidth=false,
    )

    ga = coast_axis(p, fig[3, 1])
    cells = poly!(
        ga, cell_polygon.(FITTED);
        color=colors, strokecolor=(p.grid, 0.55), strokewidth=0.3,
    )
    translate!(cells, 0, 0, Z_CELLS)
    draw_land!(ga, p)
    mask_outside!(ga, p)
    label_places!(ga, p)

    Colorbar(
        fig[4, 1];
        colormap=grad, colorrange=(-span, span),
        vertical=false, flipaxis=false, height=9, ticklabelsize=9,
        ticklabelcolor=p.muted, tickcolor=p.muted, spinewidth=0,
        ticks=([-span, 0, span], ["fewer species", "as predicted", "more species"]),
        label="departure from the species–effort relation", labelsize=10, labelcolor=p.ink2,
    )

    Label(
        fig[5, 1],
        "The same cells with effort taken out. A band along the eastern shelf — Todos os \
        Santos, Abrolhos, Cabo Frio — carries more species than its record count predicts; \
        several offshore cells and the far south carry fewer, which is what a cell whose \
        records come mostly from one large, taxonomically narrow dataset looks like. This \
        is a residual, not a richness estimate: it says a cell is unusual for its effort, \
        not how many species live there.";
        color=p.muted, fontsize=11, halign=:left, justification=:left, tellwidth=false,
        word_wrap=true,
    )

    rowsize!(fig.layout, 3, Relative(0.82))
    rowgap!(fig.layout, 1, 2)
    rowgap!(fig.layout, 2, 8)
    rowgap!(fig.layout, 3, 6)
    rowgap!(fig.layout, 4, 6)
    return fig
end

# --- Figure 3: the rank you query at is the question you asked ---------------------------
#
# Two categorical hues carrying one distinction, with a legend and a zoom panel. The zoom
# box is drawn on the parent map rather than left implicit, so the two panels are visibly
# the same data at two scales.

const ABROLHOS = (-40.0, -37.0, -19.0, -16.0)

function figure_corals(p::Palette)
    lon = collect(corals.decimalLongitude)
    lat = collect(corals.decimalLatitude)
    keep = .!ismissing.(lon) .& .!ismissing.(lat)
    reef = keep .& (coalesce.(corals.genus, "") .== "Mussismilia")
    other = keep .& .!reef
    w, e, s, n = ABROLHOS
    inbox(sel) = sel .& (lon .>= w) .& (lon .<= e) .& (lat .>= s) .& (lat .<= n)

    fig = Figure(; size=(940, 760))
    Label(
        fig[1, 1:2], "One query, two very different questions";
        color=p.ink, fontsize=15, font=:bold, halign=:left, tellwidth=false,
    )
    Label(
        fig[2, 1:2],
        "$(count(keep)) Scleractinia records across the three Brazilian shelves · \
        accessed $(corals_accessed)";
        color=p.ink2, fontsize=12, halign=:left, tellwidth=false,
    )

    function draw!(ax, big)
        draw_land!(ax, p; strokewidth=big ? 0.6 : 0.8)
        for (sel, color, size, label) in (
            (other, (p.series1, big ? 0.4 : 0.5), big ? 4 : 6,
             "Scleractinia, other genera  ($(count(other)))"),
            (reef, Makie.to_color(p.series2), big ? 4.5 : 6.5,
             "Mussismilia, the endemic reef builder  ($(count(reef)))"),
        )
            plt = scatter!(
                ax, lon[sel], lat[sel];
                color=color, markersize=size, strokewidth=0, label=label,
            )
            translate!(plt, 0, 0, Z_POINTS)
        end
        mask_outside!(ax, p, big ? EXTENT : ABROLHOS)
        return nothing
    end

    ga = coast_axis(p, fig[3, 1])
    draw!(ga, true)
    # 27°S: south of this line the order is present and the reef genus is all but absent.
    lines!(
        ga, [EXTENT[1], EXTENT[2]], [-27.0, -27.0];
        color=p.ink2, linewidth=1.2, linestyle=:dash,
    )
    text!(
        ga, EXTENT[2], -27.0;
        text="27°S ", align=(:right, :bottom), offset=(-6, 4), fontsize=10, color=p.ink2,
    )
    lines!(ga, [w, e, e, w, w], [s, s, n, n, s]; color=p.ink2, linewidth=1.2)
    label_places!(ga, p; only=["Fernando de Noronha", "Rio Grande"])

    gb = coast_axis(
        p, fig[3, 2];
        limits=ABROLHOS,
        xticks=collect(-40.0:1.0:-37.0), yticks=collect(-19.0:1.0:-16.0),
        title="the Abrolhos Bank  ·  $(count(inbox(keep))) records, \
               $(count(inbox(reef))) of them Mussismilia",
        titlesize=12, titlecolor=p.ink2, titlealign=:left,
    )
    draw!(gb, false)

    Legend(
        fig[4, 1:2], ga;
        orientation=:horizontal, framevisible=false, labelcolor=p.ink2, labelsize=11,
        patchsize=(12, 12), halign=:left, padding=(0, 0, 0, 0), unique=true,
    )
    Label(
        fig[5, 1:2],
        @sprintf(
            "Scleractinia is an order, and it holds both the reef builders and the \
             solitary deep-water corals. South of 27°S the order is still present — %d \
             records, in families such as %s — while the endemic reef genus is \
             not. Query the order and the answer is \"corals reach the Uruguayan \
             border\"; query the genus and it is \"the reefs are tropical, and %d%% of \
             the reef records are on one bank\". Both are in the same download.",
            nrow(CORALS_SOUTH),
            join(first(SOUTHERN_FAMILIES.family, 3), ", ", " and "),
            round(Int, 100 * count(inbox(reef)) / max(count(reef), 1))
        );
        color=p.muted, fontsize=11, halign=:left, justification=:left, tellwidth=false,
        word_wrap=true,
    )

    colsize!(fig.layout, 1, Relative(0.58))
    rowsize!(fig.layout, 3, Relative(0.80))
    rowgap!(fig.layout, 1, 2)
    rowgap!(fig.layout, 2, 10)
    rowgap!(fig.layout, 3, 6)
    rowgap!(fig.layout, 4, 2)
    colgap!(fig.layout, 1, 22)
    return fig
end

# --- Figure 4: the covered part of the Blue Amazon ----------------------------------------
#
# A map plus its own marginal: the colour scale and the bar chart encode the same variable,
# so the map shows where and the bars show how much.

function figure_depth(p::Palette)
    lon = collect(sharks.decimalLongitude)
    lat = collect(sharks.decimalLatitude)
    bathy = collect(sharks.bathymetry)
    keep = .!ismissing.(lon) .& .!ismissing.(lat) .& .!ismissing.(bathy)
    # Depths at or above sea level are the pipeline's grid disagreeing with the record's
    # position, not a shark on a hill; they are drawn at the shallowest step rather than
    # dropped, because a log scale has no room for them.
    depth = [max(Float64(d), 1.0) for d in bathy[keep]]

    grad = cgrad(Makie.to_color.(p.seq))
    lo, hi = 0.0, log10(5000)
    colors = [ramp_at(grad, log10(d), lo, hi) for d in depth]
    order = sortperm(depth)   # deep records last, so they are not hidden by the shelf

    fig = Figure(; size=(880, 760))
    Label(
        fig[1, 1:2], "Sharks and rays, over the seabed they were recorded above";
        color=p.ink, fontsize=15, font=:bold, halign=:left, tellwidth=false,
    )
    Label(
        fig[2, 1:2],
        "$(count(keep)) Chondrichthyes records · accessed $(sharks_accessed) · colour is \
        `bathymetry`, the depth the OBIS pipeline reads off a global grid at each \
        record's position";
        color=p.ink2, fontsize=12, halign=:left, tellwidth=false,
    )

    ga = coast_axis(p, fig[3, 1])
    draw_land!(ga, p)
    pts = scatter!(
        ga, lon[keep][order], lat[keep][order];
        color=colors[order], markersize=5, strokewidth=0.25, strokecolor=(p.surface, 0.6),
    )
    translate!(pts, 0, 0, Z_POINTS)
    mask_outside!(ga, p)
    label_places!(ga, p; only=["Foz do Amazonas", "Cabo Frio", "Rio Grande", "Trindade"])
    Colorbar(
        fig[4, 1];
        colormap=grad, colorrange=(1, 5000), scale=log10,
        vertical=false, flipaxis=false, height=9, ticklabelsize=9,
        ticks=([10, 100, 1000, 5000], ["10 m", "100 m", "1000 m", "5000 m"]),
        ticklabelcolor=p.muted, tickcolor=p.muted, spinewidth=0,
        label="seabed depth", labelsize=10, labelcolor=p.ink2,
    )

    # A fixed height keeps five bars from being stretched over the height of a map; the
    # marginal is a companion to the map, not a second panel of equal weight.
    ax = Axis(
        fig[3, 2];
        height=300, valign=:center, tellheight=false,
        title="share of records", titlesize=12, titlecolor=p.ink2, titlealign=:left,
        yticks=(1:length(DEPTH_BANDS), [b[1] for b in reverse(DEPTH_BANDS)]),
        xlabel="% of records", ygridvisible=false,
    )
    # Plotted bottom-up, so the bands are reversed to put the shallowest at the top.
    share = reverse(100 .* BAND_COUNTS ./ sum(BAND_COUNTS))
    # One variable, one hue: each bar takes the step of the map's ramp at its band's
    # midpoint, so the marginal and the map are read on the same scale.
    barcolors = [
        ramp_at(grad, log10(sqrt(max(band_lo, 1.0) * min(band_hi, 5000.0))), lo, hi)
        for (_, band_lo, band_hi) in reverse(DEPTH_BANDS)
    ]
    barplot!(ax, 1:length(share), share; direction=:x, color=barcolors, width=0.62)
    for (i, v) in enumerate(share)
        text!(
            ax, v, i; text=@sprintf(" %.1f%%", v), align=(:left, :center),
            color=p.ink2, fontsize=10,
        )
    end
    xlims!(ax, 0, maximum(share) * 1.25)
    hidespines!(ax, :l)

    Label(
        fig[5, 1:2],
        @sprintf(
            "%.0f%% of the records sit over water shallower than 200 m. Brazil's exclusive \
             economic zone is mostly abyssal, and on this evidence OBIS's coverage of it \
             is a coverage of the shelf; the blank offshore is about ship time, \
             not about sharks.",
            sum(share[(end - 1):end])
        );
        color=p.muted, fontsize=11, halign=:left, justification=:left, tellwidth=false,
        word_wrap=true,
    )

    colsize!(fig.layout, 1, Relative(0.48))
    rowsize!(fig.layout, 3, Relative(0.82))
    rowgap!(fig.layout, 1, 2)
    rowgap!(fig.layout, 2, 10)
    rowgap!(fig.layout, 3, 6)
    rowgap!(fig.layout, 4, 6)
    colgap!(fig.layout, 1, 26)
    return fig
end

# --- Run ---------------------------------------------------------------------------------

mkpath(OUT)
println("Rendering…")
save_both("brazil-effort", figure_grid)
save_both("brazil-residual", figure_residual)
save_both("brazil-corals", figure_corals)
save_both("brazil-depth", figure_depth)

mkpath(DOCS_ASSETS)
for f in readdir(OUT)
    endswith(f, ".png") && cp(joinpath(OUT, f), joinpath(DOCS_ASSETS, f); force=true)
end
println("\nDone.")
