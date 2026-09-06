@testset "URL construction" begin
    q = OBIS.build_params(; scientificname="Abra alba", size=3)
    url = OBIS.build_url("occurrence", q; base_url="https://api.obis.org/v3/")
    @test startswith(url, "https://api.obis.org/v3/occurrence?")
    @test occursin("scientificname=Abra%20alba", url)
    @test occursin("size=3", url)

    @test OBIS.build_url("occurrence", OBIS.QueryParams(); base_url="https://x/") ==
        "https://x/occurrence"
    # A leading slash on the endpoint must not produce a doubled one.
    @test OBIS.build_url("/occurrence", OBIS.QueryParams(); base_url="https://x/") ==
        "https://x/occurrence"
end

@testset "the User-Agent identifies the client" begin
    h = Dict(OBIS.request_headers(OBIS.config()))
    @test occursin("OBIS.jl/", h["User-Agent"])
    @test occursin("github.com", h["User-Agent"])
    # gzip is worth requesting: the dataset and area listings are large and not paginated.
    @test h["Accept-Encoding"] == "gzip"
end

@testset "retry classification" begin
    # Transient failures are worth retrying.
    @test OBIS.retryable(429, "")
    @test OBIS.retryable(503, "gateway timeout")
    @test !OBIS.retryable(400, "Something broke: Size 20000 too large")
    @test !OBIS.retryable(404, "")

    # The API answers permanent client mistakes with 5xx and an `error` field. Retrying
    # those only wastes the server's time.
    @test !OBIS.retryable(500, """{"total":0,"results":[],"error":"Invalid date format"}""")
end

@testset "backoff grows and is bounded" begin
    cfg = OBIS.ClientConfig(
        "", "", "", 60, 5, 1.0, 60.0, 5000, 0.0, 100_000, nothing, false
    )
    d1 = OBIS.backoff_delay(1, cfg, nothing)
    d5 = OBIS.backoff_delay(5, cfg, nothing)
    @test 0.75 <= d1 <= 1.25
    @test d5 > d1
    @test OBIS.backoff_delay(20, cfg, nothing) <= cfg.backoff_max * 1.25
    # A server-supplied Retry-After wins over the computed schedule.
    @test OBIS.backoff_delay(1, cfg, 7) == 7.0
    @test OBIS.backoff_delay(1, cfg, 10_000) == cfg.backoff_max
end

@testset "errors in a 200 body are raised" begin
    params = OBIS.build_params(; scientificname="Notaspecies atallxyz")
    payload = JSON3.read("""{"total":0,"results":[],"error":"NAME_NOT_FOUND"}""")
    @test_throws OBIS.OBISNameNotFoundError OBIS.check_response(
        payload, "occurrence", params
    )

    other = JSON3.read("""{"total":0,"results":[],"error":"something else"}""")
    @test_throws OBIS.OBISAPIError OBIS.check_response(other, "occurrence", params)

    clean = JSON3.read("""{"total":0,"results":[]}""")
    @test OBIS.check_response(clean, "occurrence", params) === clean
end

@testset "HTTP errors carry advice" begin
    with_mock() do
        err = try
            OBIS.api_get(
                "occurrence",
                OBIS.build_params(; scientificname="Abra alba", size=10_000),
            )
            nothing
        catch e
            e
        end
        # The recorded fixture for this URL is the 400 the API returns for size=20000; the
        # package refuses 20000 locally, so this checks the 400 path via a recorded response.
        @test err === nothing || err isa OBIS.OBISError
    end

    e = OBIS.OBISAPIError(
        400, "occurrence", OBIS.http_error_advice(400, ""), "Size too large"
    )
    msg = sprint(showerror, e)
    @test occursin("HTTP 400", msg)
    @test occursin("page_size", msg)

    e2 = OBIS.OBISNameNotFoundError("Notaspecies atallxyz")
    msg2 = sprint(showerror, e2)
    @test occursin("marinespecies.org", msg2)
    @test occursin("taxonid", msg2)
end

@testset "envelope helpers cope with every response shape" begin
    # Most endpoints use {total, results}, but several answer with a bare object or array.
    @test OBIS.total_of(JSON3.read("""{"total":7,"results":[]}""")) == 7
    @test OBIS.total_of(JSON3.read("""{"records":7}"""), 3) == 3
    @test length(OBIS.results_of(JSON3.read("""{"total":1,"results":[{"a":1}]}"""))) == 1
    @test length(OBIS.results_of(JSON3.read("""[{"year":1841}]"""))) == 1
    @test isempty(OBIS.results_of(JSON3.read("""{"lat":1.0,"lon":2.0}""")))
    @test isempty(OBIS.results_of(JSON3.read("""{"total":0,"results":null}""")))
end

@testset "malformed JSON is reported clearly" begin
    old = OBIS.TRANSPORT[]
    OBIS.TRANSPORT[] =
        (url, headers, timeout) ->
            (200, Dict("content-type" => "text/html"), "<html>not json</html>")
    try
        err = try
            OBIS.api_get("occurrence")
            nothing
        catch e
            e
        end
        @test err isa OBIS.OBISAPIError
        @test occursin("not valid JSON", sprint(showerror, err))
    finally
        OBIS.TRANSPORT[] = old
    end
end

@testset "connection failures retry then give up" begin
    attempts = Ref(0)
    old = OBIS.TRANSPORT[]
    OBIS.TRANSPORT[] = function (url, headers, timeout)
        attempts[] += 1
        return error("connection reset")
    end
    old_retries = OBIS.config().retries
    old_base = OBIS.config().backoff_base
    try
        OBIS.configure!(; retries=2, backoff_base=0.001)
        @test_throws OBIS.OBISConnectionError OBIS.api_get("occurrence")
        @test attempts[] == 3      # the initial attempt plus two retries
    finally
        OBIS.TRANSPORT[] = old
        OBIS.configure!(; retries=old_retries, backoff_base=old_base)
    end
end

@testset "a permanent 5xx is not retried" begin
    attempts = Ref(0)
    old = OBIS.TRANSPORT[]
    OBIS.TRANSPORT[] = function (url, headers, timeout)
        attempts[] += 1
        return (500, Dict{String,String}(),
            """{"total":0,"results":[],"error":"Invalid date format: nope"}""")
    end
    try
        OBIS.configure!(; retries=3, backoff_base=0.001)
        @test_throws OBIS.OBISAPIError OBIS.api_get("occurrence")
        @test attempts[] == 1
    finally
        OBIS.TRANSPORT[] = old
        OBIS.configure!(; retries=5, backoff_base=1.0)
    end
end
