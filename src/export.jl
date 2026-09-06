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
julia> OBIS.export_url("8acba7e7-2e50-4490-8328-b78a30472508")
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

Whether the bulk export can serve a query.

`false` when the query selects absence, dropped or pure event records. Those are available
through the API, and the OBIS documentation is not consistent about whether the export
includes absence records, so the package treats the export as not covering them rather than
returning a result that might silently be missing a class of records.
"""
function export_covers(; absence=nothing, dropped=nothing, event=nothing, kwargs...)
    for (name, sel) in ((:absence, absence), (:dropped, dropped), (:event, event))
        selection_value(name, sel) === nothing || return false
    end
    return true
end

"""
    download_export(dataset_id; dir = pwd(), overwrite = false) -> String

Download one dataset's GeoParquet export and return the local path.

```julia
path = OBIS.download_export("8acba7e7-2e50-4490-8328-b78a30472508"; dir = "data")
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

The export excludes records the quality pipeline dropped, and its coverage of absence
records is not documented consistently, so a query that needs either should stay on the
API. [`export_covers`](@ref) reports which case a query is in.

```julia
paths = OBIS.download_exports("Abra alba"; dir = "obis-export")
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
                "`OBIS.occurrence(...)` or `OBIS.occurrence_pages(...)`.",
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
    try
        HTTP.download(url, tmp; headers=request_headers(CONFIG), update_period=Inf)
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
