# Exception types.
#
# The OBIS API reports most failures with an HTTP 200 status (see NOTES.md section 8), so
# these types are raised from response *content* at least as often as from status codes.
# Every message states what the caller can do about the problem, because a bare status
# code is not actionable.

"""
    OBISError

Abstract supertype for every error raised by OceanBIS.jl. Catch this to handle any failure
from the package without catching unrelated exceptions.
"""
abstract type OBISError <: Exception end

"""
    OBISValidationError(parameter, value, message)

A request was rejected locally, before it reached the API.

The API ignores unknown query parameters and returns an empty result set for many invalid
values instead of reporting an error, so a malformed request would otherwise come back as
a plausible-looking empty answer. Validating locally turns that silence into this error.
"""
struct OBISValidationError <: OBISError
    parameter::Symbol
    value::Any
    message::String
end

function Base.showerror(io::IO, e::OBISValidationError)
    print(io, "OBISValidationError: invalid value for `", e.parameter, "`")
    if e.value !== nothing
        print(io, " (got ", repr(e.value), ")")
    end
    print(io, "\n  ", e.message)
    return nothing
end

"""
    OBISNameNotFoundError(name)

The API matched no taxon for a `scientificname`.

This is reported separately because the API signals it with `NAME_NOT_FOUND` inside an
HTTP 200 response whose body is an ordinary empty result set. Returning that empty set
would let a misspelled name read as a genuine absence of records.
"""
struct OBISNameNotFoundError <: OBISError
    name::String
end

function Base.showerror(io::IO, e::OBISNameNotFoundError)
    print(
        io,
        "OBISNameNotFoundError: OBIS matched no taxon for scientificname = ",
        repr(e.name),
        """

          The API returns an empty result set for an unmatched name, which is not the same
          as a taxon with no records. Check the spelling against the World Register of
          Marine Species (https://www.marinespecies.org), or query by AphiaID with
          `taxonid` instead, which is unambiguous.""",
    )
    return nothing
end

"""
    OBISAPIError(status, endpoint, message, body)

The API reported a failure, either through an HTTP status or through an `error` key in an
otherwise well-formed response body.
"""
struct OBISAPIError <: OBISError
    status::Int
    endpoint::String
    message::String
    body::String
end

function Base.showerror(io::IO, e::OBISAPIError)
    print(io, "OBISAPIError: request to ", e.endpoint, " failed")
    e.status > 0 && print(io, " (HTTP ", e.status, ")")
    print(io, "\n  ", e.message)
    if !isempty(e.body)
        snippet = length(e.body) > 300 ? string(first(e.body, 300), " …") : e.body
        print(io, "\n  Response: ", snippet)
    end
    return nothing
end

"""
    OBISConnectionError(endpoint, message)

The request never produced a response: a network failure, a timeout, or a retry budget
exhausted against repeated server errors.
"""
struct OBISConnectionError <: OBISError
    endpoint::String
    message::String
end

function Base.showerror(io::IO, e::OBISConnectionError)
    print(
        io,
        "OBISConnectionError: could not reach ",
        e.endpoint,
        "\n  ",
        e.message,
        """

          If this persists, check https://obis.org for service status. To retry more
          patiently, raise the retry budget with `OceanBIS.configure!(retries = 8)`.""",
    )
    return nothing
end

"""
    OBISLargeQueryError(estimate, threshold, suggestion)

A query was estimated to return more records than the configured API threshold.

Raised rather than silently switching access routes: the two routes differ in coverage
(see [`export_covers`](@ref)), so the choice belongs to the caller.
"""
struct OBISLargeQueryError <: OBISError
    estimate::Int
    threshold::Int
    suggestion::String
end

function Base.showerror(io::IO, e::OBISLargeQueryError)
    print(
        io,
        "OBISLargeQueryError: this query matches about ",
        format_count(e.estimate),
        " records, above the configured API limit of ",
        format_count(e.threshold),
        ".\n",
        e.suggestion,
    )
    return nothing
end

"""
    format_count(n)

Render an integer with thousands separators, for error and log messages.
"""
function format_count(n::Integer)
    s = string(abs(n))
    parts = String[]
    while length(s) > 3
        pushfirst!(parts, s[(end - 2):end])
        s = s[1:(end - 3)]
    end
    pushfirst!(parts, s)
    return string(n < 0 ? "-" : "", join(parts, ","))
end
