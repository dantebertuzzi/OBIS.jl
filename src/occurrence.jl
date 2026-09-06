# The occurrence endpoint.
#
# This is the endpoint that returns observation records, and the one where the package's
# guarantees matter most: a stable typed schema, rights carried on every row, and a refusal
# to quietly page through a query that OBIS would rather serve from its bulk export.

"""
    occurrence(scientificname = nothing; kwargs...) -> OBISTable

Retrieve occurrence records.

Returns an [`OBISTable`](@ref): a Tables.jl-compatible table whose columns are fixed by the
schema, so the same columns appear in the same order for every query, with `missing` where
a record carries no value. Darwin Core fields outside the core schema are preserved per row
in the `extra` column.

Each row carries the licence and citation of the dataset it came from, so
[`citations`](@ref) and [`licenses`](@ref) work on the result without a further query.

# Filters

  - `scientificname`: taxon name at any rank. Also accepted positionally.
  - `taxonid` (alias `aphiaid`): WoRMS AphiaID. Unambiguous where a name is not.
  - `geometry`: WKT, for example `"POLYGON ((2.3 51.8, 2.3 51.6, 2.6 51.6, 2.6 51.8, 2.3 51.8))"`.
  - `startdate`, `enddate`: `Date`, `DateTime`, or `"YYYY-MM-DD"`.
  - `startdepth`, `enddepth`: metres below the surface.
  - `datasetid`, `nodeid`: UUIDs. `instituteid`: OceanExpert ID. `areaid`: OBIS area ID.
  - `flags`: quality flags that must be set. `exclude`: flags to exclude. Either case is
    accepted and normalized.
  - `absence`, `dropped`, `event`: `:exclude` (default), `:include`, or `:only`.
  - `redlist`, `hab`, `wrims`: restrict to IUCN Red List, harmful algal bloom, or WRiMS
    species.
  - `measurementtype`, `measurementvalue`, `measurementunit` and their `*id` forms:
    require a matching measurement.
  - `hasextensions`: require an extension, for example `"DNADerivedData"`.

# Retrieval

  - `limit`: stop after this many records. Records arrive ordered by UUID, which is
    unrelated to date, place or taxon, so a limited pull is an arbitrary subset of the
    matches rather than the earliest or nearest ones.
  - `after`: resume from a record UUID. See [`occurrence_pages`](@ref).
  - `licenses`: look up dataset rights. `true` by default; set `false` to skip the extra
    request, which leaves the `license` columns `missing` without changing the schema.
  - `check_size`: estimate the query first and refuse to page through very large results.
    See [`estimate_size`](@ref).

# Examples

```julia
# A species, with rights attached.
recs = OBIS.occurrence("Abra alba"; limit = 500)

# Absence records: observations where the species was looked for and not found. These are
# available through the API and not through the bulk downloads.
absences = OBIS.occurrence("Abra alba"; absence = :only)

# Records the quality pipeline dropped, to see what a default query leaves out.
dropped = OBIS.occurrence("Abra alba"; dropped = :only)

# An area and a period.
recs = OBIS.occurrence(;
    scientificname = "Delphinidae",
    geometry = "POLYGON ((2.3 51.8, 2.3 51.6, 2.6 51.6, 2.6 51.8, 2.3 51.8))",
    startdate = Date(2010, 1, 1),
    enddate = Date(2020, 12, 31),
)

# Exclude records the pipeline flagged as being on land.
clean = OBIS.occurrence("Abra alba"; exclude = "ON_LAND", limit = 1000)
```
"""
function occurrence(
    scientificname=nothing;
    limit::Union{Nothing,Integer}=nothing,
    after=nothing,
    licenses::Bool=true,
    check_size::Bool=true,
    progress::Union{Nothing,Bool}=nothing,
    kwargs...,
)
    params = build_params(; scientificname=scientificname, kwargs...)

    if check_size && limit === nothing
        guard_query_size(params)
    end

    show_progress = progress === nothing ? CONFIG.progress : progress
    page_size = limit === nothing ? CONFIG.page_size : min(CONFIG.page_size, Int(limit))

    pages = OccurrencePages(
        params,
        page_size,
        after === nothing ? nothing : String(after),
        nothing,
        0,
        0,
        show_progress,
        false,          # licences are attached once, to the assembled table
    )

    parts = OBISTable[]
    collected = 0
    stopped_early = false
    for page in pages
        push!(parts, page)
        collected += nrow(page)
        if limit !== nothing && collected >= limit
            stopped_early = true
            break
        end
    end
    # When the iterator runs to exhaustion it reports completion itself; only a caller-
    # imposed stop still needs a closing line.
    show_progress && stopped_early && finish_progress(pages)

    meta = QueryMeta("occurrence", params, pages.total)
    if isempty(parts)
        return empty_table(OCCURRENCE_SCHEMA, meta)
    end

    tbl = concat_tables(parts, meta)
    limit === nothing || nrow(tbl) <= limit || (tbl = take_rows(tbl, Int(limit)))
    licenses && (tbl = attach_licenses(tbl, params))
    return tbl
