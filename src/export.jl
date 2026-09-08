# The bulk export route.
#
# OBIS publishes the full occurrence dataset as GeoParquet, one file per source dataset,
# and recommends it over the API for large volumes. The files are served over plain HTTPS
# with no credentials, and are named by dataset UUID, so a query's worth of export data can
# be fetched by resolving the query to dataset IDs and downloading those files.
#
# The package downloads the files and reports where they are. It does not parse Parquet:
# doing so would mean a heavy dependency for a format the caller may already have a
# preferred reader for, and the files are more useful on disk than in memory at this size.

"""
    export_url(dataset_id) -> String

URL of the GeoParquet export for one dataset.

```jldoctest
julia> OBISClient.export_url("8acba7e7-2e50-4490-8328-b78a30472508")
"https://obis-open-data.s3.amazonaws.com/occurrence/8acba7e7-2e50-4490-8328-b78a30472508.parquet"
```
"""
function export_url(dataset_id)
    uuid = validate_uuid(:dataset_id, dataset_id)
    return string(CONFIG.export_url, "occurrence/", uuid, ".parquet")
end

"""
    export_archive_url(dataset_id) -> String

URL of the source Darwin Core Archive for one dataset.

The archive holds the data exactly as the provider published it, without the fields OBIS's
quality pipeline adds.
"""
function export_archive_url(dataset_id)
    uuid = validate_uuid(:dataset_id, dataset_id)
    return string(CONFIG.export_url, "dwca/", uuid, ".zip")
end

"""
    export_covers(; absence = nothing, dropped = nothing, event = nothing, kwargs...) -> Bool
    export_covers(params::QueryParams) -> Bool

Whether the bulk export can serve a query.

`false` only for a query that selects pure event records. The export has no column that
identifies them — its event information is a `_event_id` carried on each occurrence, not a
record class — so there is nothing in a file to select on.

Absence and dropped records **are** in the export, contrary to the OBIS data access page,
which says exports carry neither. Verified per dataset against `/statistics`: across five
datasets the export's `absence` and `dropped` row counts matched the API's `absence = :only`
and `dropped = :only` counts exactly, and each export's total equalled the default count
plus them (NOTES.md §7.3). Reading them out of an export is a filter on those two columns.

What still differs between the routes is the date. The export is regenerated periodically
and the API is live, so the same query answered from each will differ by whatever OBIS has
ingested since — which is why a large query raises rather than switching route on its own.
"""
function export_covers(; absence=nothing, dropped=nothing, event=nothing, kwargs...)
    # `absence` and `dropped` no longer decide the answer, but are still validated: a typo
    # in a selection should be an error wherever it is written rather than silently ignored
    # here and caught by the next call that happens to look at it.
    selection_value(:absence, absence)
    selection_value(:dropped, dropped)
    return selection_value(:event, event) === nothing
end

# Taken by the route heuristic, which holds a built parameter set rather than keywords.
# Sharing the rule keeps the guard's advice and this function from drifting apart.
export_covers(params::QueryParams) = !haskey(params, "event")

"""
    download_export(dataset_id; dir = pwd(), overwrite = false) -> String

Download one dataset's GeoParquet export and return the local path.

```julia
path = OBISClient.download_export("8acba7e7-2e50-4490-8328-b78a30472508"; dir = "data")
```

Read it with whichever Parquet reader you prefer; the package does not impose one. The
schema is nested — provider terms under `source`, pipeline-interpreted terms under
`interpreted` — and so differs from the flat schema the API returns.
"""
function download_export(dataset_id; dir::AbstractString=pwd(), overwrite::Bool=false)
    uuid = validate_uuid(:dataset_id, dataset_id)
    mkpath(dir)
    path = joinpath(dir, uuid * ".parquet")
    if isfile(path) && !overwrite
        @info "Export already present; not re-downloading." path
        return path
    end
    return download_file(export_url(uuid), path)
end

"""
    download_exports(scientificname = nothing; dir = pwd(), overwrite = false, kwargs...)

Download the GeoParquet exports for every dataset a query touches.

Resolves the query to its datasets with [`dataset`](@ref), then fetches one file per
dataset, serially. Returns the local paths.

One file per dataset, whole: the export is not filtered, so a query's filters are applied
by you after reading. Absence and dropped records are present and carry their own columns;
pure event records cannot be selected at all. [`export_covers`](@ref) reports which case a
query is in.

```julia
paths = OBISClient.download_exports("Abra alba"; dir = "obis-export")
```
"""
function download_exports(
    scientificname=nothing; dir::AbstractString=pwd(), overwrite::Bool=false, kwargs...
)
    if !export_covers(; kwargs...)
        throw(
            OBISValidationError(
                :absence,
                nothing,
                "This query selects absence, dropped or event records, which the bulk " *
                "export does not cover. Retrieve it through the API instead, with " *
                "`OBISClient.occurrence(...)` or `OBISClient.occurrence_pages(...)`.",
            ),
        )
    end

    ds = dataset(scientificname; kwargs...)
    ids = String[x for x in ds.id if !ismissing(x)]
    isempty(ids) && return String[]

    @info "Downloading $(length(ids)) dataset export(s) from the OBIS Open Data bucket." dir
    paths = String[]
    for (i, id) in enumerate(ids)
        @debug "Downloading export" i length(ids) id
        try
            push!(paths, download_export(id; dir=dir, overwrite=overwrite))
        catch err
            err isa OBISError || rethrow()
            @warn "Could not download the export for one dataset; continuing." id err
        end
    end
    return paths
