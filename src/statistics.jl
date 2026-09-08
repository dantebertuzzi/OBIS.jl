# Statistics and facets, and the query-size guard built on them.
#
# `/statistics` honours every occurrence filter, including ones the API specification does
# not list for it, so a single cheap request predicts exactly how many records an occurrence
# query would return. That is what makes it possible to warn about a large pull before
# starting it rather than partway through.

"""
    statistics(scientificname = nothing; kwargs...) -> Dict{String,Any}

Summary counts for a query: records, species, taxa, datasets, and the year range.

Accepts the same filters as [`occurrence`](@ref) and counts exactly the records that query
would return, so it is the cheap way to size a query before running it.

```julia
julia> st = OceanBIS.statistics("Abra alba");

julia> st["records"], st["datasets"]
(75356, 216)

julia> OceanBIS.statistics("Abra alba"; absence = :only)["records"]
18387
```
"""
function statistics(scientificname=nothing; kwargs...)
    params = build_params(; scientificname=scientificname, kwargs...)
    return json_to_julia(api_get("statistics", params))
end

"""
    statistics_years(scientificname = nothing; kwargs...) -> Vector{Dict{String,Any}}

Number of presence records per year.

Useful for showing what record counts actually measure. A rise in a series like this
tracks survey programmes, digitization projects and the growth of OBIS itself; it is not
evidence that a taxon became more abundant.

```julia
julia> years = OceanBIS.statistics_years("Abra alba");

julia> first(years)
Dict{String, Any}("year" => 1841, "records" => 8)
```
"""
function statistics_years(scientificname=nothing; kwargs...)
    params = build_params(; scientificname=scientificname, kwargs...)
    return json_to_julia(api_get("statistics/years", params))
end

"""
    statistics_env(scientificname = nothing; kwargs...) -> Any

Record counts per sea surface temperature, salinity, or depth bin.
"""
function statistics_env(scientificname=nothing; kwargs...)
    params = build_params(; scientificname=scientificname, kwargs...)
    return json_to_julia(api_get("statistics/env", params))
end

"""
    statistics_qc(scientificname = nothing; kwargs...) -> Dict{String,Any}

Quality summary for a query: missing and invalid fields, records on land, non-marine
records, and records without an AphiaID.

Worth running before an analysis. It reports what a default query silently excludes and
what the records it does return are flagged for.
"""
function statistics_qc(scientificname=nothing; kwargs...)
    params = build_params(; scientificname=scientificname, kwargs...)
    return json_to_julia(api_get("statistics/qc", params))
end

"""
    statistics_composition(scientificname = nothing; kwargs...) -> Any

Taxonomic composition of a selection.
"""
function statistics_composition(scientificname=nothing; kwargs...)
    params = build_params(; scientificname=scientificname, kwargs...)
    return json_to_julia(api_get("statistics/composition", params))
end

"""
    facet(facets; kwargs...) -> Dict{String,Vector}

Record counts grouped by one or more fields.

`facets` names the fields, for example `"flags"`, `"datasetName"` or
`["originalScientificName", "flags"]`.

The API truncates each facet's value list, so a facet result is a ranking of the most
common values, not a complete enumeration. In particular the `flags` facet does not list
every flag OBIS uses; `OceanBIS.KNOWN_FLAGS` is the fuller reference.

```julia
julia> f = OceanBIS.facet("flags"; scientificname = "Abra alba");

julia> first(f["flags"])
Dict{String, Any}("key" => "NO_DEPTH", "records" => 29772)
```
"""
function facet(facets; kwargs...)
    params = build_params(; facets=facets, kwargs...)
    payload = api_get("facet", params)
    out = Dict{String,Vector}()
    if payload isa JSON3.Object && haskey(payload, :results)
        for (k, v) in pairs(payload[:results])
            out[String(k)] = json_to_julia(v)
        end
    end
    return out
end

"""
    estimate_size(; kwargs...) -> Int

Number of records a query would return, from one `/statistics` request.

```julia
julia> OceanBIS.estimate_size(scientificname = "Mollusca") > 1_000_000
true
```
"""
function estimate_size(; kwargs...)
    params = build_params(; kwargs...)
    return estimate_size(params)
end

function estimate_size(params::QueryParams)
    payload = api_get("statistics", stats_filters(params))
    payload isa JSON3.Object || return 0
    n = get(payload, :records, nothing)
    return n === nothing ? 0 : Int(n)
end

"""
    stats_filters(params) -> QueryParams

Drop pagination and projection parameters, which change what a page contains but not how
many records match.
"""
function stats_filters(params::QueryParams)
    out = QueryParams()
    for (k, v) in pairs(params)
        k in ("size", "after", "fields") && continue
        push!(out.pairs, k => v)
    end
    return out
end

"""
    guard_query_size(params)

Refuse to page through a query larger than `config().api_record_limit`.

The refusal is deliberate. OBIS asks that large volumes be taken from the bulk export
rather than the API, and the two routes do not cover the same records — absence and dropped
records are reachable only through the API. Switching routes silently would therefore
change the answer, so the choice is left to the caller, with the alternatives spelled out.
"""
function guard_query_size(params::QueryParams)
    limit = CONFIG.api_record_limit
    limit <= 0 && return nothing

    estimate = try
        estimate_size(params)
    catch err
        err isa OBISError || rethrow()
        # A failed estimate must not block a legitimate query; the pull proceeds and the
        # progress indicator will show how large it turns out to be.
        @debug "Could not estimate query size" err
        return nothing
    end

    estimate <= limit && return nothing

    wants_api_only = !export_covers(params)

    io = IOBuffer()
    println(io, "  Options, in the order most likely to help:")
    println(io)
    println(io, "  1. Narrow the query — add `geometry`, `startdate`/`enddate`, or a")
    println(
        io, "     `datasetid`. `OceanBIS.statistics(...)` prices a query before you run it."
    )
    println(io, "  2. Take only part of it, with `limit = n`. Records arrive ordered by")
    println(io, "     UUID, so this is an arbitrary subset, not the earliest records.")
    println(io, "  3. Stream it with `OceanBIS.occurrence_pages(...)`, which processes one")
    println(io, "     page at a time and can resume after an interruption.")
    if wants_api_only
        println(io)
        println(io, "  The bulk export is not an option for this query: it selects pure")
        println(io, "  event records, and the export has no column that identifies them.")
    else
        println(io)
        println(io, "  4. Use the bulk export, which OBIS recommends at this volume:")
        println(
            io, "     `OceanBIS.download_exports(...)` fetches the GeoParquet files for the"
        )
        println(io, "     datasets a query touches. Note that the export is a periodic")
        println(io, "     snapshot, so it lags whatever the API has ingested since.")
    end
    println(io)
    print(io, "  To proceed on the API anyway: `OceanBIS.configure!(api_record_limit = ")
    print(io, estimate + 1)
    print(io, ")`, or pass `check_size = false`.")

    throw(OBISLargeQueryError(estimate, limit, String(take!(io))))
end
