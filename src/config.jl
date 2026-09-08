# Client configuration.
#
# Defaults are deliberately conservative. OBIS publishes no request quota, and its data
# access page asks users not to parallelize downloads, so the package treats politeness as
# the default rather than as an opt-in.

"The OBIS API base URL. The version is part of the path; there is no other server."
const DEFAULT_BASE_URL = "https://api.obis.org/v3/"

"Public HTTPS mirror of the OBIS Open Data bucket on AWS."
const DEFAULT_EXPORT_URL = "https://obis-open-data.s3.amazonaws.com/"

"Repository URL, sent in the `User-Agent` header so OBIS can identify the client."
const REPO_URL = "https://github.com/dantebertuzzi/OceanBIS.jl"

"Largest page the API accepts for `/occurrence`."
const MAX_PAGE_SIZE = 10_000

"""
    ClientConfig

Runtime settings for every request the package makes. Read the active configuration with
[`config`](@ref) and change it with [`configure!`](@ref).

# Fields

  - `base_url`: API base URL.
  - `export_url`: base URL of the full-export bucket.
  - `user_agent`: sent on every request, identifying package, version and repository.
  - `timeout`: per-request timeout in seconds.
  - `retries`: how many times to retry a retryable failure (429 and 5xx).
  - `backoff_base`: first backoff interval in seconds; doubles per attempt.
  - `backoff_max`: ceiling for a single backoff interval, in seconds.
  - `page_size`: records per page when paginating; capped at $(MAX_PAGE_SIZE).
  - `request_gap`: minimum seconds between consecutive requests.
  - `api_record_limit`: query size above which [`occurrence`](@ref) refuses to page and
    points at the export route instead.
  - `cache`: a [`QueryCache`](@ref), or `nothing` to disable caching.
  - `progress`: show a progress indicator while paginating.
"""
mutable struct ClientConfig
    base_url::String
    export_url::String
    user_agent::String
    timeout::Int
    retries::Int
    backoff_base::Float64
    backoff_max::Float64
    page_size::Int
    request_gap::Float64
    api_record_limit::Int
    cache::Any
    progress::Bool
end

"""
    package_version() -> VersionNumber

Version of the installed package, used in the `User-Agent` header.
"""
function package_version()
    v = pkgversion(@__MODULE__)
    return v === nothing ? v"0.0.0" : v
end

function default_user_agent()
    return string("OceanBIS.jl/", package_version(), " (", REPO_URL, "; Julia ", VERSION, ")")
end

const CONFIG = ClientConfig(
    DEFAULT_BASE_URL,
    DEFAULT_EXPORT_URL,
    "",             # filled by __init__, which needs the loaded package version
    60,
    5,
    1.0,
    60.0,
    5_000,
    0.0,
    100_000,
    nothing,
    false,
)

"""
    config() -> ClientConfig

Return the active client configuration.

```jldoctest
julia> OceanBIS.config().base_url
"https://api.obis.org/v3/"
```
"""
config() = CONFIG

"""
    configure!(; kwargs...) -> ClientConfig

Change client settings. Every keyword matches a field of [`ClientConfig`](@ref); omitted
keywords keep their current value.

Raising `page_size` reduces the number of requests a large pull makes, which is the
courteous direction. Parallelism is deliberately not offered: the OBIS data access page
asks users not to parallelize downloads.

# Examples

```julia
# Fewer, larger requests for a long pull.
OceanBIS.configure!(page_size = 10_000, progress = true)

# Cache raw responses so an analysis can be re-run against identical data.
OceanBIS.configure!(cache = OceanBIS.QueryCache())

# Wait longer between requests on a shared or metered connection.
OceanBIS.configure!(request_gap = 0.5)
```
"""
function configure!(;
    base_url::Union{Nothing,AbstractString}=nothing,
    export_url::Union{Nothing,AbstractString}=nothing,
    user_agent::Union{Nothing,AbstractString}=nothing,
    timeout::Union{Nothing,Integer}=nothing,
    retries::Union{Nothing,Integer}=nothing,
    backoff_base::Union{Nothing,Real}=nothing,
    backoff_max::Union{Nothing,Real}=nothing,
    page_size::Union{Nothing,Integer}=nothing,
    request_gap::Union{Nothing,Real}=nothing,
    api_record_limit::Union{Nothing,Integer}=nothing,
    cache::Any=missing,
    progress::Union{Nothing,Bool}=nothing,
)
    base_url === nothing || (CONFIG.base_url = ensure_trailing_slash(base_url))
    export_url === nothing || (CONFIG.export_url = ensure_trailing_slash(export_url))
    user_agent === nothing || (CONFIG.user_agent = String(user_agent))
    timeout === nothing || (CONFIG.timeout = check_positive(:timeout, timeout))
    retries === nothing || (CONFIG.retries = check_nonnegative(:retries, retries))
    backoff_base === nothing ||
        (CONFIG.backoff_base = check_positive(:backoff_base, backoff_base))
    backoff_max === nothing ||
        (CONFIG.backoff_max = check_positive(:backoff_max, backoff_max))
    request_gap === nothing ||
        (CONFIG.request_gap = check_nonnegative(:request_gap, request_gap))
    progress === nothing || (CONFIG.progress = progress)
    cache === missing || (CONFIG.cache = cache)

    if page_size !== nothing
        if !(1 <= page_size <= MAX_PAGE_SIZE)
            throw(
                OBISValidationError(
                    :page_size,
                    page_size,
                    "The API accepts a page size between 1 and $(MAX_PAGE_SIZE); larger " *
                    "values are rejected with HTTP 400. Use $(MAX_PAGE_SIZE) for the " *
                    "fewest requests on a large pull.",
                ),
            )
        end
        CONFIG.page_size = page_size
    end

    if api_record_limit !== nothing
        CONFIG.api_record_limit = check_nonnegative(:api_record_limit, api_record_limit)
    end

    return CONFIG
end

function ensure_trailing_slash(url::AbstractString)
    s = String(url)
    return endswith(s, '/') ? s : s * "/"
end

function check_positive(name::Symbol, v)
    v > 0 || throw(OBISValidationError(name, v, "Value must be greater than zero."))
    return v
end

function check_nonnegative(name::Symbol, v)
    v >= 0 || throw(OBISValidationError(name, v, "Value must not be negative."))
    return v
end