end

"""
    EXPORT_COLUMN_SOURCES

Where each occurrence column comes from in a GeoParquet export, for the columns that are not
simply `interpreted.<name>`.

The export nests the provider's own terms under `source` and the quality pipeline's output
under `interpreted`. `interpreted` is what the API serves, so it is the default source for
every canonical column. The exceptions are the four that sit at the top level of the file,
the two whose name differs there, the three filled from the licence table, and the two the
export does not carry at all. A `nothing` means the column cannot be read from the file.

`interpreted.license` exists in the schema but was empty in every export examined, so the
licence is taken from [`export_licenses`](@ref) rather than from the row.
"""
const EXPORT_COLUMN_SOURCES = Dict{Symbol,Union{Nothing,String}}(
    :id => "_id",
    :dataset_id => "dataset_id",
    :node_id => "node_ids",
    :flags => "flags",
    :dropped => "dropped",
    :absence => "absence",
    # The pipeline's AphiaID is lower case in the export and camel case in the API.
    :aphiaID => "interpreted.aphiaid",
    # What the provider published, before the taxonomy match: `source.scientificName` is
    # "Haliotis tuberculata lamellosa" where `interpreted.scientificName` is the matched
    # "Haliotis tuberculata". That is exactly the API's `originalScientificName`.
    :originalScientificName => "source.\"scientificName\"",
    # Joined from the licence table after the read; an occurrence row carries no rights.
    :license => nothing,
    :license_url => nothing,
    :dataset_citation => nothing,
    # The export carries `marine` and `brackish` but not the other two habitat flags.
    :freshwater => nothing,
    :terrestrial => nothing,
)

"""
    export_select(spec) -> String

One entry of the `SELECT` list that reads a canonical column out of an export file.

Built from [`OCCURRENCE_SCHEMA`](@ref) rather than written out, so a column added to the
schema is read from the export without a second list to remember to update.
"""
function export_select(spec::FieldSpec)
    name = String(spec.name)
    if haskey(EXPORT_COLUMN_SOURCES, spec.name)
        src = EXPORT_COLUMN_SOURCES[spec.name]
        src === nothing && return string("NULL AS \"", name, '"')
        return string(src, " AS \"", name, '"')
    end
    return string("interpreted.\"", name, "\" AS \"", name, '"')
end

"""
    read_export(path; absence = :exclude, dropped = :exclude, licenses = true,
                limit = nothing, source_terms = false) -> OBISTable

Read one or more GeoParquet export files into the package's canonical occurrence schema.

`path` is a file, or a vector of them — so `read_export(download_exports(...))` composes.

Requires DuckDB: `using DuckDB` loads the extension that implements this. Parquet2.jl cannot
read these files, whose nested `source` and `interpreted` structs it does not support.

The result is an `OBISTable` with the same columns, in the same order and with the same
types, as one from [`occurrence`](@ref), so the two access routes become interchangeable in
everything downstream — [`licenses`](@ref) and [`citations`](@ref) included. Two columns are
always `missing`: the export carries `marine` and `brackish` but not `freshwater` or
`terrestrial`.

`absence` and `dropped` default to `:exclude`, matching the API, because the export contains
those records (NOTES.md §7.3) and a plain read would otherwise mix them into an ordinary
count without saying so. `:include` and `:only` mean what they mean everywhere else, and the
filter is pushed into the read rather than applied afterwards.

`licenses = true` fetches [`export_licenses`](@ref) once. Pass a table returned by it to
reuse across many files, or `false` to leave the three rights columns `missing`.

`source_terms = true` fills the `extra` column with the provider's own terms from `source`.
It is off by default: that block has 188 fields, and reading them costs far more than the
core schema does.

The access date on the result is the file's modification time, not today — the data is as
old as the export, and a citation built from it should say so.
"""
function read_export(
    path::Union{AbstractString,AbstractVector{<:AbstractString}}; kwargs...
)
    ext = Base.get_extension(@__MODULE__, :OBISClientDuckDBExt)
    ext === nothing && throw(
        ArgumentError(
            "OBISClient.read_export needs DuckDB. Run `using DuckDB` (add it with " *
            "`import Pkg; Pkg.add(\"DuckDB\")`) and call this again; the reader lives in " *
            "a package extension so that OBISClient.jl itself does not depend on it.",
        ),
    )
    return ext.read_export_impl(path; kwargs...)
end

