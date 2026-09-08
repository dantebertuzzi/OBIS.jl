@testset "URL construction" begin
    q = OceanBIS.build_params(; scientificname="Abra alba", size=3)
    url = OceanBIS.build_url("occurrence", q; base_url="https://api.obis.org/v3/")
    @test startswith(url, "https://api.obis.org/v3/occurrence?")
    @test occursin("scientificname=Abra%20alba", url)
    @test occursin("size=3", url)

    @test OceanBIS.build_url("occurrence", OceanBIS.QueryParams(); base_url="https://x/") ==
        "https://x/occurrence"
    # A leading slash on the endpoint must not produce a doubled one.
    @test OceanBIS.build_url("/occurrence", OceanBIS.QueryParams(); base_url="https://x/") ==
        "https://x/occurrence"
end

@testset "the User-Agent identifies the client" begin
    h = Dict(OceanBIS.request_headers(OceanBIS.config()))
    @test occursin("OceanBIS.jl/", h["User-Agent"])
    @test occursin("github.com", h["User-Agent"])
    # gzip is worth requesting: the dataset and area listings are large and not paginated.
    @test h["Accept-Encoding"] == "gzip"
end

@testset "retry classification" begin
    # Transient failures are worth retrying.
    @test OceanBIS.retryable(429, "")
    @test OceanBIS.retryable(503, "gateway timeout")
    @test !OceanBIS.retryable(400, "Something broke: Size 20000 too large")
    @test !OceanBIS.retryable(404, "")

    # The API answers permanent client mistakes with 5xx and an `error` field. Retrying
    # those only wastes the server's time.
    @test !OceanBIS.retryable(500, """{"total":0,"results":[],"error":"Invalid date format"}""")
end

@testset "backoff grows and is bounded" begin
    cfg = OceanBIS.ClientConfig(
        "", "", "", 60, 5, 1.0, 60.0, 5000, 0.0, 100_000, nothing, false
    )
    d1 = OceanBIS.backoff_delay(1, cfg, nothing)
    d5 = OceanBIS.backoff_delay(5, cfg, nothing)
    @test 0.75 <= d1 <= 1.25
    @test d5 > d1
    @test OceanBIS.backoff_delay(20, cfg, nothing) <= cfg.backoff_max * 1.25
    # A server-supplied Retry-After wins over the computed schedule.
    @test OceanBIS.backoff_delay(1, cfg, 7) == 7.0
    @test OceanBIS.backoff_delay(1, cfg, 10_000) == cfg.backoff_max
end

@testset "errors in a 200 body are raised" begin
    params = OceanBIS.build_params(; scientificname="Notaspecies atallxyz")
    payload = JSON3.read("""{"total":0,"results":[],"error":"NAME_NOT_FOUND"}""")
    @test_throws OceanBIS.OBISNameNotFoundError OceanBIS.check_response(
        payload, "occurrence", params
    )

    other = JSON3.read("""{"total":0,"results":[],"error":"something else"}""")
    @test_throws OceanBIS.OBISAPIError OceanBIS.check_response(other, "occurrence", params)

    clean = JSON3.read("""{"total":0,"results":[]}""")
    @test OceanBIS.check_response(clean, "occurrence", params) === clean
end

@testset "HTTP errors carry advice" begin
    # No fixture is recorded for this request, so the mock refuses it and the request layer
    # exhausts its retry budget. The backoff is turned down for the duration: the point is
    # the error that comes out, not the thirty seconds of waiting on the way to it.
    old_base = OceanBIS.config().backoff_base
    try
        OceanBIS.configure!(; backoff_base=0.001)
        with_mock() do
            err = try
                OceanBIS.api_get(
                    "occurrence",
                    OceanBIS.build_params(; scientificname="Abra alba", size=10_000),
                )
                nothing
            catch e
                e
            end
            @test err isa OceanBIS.OBISError
        end
    finally
        OceanBIS.configure!(; backoff_base=old_base)
    end

    e = OceanBIS.OBISAPIError(
        400, "occurrence", OceanBIS.http_error_advice(400, ""), "Size too large"
    )
    msg = sprint(showerror, e)
    @test occursin("HTTP 400", msg)
    @test occursin("page_size", msg)

    e2 = OceanBIS.OBISNameNotFoundError("Notaspecies atallxyz")
    msg2 = sprint(showerror, e2)
    @test occursin("marinespecies.org", msg2)
    @test occursin("taxonid", msg2)
end

@testset "envelope helpers cope with every response shape" begin
    # Most endpoints use {total, results}, but several answer with a bare object or array.
    @test OceanBIS.total_of(JSON3.read("""{"total":7,"results":[]}""")) == 7
    @test OceanBIS.total_of(JSON3.read("""{"records":7}"""), 3) == 3
    @test length(OceanBIS.results_of(JSON3.read("""{"total":1,"results":[{"a":1}]}"""))) == 1
    @test length(OceanBIS.results_of(JSON3.read("""[{"year":1841}]"""))) == 1
    @test isempty(OceanBIS.results_of(JSON3.read("""{"lat":1.0,"lon":2.0}""")))
    @test isempty(OceanBIS.results_of(JSON3.read("""{"total":0,"results":null}""")))
