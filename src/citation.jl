# Citation and licence reporting.
#
# The OBIS data policy asks that any use of the data be cited, naming software applications
# explicitly, and the required format includes `Accessed: YYYY-MM-DD`. That date is a
# property of the request, not of the data, so nothing but the client can supply it — which
# is why a result carries it and these functions read it from there rather than asking.
#
# Licences vary per dataset and include CC BY-NC, so whether a result may be redistributed
# depends on which datasets it drew on. `licenses` answers that from the result itself.

"""
    citations(t::OBISTable; format = :table)

Build the citations required for the data in a result.

Returns one entry per dataset the records came from, with the provider's citation string,
its DOI where one exists, its licence, how many records in the result it contributed, and a
ready-to-use citation in the format the OBIS data policy specifies — including the access
date recorded when the data was retrieved.

Formats:

  - `:table` — an [`OBISTable`](@ref), for further processing or writing to a file.
  - `:text` — the formatted citations as one string, ready to paste.
  - `:bibtex` — a BibTeX document, one `@misc` entry per dataset.

The dataset citation is not the only obligation. Where a result draws on many datasets, the
policy also allows citing the OBIS database as a whole; [`obis_citation`](@ref) builds that.

# Examples

```julia
recs = OBIS.occurrence("Abra alba"; limit = 1000)

cites = OBIS.citations(recs)          # a table, one row per dataset
print(OBIS.citations(recs; format = :text))
write("references.bib", OBIS.citations(recs; format = :bibtex))
```
"""
function citations(t::OBISTable; format::Symbol=:table)
    entries = citation_entries(t)
    format === :table && return citation_table(entries, metadata(t))
    format === :text && return citation_text(entries)
    format === :bibtex && return citation_bibtex(entries)
    throw(
        OBISValidationError(
            :format, format, "Use `:table`, `:text` or `:bibtex`."
        ),
    )
end

"""
    CitationEntry

One dataset's contribution to a result, with everything a citation needs.
"""
struct CitationEntry
    dataset_id::String
    title::Union{Missing,String}
    citation::Union{Missing,String}
    doi::Union{Missing,String}
    license::String
    license_url::Union{Missing,String}
    published::Union{Missing,DateTime}
    records::Int
    accessed::Date
end

"""
    citation_entries(t) -> Vector{CitationEntry}

Gather per-dataset citation metadata for the datasets present in a result.

Dataset metadata is fetched with the result's own query, so this costs one request
regardless of how many datasets are involved.
"""
function citation_entries(t::OBISTable)
    meta = metadata(t)
    counts = dataset_counts(t)
    isempty(counts) && return CitationEntry[]

    records = fetch_dataset_records(meta, collect(keys(counts)))

    entries = CitationEntry[]
    for (id, n) in counts
        rec = get(records, id, nothing)
        if rec === nothing
            push!(
                entries,
                CitationEntry(
                    id, missing, missing, missing, "unknown", missing, missing, n,
                    meta.accessed
                ),
            )
            continue
        end
        rights = get(rec, :intellectualrights, nothing)
        lic = normalize_license(rights)
        push!(
            entries,
            CitationEntry(
                id,
                str_or_missing(get(rec, :title, nothing)),
                str_or_missing(get(rec, :citation, nothing)),
                doi_of(get(rec, :citation_id, nothing)),
                lic,
                license_url(lic),
                coerce_iso_datetime(get(rec, :published, nothing)),
                n,
                meta.accessed,
            ),
        )
    end

    sort!(entries; by=e -> (-e.records, e.dataset_id))
    return entries
end

"""
    dataset_counts(t) -> Dict{String,Int}

How many records in a result came from each dataset.
"""
function dataset_counts(t::OBISTable)
    counts = Dict{String,Int}()
    key = haskey(t, :dataset_id) ? :dataset_id : (haskey(t, :id) ? :id : nothing)
    key === nothing && return counts
    for v in Tables.getcolumn(t, key)
        ismissing(v) && continue
        counts[String(v)] = get(counts, String(v), 0) + 1
    end
    return counts
end

