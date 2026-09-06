# The remaining endpoints: taxon, checklist, node, institute, area, country, metrics.

"""
    taxon(id) -> OBISTable

Look up a taxon by WoRMS AphiaID or by exact scientific name.

An AphiaID is unambiguous; a name is not, and the API matches it exactly rather than
fuzzily. There is no taxon *search* endpoint — use [`checklist`](@ref) to discover which
taxa occur in a selection.

```julia
julia> t = OBIS.taxon(141433);       # by AphiaID

julia> t = OBIS.taxon("Abra alba");  # by exact name
```
"""
function taxon(id::Integer)
    payload = api_get("taxon/$(Int(id))")
    records = results_of(payload)
    meta = QueryMeta("taxon/$(Int(id))", QueryParams(), total_of(payload, length(records)))
    return build_table(records, TAXON_SCHEMA, meta)
end

function taxon(name::AbstractString)
    s = strip(String(name))
    isempty(s) && throw(
        OBISValidationError(:name, name, "Provide a scientific name or an AphiaID.")
    )
    path = "taxon/" * HTTP.escapeuri(s)
    payload = api_get(path)
    records = results_of(payload)
    meta = QueryMeta(path, QueryParams(), total_of(payload, length(records)))
    return build_table(records, TAXON_SCHEMA, meta)
end

"""
    taxon_annotations(; scientificname = nothing, kwargs...) -> Vector

Annotations the WoRMS team made on scientific names that OBIS could not match
automatically.

These explain why a name carries `NO_MATCH` or a `WORMS_ANNOTATION_*` flag, and whether it
can be fixed.
"""
function taxon_annotations(; scientificname=nothing, kwargs...)
    params = build_params(; scientificname=scientificname, kwargs...)
    return json_to_julia(api_get("taxon/annotations", params))
end

"""
    checklist(scientificname = nothing; kwargs...) -> OBISTable

Build a species checklist for a selection.

Accepts the same filters as [`occurrence`](@ref), and returns one row per taxon with the
number of records supporting it. This is the way to find out which taxa occur somewhere;
the record counts are counts of observations, which reflect how much sampling has happened
there as much as what lives there.

```julia
# What has been recorded in this polygon?
list = OBIS.checklist(;
    geometry = "POLYGON ((2.3 51.8, 2.3 51.6, 2.6 51.6, 2.6 51.8, 2.3 51.8))"
)

# Red List species in the same area.
OBIS.checklist_redlist(; geometry = "POLYGON ((2.3 51.8, 2.3 51.6, 2.6 51.6, 2.6 51.8, 2.3 51.8))")
```
"""
checklist(scientificname=nothing; kwargs...) =
    checklist_endpoint("checklist", scientificname; kwargs...)

"""
    checklist_redlist(scientificname = nothing; kwargs...) -> OBISTable

Checklist restricted to IUCN Red List species.
"""
checklist_redlist(scientificname=nothing; kwargs...) =
    checklist_endpoint("checklist/redlist", scientificname; kwargs...)

"""
    checklist_newest(scientificname = nothing; kwargs...) -> OBISTable

Checklist of the most recently added species in a selection.
"""
checklist_newest(scientificname=nothing; kwargs...) =
    checklist_endpoint("checklist/newest", scientificname; kwargs...)

function checklist_endpoint(path::AbstractString, scientificname; kwargs...)
    params = build_params(; scientificname=scientificname, kwargs...)
    payload = api_get(path, params)
    records = results_of(payload)
    meta = QueryMeta(path, params, total_of(payload, length(records)))
    return build_table(records, TAXON_SCHEMA, meta)
end

"""
    node(id = nothing) -> OBISTable

List OBIS nodes, or fetch one by UUID.

Nodes are the regional and thematic partners that curate the data. A node UUID is the
`nodeid` filter accepted elsewhere.

```julia
julia> nodes = OBIS.node();          # all nodes

julia> n = OBIS.node("4bf79a01-65a9-4db6-b37b-18434f26ddfc");
```
"""
function node(id=nothing)
    path = id === nothing ? "node" : "node/" * validate_uuid(:id, id)
    payload = api_get(path)
    records = results_of(payload)
    meta = QueryMeta(path, QueryParams(), total_of(payload, length(records)))
    return build_table(records, NODE_SCHEMA, meta)