end

@testset "malformed JSON is reported clearly" begin
    old = OceanBIS.TRANSPORT[]
    OceanBIS.TRANSPORT[] =
        (url, headers, timeout) ->
            (200, Dict("content-type" => "text/html"), "<html>not json</html>")
    try
        err = try
            OceanBIS.api_get("occurrence")
            nothing
        catch e
            e
        end
        @test err isa OceanBIS.OBISAPIError
        @test occursin("not valid JSON", sprint(showerror, err))
    finally
        OceanBIS.TRANSPORT[] = old
    end
end

@testset "connection failures retry then give up" begin
    attempts = Ref(0)
    old = OceanBIS.TRANSPORT[]
    OceanBIS.TRANSPORT[] = function (url, headers, timeout)
        attempts[] += 1
        return error("connection reset")
    end
    old_retries = OceanBIS.config().retries
    old_base = OceanBIS.config().backoff_base
    try
        OceanBIS.configure!(; retries=2, backoff_base=0.001)
        @test_throws OceanBIS.OBISConnectionError OceanBIS.api_get("occurrence")
        @test attempts[] == 3      # the initial attempt plus two retries
    finally
        OceanBIS.TRANSPORT[] = old
        OceanBIS.configure!(; retries=old_retries, backoff_base=old_base)
    end
end

@testset "a permanent 5xx is not retried" begin
    attempts = Ref(0)
    old = OceanBIS.TRANSPORT[]
    OceanBIS.TRANSPORT[] = function (url, headers, timeout)
        attempts[] += 1
        return (500, Dict{String,String}(),
            """{"total":0,"results":[],"error":"Invalid date format: nope"}""")
    end
    try
        OceanBIS.configure!(; retries=3, backoff_base=0.001)
        @test_throws OceanBIS.OBISAPIError OceanBIS.api_get("occurrence")
        @test attempts[] == 1
    finally
        OceanBIS.TRANSPORT[] = old
        OceanBIS.configure!(; retries=5, backoff_base=1.0)
    end
end

@testset "the courtesy gap is honoured between requests" begin
    # OBIS publishes no request quota and asks users not to parallelize downloads, so the
    # spacing between requests is the one rule the service asks for by name. Checked
    # against the clock rather than by inspection.
    old_gap = OceanBIS.config().request_gap
    try
        OceanBIS.configure!(; request_gap=0.2)
        OceanBIS.LAST_REQUEST[] = time()
        @test (@elapsed OceanBIS.throttle!(OceanBIS.config())) >= 0.15

        # A gap of zero must not sleep at all: the setting has to be genuinely free to
        # turn off, or a test suite serving fixtures would pay for it.
        OceanBIS.configure!(; request_gap=0.0)
        OceanBIS.LAST_REQUEST[] = time()
        @test (@elapsed OceanBIS.throttle!(OceanBIS.config())) < 0.05
    finally
        OceanBIS.configure!(; request_gap=old_gap)
    end
end

@testset "a 429 backs off and retries" begin
    # The one status where the server is explicitly asking for a pause, and the only one
    # where it says how long: `Retry-After` wins over the computed schedule.
    attempts = Ref(0)
    old = OceanBIS.TRANSPORT[]
    old_retries = OceanBIS.config().retries
    old_base = OceanBIS.config().backoff_base
    OceanBIS.TRANSPORT[] = function (url, headers, timeout)
        attempts[] += 1
        attempts[] == 1 && return (429, Dict("retry-after" => "0"), "slow down")
        return (200, Dict{String,String}(), """{"total":0,"results":[]}""")
    end
    try
        OceanBIS.configure!(; retries=2, backoff_base=0.001)
        payload = OceanBIS.api_get("occurrence")
        @test attempts[] == 2
        @test OceanBIS.total_of(payload) == 0
    finally
        OceanBIS.TRANSPORT[] = old
        OceanBIS.configure!(; retries=old_retries, backoff_base=old_base)
    end
end

@testset "every status maps to advice the caller can act on" begin
    # An HTTP status on its own tells a user nothing about what to do next, and these are
    # the sentences that do.
    @test occursin("page_size", OceanBIS.http_error_advice(400, ""))
    @test occursin("endpoints", OceanBIS.http_error_advice(404, ""))
    @test occursin("request_gap", OceanBIS.http_error_advice(429, ""))
    @test occursin("server error", OceanBIS.http_error_advice(503, ""))
    # An unclassified status still gets a sentence rather than an empty message.
    @test OceanBIS.http_error_advice(418, "") == "The request failed."
end