"""
    fetch_dataset_records(meta, ids) -> Dict{String,Any}

Retrieve dataset metadata covering `ids`, reusing the result's query where possible.
"""
function fetch_dataset_records(meta::QueryMeta, ids::Vector{String})
    out = Dict{String,Any}()
    isempty(ids) && return out

    params = QueryParams([k => v for (k, v) in meta.params])
    filters = dataset_filters(params)

    if !isempty(filters)
        try
            for rec in results_of(api_get("dataset", filters))
                rec isa JSON3.Object || continue
                id = get(rec, :id, nothing)
                id === nothing || (out[String(id)] = rec)
            end
        catch err
            err isa OBISError || rethrow()
            @debug "Bulk dataset lookup failed; falling back to individual requests" err
        end
    end

    missing_ids = [id for id in ids if !haskey(out, id)]
    if length(missing_ids) > 50
        @warn """
        Citation metadata is unavailable for $(length(missing_ids)) datasets without one \
        request each, so those entries will be incomplete. Narrow the query, or call \
        `OBIS.dataset(...)` with the same filters to retrieve the metadata yourself.""" maxlog =
            1
        missing_ids = String[]
    end
    for id in missing_ids
        try
            for rec in results_of(api_get("dataset/$(id)"))
                rec isa JSON3.Object && (out[id] = rec)
            end
        catch err
            err isa OBISError || rethrow()
        end
    end

    return out
end

str_or_missing(x) = x === nothing ? missing : String(string(x))

function doi_of(x)
    x === nothing && return missing
    s = String(string(x))
    isempty(strip(s)) && return missing
    return replace(s, r"^https?://(dx\.)?doi\.org/" => "")
end

"""
    format_citation(e::CitationEntry) -> String

Render one dataset citation in the format the OBIS data policy specifies.

Follows the policy template: the provider's citation, then the OBIS availability statement
and the access date. Where the provider supplied no citation, one is assembled from the
title and publication year so that the dataset is still identifiable — a missing citation
string is not a reason to leave data uncredited.
"""
function format_citation(e::CitationEntry)
    base = if !ismissing(e.citation) && !isempty(strip(e.citation))
        strip(e.citation)
    elseif !ismissing(e.title)
        year = ismissing(e.published) ? "n.d." : string(Dates.year(e.published))
        string(e.title, " (", year, ")")
    else
        string("OBIS dataset ", e.dataset_id)
    end

    io = IOBuffer()
    print(io, base)
    endswith(rstrip(String(base)), '.') || print(io, '.')
    print(io, " [Dataset] (Available: Ocean Biodiversity Information System. ")
    print(io, "Intergovernmental Oceanographic Commission of UNESCO. https://obis.org. ")
    print(io, "Accessed: ", e.accessed, ")")
    ismissing(e.doi) || print(io, " https://doi.org/", e.doi)
    return String(take!(io))
end

function citation_text(entries::Vector{CitationEntry})
    isempty(entries) && return ""
    return join((format_citation(e) for e in entries), "\n\n") * "\n"
end

"""
    obis_citation(; description = nothing, accessed = today(), year = Dates.year(today()))

The citation for the OBIS database as a whole.

The data policy allows citing the integrated database in addition to — never instead of —
the individual datasets, whose own restrictions continue to apply.

```jldoctest
julia> OBIS.obis_citation(; description = "Distribution records of Abra alba", accessed = Date(2026, 9, 6), year = 2026)
"OBIS (2026) Distribution records of Abra alba [Dataset] (Available: Ocean Biodiversity Information System. Intergovernmental Oceanographic Commission of UNESCO. https://obis.org. Accessed: 2026-09-06)"
```
"""
function obis_citation(;
    description=nothing, accessed::Date=today(), year::Integer=Dates.year(today())
)
    io = IOBuffer()
    print(io, "OBIS (", year, ") ")
    description === nothing || print(io, description, " ")
    print(io, "[Dataset] (Available: Ocean Biodiversity Information System. ")
    print(io, "Intergovernmental Oceanographic Commission of UNESCO. https://obis.org. ")
    print(io, "Accessed: ", accessed, ")")
    return String(take!(io))
end

# --- BibTeX ----------------------------------------------------------------------------

function citation_bibtex(entries::Vector{CitationEntry})
    io = IOBuffer()
    for e in entries
        print(io, bibtex_entry(e), "\n")
    end
    return String(take!(io))
end

function bibtex_entry(e::CitationEntry)
    key = string("obis_", first(replace(e.dataset_id, "-" => ""), 12))
    title = ismissing(e.title) ? string("OBIS dataset ", e.dataset_id) : e.title
    year = ismissing(e.published) ? "" : string(Dates.year(e.published))

    io = IOBuffer()
    println(io, "@misc{", key, ",")
    println(io, "  title        = {", bibtex_escape(title), "},")
    isempty(year) || println(io, "  year         = {", year, "},")
    println(io, "  howpublished = {Ocean Biodiversity Information System (OBIS), ",
        "Intergovernmental Oceanographic Commission of UNESCO},")
    ismissing(e.doi) || println(io, "  doi          = {", bibtex_escape(e.doi), "},")
    println(io, "  url          = {https://obis.org/dataset/", e.dataset_id, "},")
    print(io, "  note         = {Accessed: ", e.accessed, ". License: ", e.license)
    ismissing(e.license_url) || print(io, " (", e.license_url, ")")
    println(io, ". Records used: ", e.records, ".},")
    println(io, "}")
    return String(take!(io))