"""
    export_licenses(; path = nothing) -> OBISTable

Fetch the licence table published alongside the bulk export.

One row per dataset, with the rights statement, its canonical URL and the provider's
citation. This is a companion to the export files rather than a live view of the API: it is
regenerated with the export, so it lags the current dataset list. For a live query, take
licences from [`dataset`](@ref) or from an occurrence result.

Pass `path` to read a previously downloaded copy instead of fetching it.
"""
function export_licenses(; path::Union{Nothing,AbstractString}=nothing)
    text = if path === nothing
        url = string(CONFIG.export_url, "licenses.tsv")
        body, _ = raw_request_absolute(url)
        body
    else
        read(path, String)
    end
    return parse_licenses_tsv(text)
end

"""
    parse_licenses_tsv(text) -> OBISTable

Parse the export licence table.

The format is tab-separated with a header, which is why this does not need a CSV
dependency. Citation strings are sometimes quoted, so a record is treated as complete only
once it has the expected number of fields *and* an even number of quote characters; a
citation containing a line break is therefore reassembled rather than truncated.
"""
function parse_licenses_tsv(text::AbstractString)
    lines = split(text, '\n')
    isempty(lines) && error("the licence table is empty")

    header = split(strip(lines[1], '\r'), '\t')
    ncols = length(header)

    ids = String[]
    lic_text = Union{Missing,String}[]
    lic_id = String[]
    lic_url = Union{Missing,String}[]
    citations_col = Union{Missing,String}[]

    buffer = ""
    for raw in Iterators.drop(lines, 1)
        line = strip(raw, '\r')
        isempty(line) && isempty(buffer) && continue
        buffer = isempty(buffer) ? String(line) : string(buffer, "\n", line)
        fields = split(buffer, '\t')
        # An odd number of quotes means a quoted field is still open, so the record
        # continues on the next line.
        (length(fields) < ncols || isodd(count(==('"'), buffer))) && continue

        id = strip(fields[1])
        rights = ncols >= 2 ? strip(fields[2]) : ""
        url = ncols >= 3 ? strip(fields[3]) : ""
        cite = ncols >= 4 ? strip(join(fields[4:end], '\t')) : ""
        buffer = ""

        isempty(id) && continue
        # The URL is unambiguous where it is present; the prose is the fallback.
        norm = normalize_license(isempty(url) ? rights : url)
        push!(ids, String(id))
        push!(lic_text, isempty(rights) ? missing : String(rights))
        push!(lic_id, norm)
        push!(lic_url, isempty(url) ? license_url(norm) : String(url))
        push!(citations_col, isempty(cite) ? missing : String(strip(cite, '"')))
    end

    meta = QueryMeta(
        "export/licenses.tsv",
        Pair{String,String}[],
        today(),
        now(UTC),
        length(ids),
        CONFIG.export_url,
        string(package_version()),
    )
    return OBISTable(
        [:dataset_id, :license, :license_url, :intellectualrights, :citation],
        AbstractVector[ids, lic_id, lic_url, lic_text, citations_col],
        meta,
    )
end

"""
    raw_request_absolute(url) -> (body, headers)

Fetch an absolute URL with the package's retry, backoff and identification rules.

Used for the export bucket, which is not under the API base URL.
"""
function raw_request_absolute(url::AbstractString; cfg::ClientConfig=CONFIG)
    transport = TRANSPORT[] === nothing ? default_transport : TRANSPORT[]
    headers = request_headers(cfg)
    for attempt in 1:(cfg.retries + 1)
        throttle!(cfg)
        LAST_REQUEST[] = time()
        status, resp_headers, body = try
            transport(url, headers, cfg.timeout)
        catch err
            err isa OBISError && rethrow()
            attempt <= cfg.retries &&
                (sleep(backoff_delay(attempt, cfg, nothing)); continue)
            throw(OBISConnectionError(url, sprint(showerror, err)))
        end
        status < 400 && return body, resp_headers
        if retryable(status, body) && attempt <= cfg.retries
            sleep(backoff_delay(attempt, cfg, parse_retry_after(resp_headers)))
            continue
        end
        throw(OBISAPIError(status, url, http_error_advice(status, body), body))
    end
    throw(OBISConnectionError(url, "Retry budget exhausted."))
end

"""
    download_file(url, path) -> String

Download to a temporary file and move it into place, so an interrupted transfer cannot
leave a truncated file that looks complete.
"""
function download_file(url::AbstractString, path::AbstractString)
    tmp = path * ".part"
    downloader = DOWNLOADER[] === nothing ? default_downloader : DOWNLOADER[]
    try
        downloader(url, tmp, request_headers(CONFIG))
    catch err
        isfile(tmp) && rm(tmp; force=true)
        throw(
            OBISConnectionError(
                url,
                "Download failed: " *
                sprint(showerror, err) *
                ". The bulk export is served from the OBIS Open Data bucket on AWS; a " *
                "failure here is unrelated to the API.",
            ),
        )
    end
    mv(tmp, path; force=true)
    return path
end
