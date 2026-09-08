# Getting started

## Querying occurrences

[`OceanBIS.occurrence`](@ref) is the main entry point. The first argument is a scientific name
at any rank; everything else is a keyword.

```julia
using OceanBIS, Dates

# By name.
OceanBIS.occurrence("Abra alba"; limit = 100)

# By AphiaID, which is unambiguous where a name is not.
OceanBIS.occurrence(; taxonid = 141433, limit = 100)

# In an area, over a period, within a depth range.
OceanBIS.occurrence(;
    scientificname = "Delphinidae",
    geometry  = "POLYGON ((2.0 52.5, 2.0 51.0, 4.5 51.0, 4.5 52.5, 2.0 52.5))",
    startdate = Date(2010, 1, 1),
    enddate   = Date(2020, 12, 31),
    startdepth = 0,
    enddepth   = 200,
)

# From one dataset, one node, or one institute.
OceanBIS.occurrence(; datasetid = "8acba7e7-2e50-4490-8328-b78a30472508")
OceanBIS.occurrence(; nodeid = "4bf79a01-65a9-4db6-b37b-18434f26ddfc", limit = 100)
OceanBIS.occurrence(; instituteid = 6223, limit = 100)
```

Build a polygon interactively at [wktmap.com](https://wktmap.com) if you do not have one.
The package checks the WKT before sending it, because the API answers unparseable geometry
with an empty result set and no error.

### Selecting record classes

`absence`, `dropped` and `event` take `:exclude` (the default), `:include`, or `:only`.
These are three different questions, which is why they are not booleans.

```julia
OceanBIS.occurrence("Abra alba"; absence = :only)      # only absences
OceanBIS.occurrence("Abra alba"; absence = :include)   # presences and absences together
OceanBIS.occurrence("Abra alba"; dropped = :only)      # records the QC pipeline dropped
```

### Filtering on quality flags

```julia
OceanBIS.occurrence("Abra alba"; exclude = "ON_LAND", limit = 1000)   # drop the flagged ones
OceanBIS.occurrence("Abra alba"; flags = "ON_LAND", limit = 100)      # inspect only those
OceanBIS.occurrence("Abra alba"; exclude = ["ON_LAND", "NO_DEPTH"])
```

Either case works — the package normalizes to the upper-case forms the API matches on.
See [Interpreting OBIS data](interpreting.md) for what the flags mean.

## Working with a result

A result is an [`OceanBIS.OBISTable`](@ref): column-oriented, typed, and Tables.jl-compatible.

```julia
recs = OceanBIS.occurrence("Abra alba"; limit = 500)

OceanBIS.nrow(recs)
OceanBIS.ncol(recs)

recs.scientificName        # by property
recs[:decimalLatitude]     # by name
Tables.columnnames(recs)
Tables.schema(recs)

for row in Tables.rows(recs)
    row.scientificName, row.decimalLatitude
end
```

Columns are concretely typed. Coordinates and depths are `Float64` even though the API
encodes whole values as integers; the interpreted dates are `DateTime`; flags are a
`Set{String}`, empty when no flags were raised, so membership tests need no missing
handling.

```julia
count(fs -> "ON_LAND" in fs, recs.flags)
extrema(skipmissing(recs.decimalLatitude))
```

### Fields outside the core schema

Providers supply Darwin Core terms beyond the core schema, and which of them appear depends
on the query. They are kept per row in `extra` rather than becoming columns, so the main
schema stays the same between queries.

```julia
OceanBIS.extra_names(recs)                    # what is present in this result
OceanBIS.extra_column(recs, :waterBody)       # lift one out, missing where absent

using DataFrames
DataFrame(recs; flatten_extra = true)     # or flatten them all
```

### Provenance

```julia
meta = OceanBIS.metadata(recs)
meta.accessed      # the date to cite
meta.total         # how many records matched, which may exceed what you retrieved
meta.params        # the query, as sent
```

## Other endpoints

```julia
# Which taxa occur here?
OceanBIS.checklist(; geometry = "POLYGON ((2.3 51.8, 2.3 51.6, 2.6 51.6, 2.6 51.8, 2.3 51.8))")
OceanBIS.checklist_redlist(; areaid = 259)

# Taxonomy.
OceanBIS.taxon(141433)
OceanBIS.taxon("Abra alba")

# Datasets, nodes, institutes, areas, countries.
OceanBIS.dataset("Abra alba")
OceanBIS.node()
OceanBIS.institute("Abra alba")
OceanBIS.area()
OceanBIS.country()

# Counts, without retrieving records.
OceanBIS.statistics("Abra alba")
OceanBIS.statistics_years("Abra alba")
OceanBIS.statistics_qc("Abra alba")
OceanBIS.facet("datasetName"; scientificname = "Abra alba")
```

`statistics` accepts the same filters as `occurrence` and counts exactly the records that
query would return, which makes it the cheap way to size a query first.

## Errors

The API reports most failures with a success status, so the package raises them instead.

```julia
OceanBIS.occurrence("Abra albaa")     # OBISNameNotFoundError, not an empty result
OceanBIS.occurrence(; geometry = "NOTWKT")   # OBISValidationError, caught locally
```

An empty result from this package therefore means no records matched — never that the
query was malformed. Every error type is a subtype of [`OceanBIS.OBISError`](@ref).

## Configuration

```julia
OceanBIS.configure!(
    page_size = 10_000,        # fewer, larger requests on a long pull
    progress = true,           # progress while paginating
    request_gap = 0.5,         # seconds between requests
    retries = 8,
)
OceanBIS.config()
```