end

"""
    bibtex_escape(s) -> String

Escape the characters BibTeX treats specially, so a provider's citation text cannot break
the generated file.
"""
function bibtex_escape(s::AbstractString)
    out = IOBuffer()
    for c in s
        if c in ('{', '}', '\\')
            print(out, '\\', c)
        elseif c in ('&', '%', '$', '#', '_')
            print(out, '\\', c)
        elseif c == '~'
            print(out, "\\textasciitilde{}")
        elseif c == '^'
            print(out, "\\textasciicircum{}")
        else
            print(out, c)
        end
    end
    return String(take!(out))
end

# --- Tables ----------------------------------------------------------------------------

function citation_table(entries::Vector{CitationEntry}, meta::QueryMeta)
    n = length(entries)
    names = [
        :dataset_id,
        :title,
        :records,
        :license,
        :license_url,
        :doi,
        :citation,
        :formatted,
        :accessed,
    ]
    columns = AbstractVector[
        String[e.dataset_id for e in entries],
        Union{Missing,String}[e.title for e in entries],
        Int[e.records for e in entries],
        String[e.license for e in entries],
        Union{Missing,String}[e.license_url for e in entries],
        Union{Missing,String}[e.doi for e in entries],
        Union{Missing,String}[e.citation for e in entries],
        String[format_citation(e) for e in entries],
        Date[e.accessed for e in entries],
    ]
    cmeta = QueryMeta(
        "citations",
        meta.params,
        meta.accessed,
        meta.retrieved,
        n,
        meta.base_url,
        meta.package_version,
    )
    return OBISTable(names, columns, cmeta)
end

"""
    licenses(t::OBISTable) -> OBISTable

Summarize which licences a result is under.

One row per distinct licence, with how many datasets and records fall under it and what it
permits. Read it before redistributing: a single CC BY-NC dataset makes the combined result
non-commercial, and `"unknown"` covers rights statements that could not be identified —
among them the literal value `Restricted` — which are not permission to redistribute.

```julia
julia> OBIS.licenses(OBIS.occurrence("Abra alba"; limit = 500))
OBISTable: 3 records, 7 columns
```
"""
function licenses(t::OBISTable)
    meta = metadata(t)
    by_license = Dict{String,Tuple{Set{String},Int}}()

    lic_col = haskey(t, :license) ? Tables.getcolumn(t, :license) : nothing
    if lic_col === nothing
        throw(
            OBISValidationError(
                :t,
                nothing,
                "This table has no `license` column. Licences are attached to occurrence " *
                "and dataset results; for other endpoints, query `OBIS.dataset(...)` with " *
                "the same filters.",
            ),
        )
    end

    ids = if haskey(t, :dataset_id)
        Tables.getcolumn(t, :dataset_id)
    else
        (haskey(t, :id) ? Tables.getcolumn(t, :id) : nothing)
    end

    for i in eachindex(lic_col)
        id = ismissing(lic_col[i]) ? "unknown" : String(lic_col[i])
        ds = ids === nothing || ismissing(ids[i]) ? "" : String(ids[i])
        set, n = get(by_license, id, (Set{String}(), 0))
        isempty(ds) || push!(set, ds)
        by_license[id] = (set, n + 1)
    end

    keys_sorted = sort!(collect(keys(by_license)); by=k -> (-by_license[k][2], k))
    names = [
        :license,
        :datasets,
        :records,
        :permits_redistribution,
        :permits_commercial_use,
        :requires_attribution,
        :url,
    ]
    columns = AbstractVector[
        String[k for k in keys_sorted],
        Int[length(by_license[k][1]) for k in keys_sorted],
        Int[by_license[k][2] for k in keys_sorted],
        Bool[permits_redistribution(k) for k in keys_sorted],
        Bool[permits_commercial_use(k) for k in keys_sorted],
        Bool[requires_attribution(k) for k in keys_sorted],
        Union{Missing,String}[license_url(k) for k in keys_sorted],
    ]
    lmeta = QueryMeta(
        "licenses",
        meta.params,
        meta.accessed,
        meta.retrieved,
        length(keys_sorted),
        meta.base_url,
        meta.package_version,
    )
    return OBISTable(names, columns, lmeta)
end
