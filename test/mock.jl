# A transport that serves recorded fixtures instead of reaching the network.
#
# The test suite must never depend on the OBIS service being up, fast, or unchanged, so
# every unit test runs against responses recorded once by test/record_fixtures.jl.
#
# URLs are matched after normalization rather than literally: the package percent-encodes
# WKT and other punctuation differently from a hand-written URL, and parameter order is an
# implementation detail. Comparing decoded, sorted parameters keeps the fixtures readable
# and the matching robust.

using HTTP
using JSON3

const FIXTURE_DIR = joinpath(@__DIR__, "fixtures")

"""
    normalize_url(url) -> String

Reduce a URL to a canonical form: path, then decoded parameters sorted by name.
"""
function normalize_url(url::AbstractString)
    uri = HTTP.URI(url)
    path = rstrip(string(uri.scheme, "://", uri.host, uri.path), '/')
    isempty(uri.query) && return path
    parts = String[]
    for kv in split(uri.query, '&')
        isempty(kv) && continue
        i = findfirst('=', kv)
        if i === nothing
            push!(parts, HTTP.unescapeuri(kv) * "=")
        else
            k = HTTP.unescapeuri(kv[1:(i - 1)])
            v = HTTP.unescapeuri(kv[(i + 1):end])
            push!(parts, string(k, '=', v))
        end
    end
    sort!(parts)
    return string(path, '?', join(parts, '&'))
end

"""
    load_fixtures() -> Dict{String,Tuple{Int,String}}

Read the recorded manifest into a lookup from normalized URL to `(status, body)`.
"""
function load_fixtures()
    manifest_path = joinpath(FIXTURE_DIR, "manifest.json")
    isfile(manifest_path) || error(
        "No fixtures found at $(manifest_path). Record them with " *
        "`julia --project=. test/record_fixtures.jl` (this reaches the live API).",
    )
    manifest = JSON3.read(read(manifest_path, String))
    out = Dict{String,Tuple{Int,String}}()
    for (url, entry) in pairs(manifest)
        body = read(joinpath(FIXTURE_DIR, String(entry["file"])), String)
        out[normalize_url(String(url))] = (Int(entry["status"]), body)
    end
    return out
end

const FIXTURES = load_fixtures()

"Requests the mock transport has served, in order, for assertions about request counts."
const REQUEST_LOG = String[]

"""
    mock_transport(url, headers, timeout) -> (status, headers, body)

Serve a recorded response, or fail loudly naming the URL that was not recorded.

An unrecorded URL is an error rather than a network call: a test that silently reached the
API would pass or fail for reasons unrelated to the code under test.
"""
function mock_transport(url::AbstractString, headers, timeout::Integer)
    push!(REQUEST_LOG, String(url))
    key = normalize_url(url)
    haskey(FIXTURES, key) || error(
        """
        No fixture recorded for this request:
          $(url)
        normalized to:
          $(key)
        Add it to test/record_fixtures.jl and re-record, or adjust the test to use a
        request that is already recorded.""",
    )
    status, body = FIXTURES[key]
    return (
        status, Dict("content-type" => "application/json", "etag" => "W/\"test\""), body
    )
end

"""
    with_mock(f)

Run `f` with the mock transport installed and the request log cleared.
"""
function with_mock(f)
    old = OBIS.TRANSPORT[]
    OBIS.TRANSPORT[] = mock_transport
    empty!(REQUEST_LOG)
    try
        return f()
    finally
        OBIS.TRANSPORT[] = old
    end
end

"""
    fixture(name) -> String

Read a recorded fixture body by name, for tests that parse a response directly.
"""
function fixture(name::AbstractString)
    for ext in (".json", ".txt", ".tsv")
        p = joinpath(FIXTURE_DIR, name * ext)
        isfile(p) && return read(p, String)
    end
    return error("no fixture named $(name)")
end
