# Mapping a coast: the Brazilian shelf

Four maps of one coastline, none of them a scatter of one query. The point of the exercise
is that the interesting maps come from asking the API a different question, not from
plotting the same answer more prettily.

The script is [`examples/brazil.jl`](https://github.com/dantebertuzzi/OceanBIS.jl/blob/main/examples/brazil.jl).
Run it with `julia --project=examples examples/brazil.jl`. Every number and figure below
came from that run; the counts move as OBIS ingests data.

```julia
using OceanBIS, DataFrames, Statistics
```

The first run makes about six hundred small requests and retrieves some 26,000 records.
That is a case for the cache, and not only to save the reruns: OBIS ingests continuously,
so without one the same script run tomorrow draws different maps and nothing kept a copy of
what today's were based on.

```julia
OceanBIS.configure!(cache = OceanBIS.QueryCache())
```

## 1. The region, priced before anything is downloaded

The coast is covered by three OBIS areas, so the region is OBIS's own definition rather than
a hand-drawn box, and the same one their statistics are reported against:

```julia
for id in (40017, 40016, 40015)          # North, East and South Brazil Shelf
    OceanBIS.statistics(; areaid = id)
end
```

```
North Brazil Shelf      77171 records    3518 species   163 datasets  1849–2026
East Brazil Shelf      295880 records    6357 species   179 datasets  1849–2026
South Brazil Shelf     250878 records    4989 species   188 datasets  1648–2026
```

624,000 records is more than the API is meant to serve one client, and none of the four
figures needs them.

## 2. A choropleth that downloads no records at all

`statistics` honours every occurrence filter, `geometry` included, so one cheap request per
grid cell returns that cell's record and species counts. A one-degree grid over the coast
is six hundred requests and almost no data — less traffic than a single page of
occurrences:

```julia
cell(w, s) = "POLYGON (($w $s, $(w+1) $s, $(w+1) $(s+1), $w $(s+1), $w $s))"

st = OceanBIS.statistics(; geometry = cell(-46.0, -24.0))
(st["records"], st["species"])
```

Requesting every cell of the bounding box would waste most of them on the Amazon basin and
the open South Atlantic, so the grid is masked to a corridor five degrees wide around a
coarse coastline polyline, plus a small disc around each of the oceanic island groups —
Fernando de Noronha, São Pedro e São Paulo, and Trindade — which lie outside it.

```
602 cells queried, 580 with records; the busiest holds 74216 records and the emptiest 0.

the six busiest cells:
  -33.0°–-32.0°   -4.0°– -3.0°     74216 records    778 species
  -39.0°–-38.0°  -18.0°–-17.0°     50094 records    953 species
  -42.0°–-41.0°  -23.0°–-22.0°     44393 records   1314 species
  -49.0°–-48.0°  -28.0°–-27.0°     43917 records    787 species
  -46.0°–-45.0°  -24.0°–-23.0°     43291 records   1878 species
  -30.0°–-29.0°  -21.0°–-20.0°     43217 records    515 species
```

Effort spans five orders of magnitude between cells, which is why every colour scale here is
logarithmic; on a linear scale the whole coast would be one colour and São Sebastião
another.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/brazil-effort-dark.png">
  <img alt="Records and species per one-degree cell along the Brazilian coast, on a logarithmic colour scale" src="../assets/brazil-effort.png">
</picture>

The two panels are the same map. The bright cells are not the richest stretches of coast,
they are the ones with a marine laboratory on them — São Sebastião, Cabo Frio, Todos os
Santos — plus the oceanic islands, where one expedition's records have nowhere else to fall.

## 3. Dividing the effort out

Species counts rise with record counts along a power law, the species–effort relation that
[the killer whale example](worked-example.md) fits across large marine ecosystems. Fit it
across cells instead, and the residual says how much richer or poorer each cell is than a
cell of its sampling intensity usually is:

```julia
logrec = log10.(records_per_cell)
logspp = log10.(species_per_cell)
slope  = cov(logrec, logspp) / var(logrec)
resid  = logspp .- ((mean(logspp) - slope * mean(logrec)) .+ slope .* logrec)
```

```
log10(species) = 0.32 + 0.61 · log10(records)
across the 245 cells with at least 100 records, r² = 0.60
```

A slope of 0.61 means a cell with ten times the records holds 4.1 times the species, not
ten times. Cells below a hundred records are left out of both the fit and the figure: a
residual computed on four records is noise, and a map of noise is indistinguishable from a
map of nothing.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/brazil-residual-dark.png">
  <img alt="Departure from the species–effort relation per one-degree cell along the Brazilian coast, on a diverging colour scale" src="../assets/brazil-residual.png">
</picture>

The scale diverges around a meaningful zero — a cell exactly as rich as its record count
predicts — so neutral grey has to read as nothing. A band along the eastern shelf carries
more species than its records predict; several offshore cells and the far south carry
fewer, which is what a cell whose records come mostly from one large, taxonomically narrow
dataset looks like. It is a residual, not a richness estimate: it says a cell is unusual for
its effort, not how many species live there.

## 4. The rank you query at is the question you asked

Two taxa, one retrieval each per shelf:

```julia
corals = vcat((DataFrame(OceanBIS.occurrence("Scleractinia"; areaid = id))
               for id in (40017, 40016, 40015))...)
```

```
Scleractinia   : 17134 records, accessed 2026-09-07
Chondrichthyes : 8731 records, accessed 2026-09-07
```

`Scleractinia` is an order, and querying at that rank quietly answers a different question
than "where are the reefs". The order holds the zooxanthellate reef builders and also the
solitary deep-water corals, which live in cold water and reach the southern end of the
coast:

```julia
south = filter(:decimalLatitude => x -> !ismissing(x) && x < -27.0, corals)
combine(groupby(dropmissing(south, :family), :family), nrow => :records)
```

```
south of 27°S there are 293 Scleractinia records and 0 of them are Mussismilia;
the families down there are
  Caryophylliidae     144
  Cladocoridae         48
  Flabellidae          31
  Dendrophylliidae     31
```

`Mussismilia` — endemic to Brazil, and the genus the Abrolhos reefs are built from — is the
reef half of the answer, and 4,469 of the 17,134 records.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/brazil-corals-dark.png">
  <img alt="Scleractinia records along the Brazilian coast with Mussismilia highlighted, and a zoom on the Abrolhos Bank" src="../assets/brazil-corals.png">
</picture>

Read at the order, the data say corals reach 34°S. Read at the genus, they say the reefs are
tropical and 93% of the reef records sit on one bank. Both answers come out of the same
download; only one of them answers the question most people mean.

## 5. Which part of the exclusive economic zone is covered

`bathymetry` is filled by the OBIS pipeline from a global grid, so it is present on
essentially every record even where the provider reported no depth of its own. Colouring
the shark and ray records by it turns the map into a statement about coverage:

```julia
sharks = vcat((DataFrame(OceanBIS.occurrence("Chondrichthyes"; areaid = id))
               for id in (40017, 40016, 40015))...)
count(d -> d < 200, skipmissing(sharks.bathymetry)) / nrow(sharks)
```

```
seabed depth under the Chondrichthyes records:
  0–50 m         3149   36.1%
  50–200 m       3661   41.9%
  200–1000 m     1549   17.7%
  1000–3000 m     260    3.0%
  > 3000 m        112    1.3%
the shallowest band includes 309 records the depth grid places above sea level.
```

The shallowest band opens downward rather than starting at zero. Some records sit where the
global depth grid says dry land, because a grid cell is coarser than a coastline; they
belong in the shallow band rather than in a footnote, and certainly not silently dropped,
which would make every band a share of a total that is not the number of records.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/brazil-depth-dark.png">
  <img alt="Chondrichthyes records along the Brazilian coast coloured by seabed depth, with a marginal bar chart of the depth bands" src="../assets/brazil-depth.png">
</picture>

77% of the records sit over water shallower than 200 m. Brazil's exclusive economic zone is
mostly abyssal, so on this evidence OBIS's coverage of it is a coverage of the shelf, and
the blank offshore is about ship time rather than about sharks.

## Notes on drawing the maps

Plotting is not part of OceanBIS.jl, and two of the wrinkles below are GeoMakie's rather than
this package's — but they cost an afternoon each, so they are recorded here.

  - **GeoMakie 0.7 does not clip a plot to the axis limits.** A land polygon drawn under a
    regional map bleeds across the rest of the figure and paints over the tick labels. The
    script stacks its content at explicit depths with `translate!`, below the axis
    decorations at `z = 0`, and then covers whatever escaped with four rectangles in the
    surface colour.
  - **A `GeoAxis` draws its frame through its outermost ticks, not at its limits.** Choose
    the extent and the ticks to coincide, or the axis labels end up printed across the
    middle of the map.
  - **Makie strokes a glyph over its fill.** Asking one `text!` for dark letters with a pale
    halo produces pale letters; the halo has to be its own pass underneath. Without it a
    place name crossing from a filled cell onto the background goes from legible to
    invisible halfway through the word.
  - `xtickformat` and `ytickformat` are declared on `GeoAxis` but not used in this version;
    the degree labels come from GeoMakie's own formatter.
