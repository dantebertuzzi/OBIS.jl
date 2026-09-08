# The dataset endpoint, and the licence lookup that occurrence results depend on.
#
# An occurrence record carries `dataset_id` and nothing else about rights, so licence and
# citation have to come from the dataset side. The join is cheap because `/dataset` accepts
# the same filters as `/occurrence`: the rights information for a whole query costs one
# additional request, not one request per dataset.

"""
    dataset(scientificname = nothing; kwargs...) -> OBISTable

Find datasets matching a query.

Accepts the same filters as [`occurrence`](@ref), so `dataset` describes exactly the
datasets an occurrence query draws on. Each row carries the provider's citation string, the
rights statement as published, and a normalized `license` identifier derived from it.

This endpoint does not paginate: every match is returned in one response. An unfiltered
call therefore retrieves metadata for every dataset in OBIS, currently around seven
thousand.

# Examples

```julia
# Datasets behind a species.
ds = OceanBIS.dataset("Abra alba")

# Which licences are in play, before downloading any occurrences.
OceanBIS.licenses(ds)
```
"""
function dataset(scientificname=nothing; kwargs...)
    params = build_params(; scientificname=scientificname, kwargs...)
    payload = api_get("dataset", params)
    records = results_of(payload)
    meta = QueryMeta("dataset", params, total_of(payload, length(records)))
    return finalize_dataset_table(build_table(records, DATASET_SCHEMA, meta))
end

"""
    dataset_by_id(id) -> OBISTable

Fetch one dataset by its UUID.

```julia
julia> ds = OceanBIS.dataset_by_id("8acba7e7-2e50-4490-8328-b78a30472508");
```
"""
function dataset_by_id(id)
    uuid = validate_uuid(:id, id)
    payload = api_get("dataset/$(uuid)")
    records = results_of(payload)
    meta = QueryMeta("dataset/$(uuid)", QueryParams(), length(records))
    return finalize_dataset_table(build_table(records, DATASET_SCHEMA, meta))
end

"""
    dataset_errors(id) -> Vector

Loading errors OBIS recorded for a dataset, useful when a dataset holds fewer records than
expected.
"""
function dataset_errors(id)
    uuid = validate_uuid(:id, id)
    return json_to_julia(api_get("dataset/$(uuid)/errors"))
end

"""
    finalize_dataset_table(t) -> OBISTable

Fill the derived `license` and `license_url` columns from the published rights text.
"""
function finalize_dataset_table(t::OBISTable)
    rights = Tables.getcolumn(t, :intellectualrights)
    lic = Tables.getcolumn(t, :license)
    url = Tables.getcolumn(t, :license_url)
    for i in eachindex(rights)
        id = normalize_license(rights[i])
        lic[i] = id
        url[i] = license_url(id)
    end
    return t
end

"""
    DatasetInfo

Rights and citation metadata for one dataset, as attached to occurrence records.
"""
struct DatasetInfo
    license::String
    license_url::Union{Missing,String}
    citation::Union{Missing,String}
    title::Union{Missing,String}
end

"""
    dataset_info(params; ids) -> Dict{String,DatasetInfo}

Build a `dataset_id` to rights mapping covering `ids`.

Strategy is chosen by cost. When the occurrence query carries filters, one `/dataset` call
with those same filters covers every dataset the query can touch. When it carries none —
which would otherwise pull metadata for all of OBIS — the datasets actually present in the
result are fetched individually instead.
"""
function dataset_info(params::QueryParams, ids::Vector{String})
    isempty(ids) && return Dict{String,DatasetInfo}()
    out = Dict{String,DatasetInfo}()

    filters = dataset_filters(params)
    if !isempty(filters)
        payload = api_get("dataset", filters)
        for rec in results_of(payload)
            rec isa JSON3.Object || continue
            id = get(rec, :id, nothing)
            id === nothing && continue
            out[String(id)] = info_from_record(rec)
        end
    end

    remaining = [id for id in ids if !haskey(out, id)]
    if !isempty(remaining)
        if length(remaining) > 50
            @warn """
            Rights information is missing for $(length(remaining)) datasets and would need \
            one request each, so it is being skipped. The `license` column will be \
            `missing` for those records. Narrow the query, or call `OceanBIS.dataset(...)` \
            with the same filters to retrieve the rights separately.""" maxlog = 1
            return out
        end
        for id in remaining
            try
                payload = api_get("dataset/$(id)")
                for rec in results_of(payload)
                    rec isa JSON3.Object || continue
                    out[id] = info_from_record(rec)
                end
            catch err
                err isa OBISError || rethrow()
                @debug "Could not retrieve dataset metadata" id err
            end
        end
    end

    return out
end

function info_from_record(rec)
    rights = get(rec, :intellectualrights, nothing)
    id = normalize_license(rights)
    citation = get(rec, :citation, nothing)
    title = get(rec, :title, nothing)
    return DatasetInfo(
        id,
        license_url(id),
        citation === nothing ? missing : String(citation),
        title === nothing ? missing : String(title),
    )
end

"""
    dataset_filters(params) -> QueryParams

Keep only the parameters `/dataset` filters on.

Pagination and occurrence-only parameters are dropped. The result may match more datasets
than the occurrence query strictly touches, which is harmless for a lookup table.
"""
function dataset_filters(params::QueryParams)
    keep = (
        "scientificname",
        "taxonid",
        "datasetid",
        "areaid",
        "instituteid",
        "nodeid",
        "startdate",
        "enddate",
        "startdepth",
        "enddepth",
        "geometry",
        "redlist",
        "hab",
        "wrims",
        "flags",
        "exclude",
        "tags",
        "absence",
        "dropped",
    )
    out = QueryParams()
    for (k, v) in pairs(params)
        k in keep && push!(out.pairs, k => v)
    end
    return out
end

"""
    attach_licenses(t, params) -> OBISTable

Fill the `license`, `license_url` and `dataset_citation` columns of an occurrence table.

Called automatically by [`occurrence`](@ref); pass `licenses = false` there to skip it. The
columns exist either way, so the table's shape does not depend on the choice.
"""
function attach_licenses(t::OBISTable, params::QueryParams)
    haskey(t, :dataset_id) || return t
    dsids = Tables.getcolumn(t, :dataset_id)
    ids = unique(String[x for x in dsids if !ismissing(x)])
    isempty(ids) && return t

    info = try
        dataset_info(params, ids)
    catch err
        err isa OBISError || rethrow()
        @warn """
        Could not retrieve dataset rights information; `license` will be `missing`.
        The records themselves are unaffected. Reason: $(sprint(showerror, err))""" maxlog =
            1
        return t
    end

    lic = Tables.getcolumn(t, :license)
    url = Tables.getcolumn(t, :license_url)
    cit = Tables.getcolumn(t, :dataset_citation)
    for i in eachindex(dsids)
        d = dsids[i]
        ismissing(d) && continue
        haskey(info, d) || continue
        rec = info[d]
        lic[i] = rec.license
        url[i] = rec.license_url
        cit[i] = rec.citation
    end
    return t
end