end

"""
    node_activities(id) -> Vector

Activities recorded for a node.
"""
function node_activities(id)
    uuid = validate_uuid(:id, id)
    return json_to_julia(api_get("node/$(uuid)/activities"))
end

"""
    institute(scientificname = nothing; kwargs...) -> OBISTable

Find institutes contributing to a selection.

Identifiers are OceanExpert IDs, which is what the `instituteid` filter expects elsewhere.
"""
function institute(scientificname=nothing; kwargs...)
    params = build_params(; scientificname=scientificname, kwargs...)
    payload = api_get("institute", params)
    records = results_of(payload)
    meta = QueryMeta("institute", params, total_of(payload, length(records)))
    return build_table(records, INSTITUTE_SCHEMA, meta)
end

"""
    institute_by_id(id) -> OBISTable

Fetch one institute by its OceanExpert ID.
"""
function institute_by_id(id)
    path = "institute/$(id)"
    payload = api_get(path)
    records = results_of(payload)
    meta = QueryMeta(path, QueryParams(), total_of(payload, length(records)))
    return build_table(records, INSTITUTE_SCHEMA, meta)
end

"""
    area(id = nothing) -> OBISTable

List the areas OBIS can filter by, or fetch one by ID.

Areas include exclusive economic zones, marine protected areas and other named regions. An
area ID is what the `areaid` filter expects.

```julia
julia> areas = OBIS.area();

julia> belgian = [r for r in areas.name if occursin("Belg", r)]
```
"""
function area(id=nothing)
    path = id === nothing ? "area" : "area/$(id)"
    payload = api_get(path)
    records = results_of(payload)
    meta = QueryMeta(path, QueryParams(), total_of(payload, length(records)))
    return build_table(records, AREA_SCHEMA, meta)
end

"""
    country(id = nothing) -> OBISTable

List the countries OBIS can filter by, or fetch one by ID.
"""
function country(id=nothing)
    path = id === nothing ? "country" : "country/$(id)"
    payload = api_get(path)
    records = results_of(payload)
    meta = QueryMeta(path, QueryParams(), total_of(payload, length(records)))
    return build_table(records, COUNTRY_SCHEMA, meta)
end

"""
    metrics(; datasetid = nothing, nodeid = nothing) -> Any

Yearly download counts for a dataset or a node.

Provide one or the other. When both are given the API uses `datasetid`.
"""
function metrics(; datasetid=nothing, nodeid=nothing)
    if datasetid === nothing && nodeid === nothing
        throw(
            OBISValidationError(
                :datasetid, nothing, "Provide either `datasetid` or `nodeid`."
            ),
        )
    end
    q = QueryParams()
    datasetid === nothing || (q["datasetid"] = validate_uuid(:datasetid, datasetid))
    nodeid === nothing || (q["nodeid"] = validate_uuid(:nodeid, nodeid))
    return json_to_julia(api_get("metrics", q))
end

"""
    metrics_downloads(datasetid; startdate = nothing, enddate = nothing, groupby = nothing)

Download counts for a dataset, optionally within a date range.

Pass `groupby = "time"` for one entry per download event instead of an aggregate.
"""
function metrics_downloads(datasetid; startdate=nothing, enddate=nothing, groupby=nothing)
    q = QueryParams()
    q["datasetid"] = validate_uuid(:datasetid, datasetid)
    startdate === nothing || (q["startdate"] = format_date(:startdate, startdate))
    enddate === nothing || (q["enddate"] = format_date(:enddate, enddate))
    if groupby !== nothing
        String(string(groupby)) == "time" || throw(
            OBISValidationError(
                :groupby, groupby, "The only value the API accepts is \"time\"."
            ),
        )
        q["groupby"] = "time"
    end
    return json_to_julia(api_get("metrics/downloads", q))
end
