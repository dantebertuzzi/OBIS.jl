# Local response cache, addressed by a hash of the query.
#
# The purpose is reproducibility rather than speed. OBIS ingests new records continuously,
# so the same query run twice returns different data, and an analysis published today
# cannot be re-run against the data it was based on unless something kept a copy. Storing
# the raw response body alongside the query and the retrieval date makes that possible, and
# keeps the stored artifact independent of this package's parsing decisions.

"""
    QueryCache(dir = default_cache_dir(); readonly = false)

A local, content-addressed cache of raw API responses.

Each entry is keyed by a hash of the base URL, endpoint and query parameters, and stores
the unparsed response body next to a metadata record giving the endpoint, the parameters,
the retrieval timestamp and the response `ETag`. Storing the raw body means a re-run
reproduces the original data even if this package's schema handling has changed since.

Entries never expire. That is the point: an expiring cache cannot support "re-run this
analysis against the data as it stood in March". Remove entries explicitly with
[`clear_cache!`](@ref).

# Examples

```julia
# Cache into the default location for the rest of the session.
OceanBIS.configure!(cache = OceanBIS.QueryCache())

# Keep an analysis's data alongside the analysis.
OceanBIS.configure!(cache = OceanBIS.QueryCache("data/obis-cache"))

# Re-run later against exactly what was fetched, refusing to reach the network.
OceanBIS.configure!(cache = OceanBIS.QueryCache("data/obis-cache"; readonly = true))
```
"""
struct QueryCache
    dir::String
    readonly::Bool
end

function QueryCache(dir::AbstractString=default_cache_dir(); readonly::Bool=false)
    return QueryCache(String(dir), readonly)
end

"""
    default_cache_dir() -> String

Default cache location, honouring `XDG_CACHE_HOME` where it is set.
"""
function default_cache_dir()
    xdg = get(ENV, "XDG_CACHE_HOME", "")
    base = isempty(xdg) ? joinpath(homedir(), ".cache") : xdg
    return joinpath(base, "OceanBIS.jl")
end

"""
    cache_key(endpoint, params; base_url) -> String

Hash a query into a stable cache key.

Parameters are sorted before hashing so that keyword order does not change the key, which
is what lets the same query written two different ways hit the same entry.
"""
function cache_key(endpoint::AbstractString, params::QueryParams; base_url::AbstractString)
    io = IOBuffer()
    print(io, base_url, '\n', lstrip(String(endpoint), '/'), '\n')
    for (k, v) in sorted_pairs(params)
        print(io, k, '=', v, '\n')
    end
    return bytes2hex(SHA.sha256(take!(io)))
end

entry_path(cache::QueryCache, key::AbstractString) = joinpath(cache.dir, key * ".json")
meta_path(cache::QueryCache, key::AbstractString) = joinpath(cache.dir, key * ".meta.json")

"""
    cached_body(cache, endpoint, params) -> Union{Nothing,String}

Return a stored response body, or `nothing` when the query is not cached.
"""
cached_body(::Nothing, ::AbstractString, ::QueryParams) = nothing

function cached_body(cache::QueryCache, endpoint::AbstractString, params::QueryParams)
    key = cache_key(endpoint, params; base_url=CONFIG.base_url)
    path = entry_path(cache, key)
    isfile(path) || begin
        if cache.readonly
            throw(
                OBISAPIError(
                    0,
                    endpoint,
                    "The cache is read-only and holds no entry for this query, so the " *
                    "package will not reach the network for it. Either this query differs " *
                    "from the one that was cached, or the cache directory " *
                    "($(cache.dir)) is not the one that was written. Set " *
                    "`readonly = false` to fetch it.",
                    "",
                ),
            )
        end
        return nothing
    end
    return read(path, String)
end

"""
    store_body!(cache, endpoint, params, body, headers)

Write a response body and its provenance metadata into the cache.
"""
store_body!(::Nothing, ::AbstractString, ::QueryParams, ::AbstractString, ::Any) = nothing

function store_body!(
    cache::QueryCache,
    endpoint::AbstractString,
    params::QueryParams,
    body::AbstractString,
    headers,
)
    cache.readonly && return nothing
    mkpath(cache.dir)
    key = cache_key(endpoint, params; base_url=CONFIG.base_url)

    meta = Dict{String,Any}(
        "endpoint" => lstrip(String(endpoint), '/'),
        "base_url" => CONFIG.base_url,
        "parameters" => Dict(k => v for (k, v) in sorted_pairs(params)),
        "retrieved" => string(now(UTC)),
        "accessed" => string(today()),
        "package_version" => string(package_version()),
        "etag" => headers isa AbstractDict ? get(headers, "etag", "") : "",
    )

    # Write through a temporary file so an interrupted run cannot leave a truncated entry
    # that would later be served as if it were complete.
    tmp = entry_path(cache, key) * ".tmp"
    write(tmp, body)
    mv(tmp, entry_path(cache, key); force=true)

    tmpm = meta_path(cache, key) * ".tmp"
    open(tmpm, "w") do io
        JSON3.write(io, meta)
    end
    mv(tmpm, meta_path(cache, key); force=true)
    return nothing
end

"""
    cache_entries(cache = config().cache) -> Vector{Dict{String,Any}}

List what a cache holds: endpoint, parameters, retrieval time and size for each entry.

```julia
for e in OceanBIS.cache_entries()
    println(e["endpoint"], "  ", e["retrieved"])
end
```
"""
function cache_entries(cache=CONFIG.cache)
    cache === nothing && return Dict{String,Any}[]
    isdir(cache.dir) || return Dict{String,Any}[]
    out = Dict{String,Any}[]
    for f in sort(readdir(cache.dir))
        endswith(f, ".meta.json") || continue
        meta = try
            copy(JSON3.read(read(joinpath(cache.dir, f), String), Dict{String,Any}))
        catch
            continue
        end
        key = replace(f, ".meta.json" => "")
        body = entry_path(cache, key)
        meta["key"] = key
        meta["bytes"] = isfile(body) ? filesize(body) : 0
        push!(out, meta)
    end
    return out
end

"""
    clear_cache!(cache = config().cache) -> Int

Delete every entry in a cache and return how many were removed.
"""
function clear_cache!(cache=CONFIG.cache)
    cache === nothing && return 0
    isdir(cache.dir) || return 0
    n = 0
    for f in readdir(cache.dir)
        endswith(f, ".json") || continue
        rm(joinpath(cache.dir, f); force=true)
        endswith(f, ".meta.json") && (n += 1)
    end
    return n
end