end

"""
    occurrence_pages(scientificname = nothing; kwargs...) -> OccurrencePages

Build a lazy, resumable iterator over pages of occurrence records.

Accepts the same filters as [`occurrence`](@ref). Nothing is fetched until iteration
begins, and each iteration yields one page as an [`OBISTable`](@ref), so a query larger than
memory can be processed page by page.

Extra keywords: `page_size` sets records per request (up to $(MAX_PAGE_SIZE)); `after`
resumes from a record UUID; `licenses` attaches dataset rights to every page, which costs
one extra request per page and is therefore off by default.

# Examples

```julia
# Summarize a large query without materializing it.
counts = Dict{String,Int}()
for page in OBIS.occurrence_pages(scientificname = "Mollusca"; page_size = 10_000)
    for name in page.scientificName
        ismissing(name) || (counts[name] = get(counts, name, 0) + 1)
    end
end

# Checkpoint after every page so an interrupted pull can resume.
pages = OBIS.occurrence_pages(scientificname = "Mollusca")
for page in pages
    save(page)
    write("obis.cursor", OBIS.cursor(pages))
end
```
"""
function occurrence_pages(
    scientificname=nothing;
    page_size::Integer=CONFIG.page_size,
    after=nothing,
    licenses::Bool=false,
    progress::Union{Nothing,Bool}=nothing,
    kwargs...,
)
    params = build_params(; scientificname=scientificname, kwargs...)
    return OccurrencePages(
        params,
        validate_size(page_size),
        after === nothing ? nothing : String(after),
        nothing,
        0,
        0,
        progress === nothing ? CONFIG.progress : progress,
        licenses,
    )
end

"""
    occurrence_by_id(id) -> OBISTable

Fetch a single occurrence record by its OBIS record UUID.
"""
function occurrence_by_id(id)
    uuid = validate_uuid(:id, id)
    payload = api_get("occurrence/$(uuid)")
    records = results_of(payload)
    meta = QueryMeta("occurrence/$(uuid)", QueryParams(), length(records))
    return build_table(records, OCCURRENCE_SCHEMA, meta)
end

"""
    empty_table(schema, meta) -> OBISTable

An empty table with the full schema.

A query that matches nothing still returns every column, so downstream code that selects
columns behaves the same whether or not there were records.
"""
function empty_table(schema::Vector{FieldSpec}, meta::QueryMeta)
    names = Symbol[s.name for s in schema]
    columns = AbstractVector[Vector{column_type(s)}(undef, 0) for s in schema]
    push!(names, :extra)
    push!(columns, Dict{Symbol,Any}[])
    return OBISTable(names, columns, meta)
end

"""
    take_rows(t, n) -> OBISTable

The first `n` rows of a table, keeping the schema and provenance.
"""
function take_rows(t::OBISTable, n::Integer)
    n >= nrow(t) && return t
    columns = AbstractVector[c[1:n] for c in _columns(t)]
    return OBISTable(copy(_names(t)), columns, metadata(t))
end
