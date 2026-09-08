@testset "query size estimation" begin
    with_mock() do
        n = OBISClient.estimate_size(; scientificname="Abra alba")
        @test n > 0
        @test n == OBISClient.statistics("Abra alba")["records"]

        # Pagination parameters change what a page holds, not how many records match, so
        # they must not reach the estimate.
        params = OBISClient.build_params(; scientificname="Abra alba", size=10, after="x")
        @test OBISClient.estimate_size(params) == n
    end
end

@testset "a large query is refused, not silently rerouted" begin
    with_mock() do
        old = OBISClient.config().api_record_limit
        try
            OBISClient.configure!(; api_record_limit=1000)
            err = try
                OBISClient.occurrence("Mollusca")
                nothing
            catch e
                e
            end
            @test err isa OBISClient.OBISLargeQueryError

            msg = sprint(showerror, err)
            # The message must name every way forward, because the two routes do not cover
            # the same records and the choice belongs to the caller.
            @test occursin("limit =", msg)
            @test occursin("occurrence_pages", msg)
            @test occursin("download_exports", msg)
            @test occursin("api_record_limit", msg)
            @test occursin("check_size = false", msg)

            # A limited or explicitly unchecked pull is allowed through.
            OBISClient.configure!(; api_record_limit=1000)
            @test OBISClient.nrow(
                OBISClient.occurrence("Abra alba"; limit=3, licenses=false)
            ) == 3
        finally
            OBISClient.configure!(; api_record_limit=old)
        end
    end
end

@testset "export coverage" begin
    @test OBISClient.export_covers()
    @test OBISClient.export_covers(; scientificname="Abra alba")
    @test OBISClient.export_covers(; absence=:exclude)

    # Absence and dropped records are in the export, whatever the OBIS data access page
    # says: across five datasets the export's counts for both matched the API's
    # `absence = :only` and `dropped = :only` counts exactly (NOTES.md §7.3).
    @test OBISClient.export_covers(; absence=:only)
    @test OBISClient.export_covers(; absence=:include)
    @test OBISClient.export_covers(; dropped=:only)

    # Pure event records are the one selection the export cannot serve: no column in the
    # file identifies them, so there is nothing to filter on.
    @test !OBISClient.export_covers(; event=:only)
    @test !OBISClient.export_covers(; event=:include)

    # A mistyped selection is still an error here, even though only `event` decides.
    @test_throws OBISClient.OBISValidationError OBISClient.export_covers(; absence=:maybe)
    @test_throws OBISClient.OBISValidationError OBISClient.export_covers(; dropped=:maybe)

    # The route heuristic reads the same rule from a built parameter set, so the guard's
    # advice cannot drift from what this function reports.
    @test OBISClient.export_covers(
        OBISClient.build_params(; scientificname="Abra alba", absence=:only)
    )
    @test !OBISClient.export_covers(
        OBISClient.build_params(; scientificname="Abra alba", event=:only)
    )
end

@testset "export URLs" begin
    id = "8acba7e7-2e50-4490-8328-b78a30472508"
    @test OBISClient.export_url(id) ==
        "https://obis-open-data.s3.amazonaws.com/occurrence/$(id).parquet"
    @test OBISClient.export_archive_url(id) ==
        "https://obis-open-data.s3.amazonaws.com/dwca/$(id).zip"
    @test_throws OBISClient.OBISValidationError OBISClient.export_url("not-a-uuid")
end

@testset "an API-only query cannot be sent to the export" begin
    @test_throws OBISClient.OBISValidationError OBISClient.download_exports(
        "Abra alba"; event=:only
    )
end

@testset "the export licence table parses" begin
    with_mock() do
        licenses = OBISClient.export_licenses()
        @test OBISClient.nrow(licenses) > 10
        @test Tables.columnnames(licenses) ==
            [:dataset_id, :license, :license_url, :intellectualrights, :citation]
        @test all(!ismissing, licenses.dataset_id)

        # The URL column collapses dozens of prose spellings onto a handful of licences.
        ids = Set(licenses.license)
        @test issubset(
            ids, Set(["CC0-1.0", "CC-BY-4.0", "CC-BY-NC-4.0", "CC-BY-SA-4.0", "unknown"])
        )
        @test "CC-BY-4.0" in ids
    end
end

@testset "TSV parsing handles embedded newlines" begin
    # Citation text in the licence table contains quotes and line breaks, so rows are
    # joined until they hold the expected number of fields.
    text = """
    id\tlicense\tlicense_url\tcitation
    aaa\tCC0\thttp://creativecommons.org/publicdomain/zero/1.0/legalcode\tSimple citation.
    bbb\tCC-BY\thttp://creativecommons.org/licenses/by/4.0/legalcode\t"A citation
    that spans lines."
    """
    t = OBISClient.parse_licenses_tsv(text)
    @test OBISClient.nrow(t) == 2
    @test t.dataset_id == ["aaa", "bbb"]
    @test t.license == ["CC0-1.0", "CC-BY-4.0"]
    @test occursin("spans lines", t.citation[2])
end

@testset "a failed size estimate does not block the query" begin
    # The estimate is a courtesy, not a gate: if `/statistics` is unavailable the pull
    # should go ahead and let the progress indicator show how large it turns out to be.
    # Refusing the query because the pre-flight check failed would be the worse answer.
    old = OBISClient.TRANSPORT[]
    old_limit = OBISClient.config().api_record_limit
    OBISClient.TRANSPORT[] =
        (url, headers, timeout) ->
            (500, Dict{String,String}(), """{"error":"Invalid date format"}""")
    try
        # A limit of one record: any estimate that came back at all would refuse the
        # query, so passing proves the failed estimate was the reason it went through.
        OBISClient.configure!(; api_record_limit=1)
        @test OBISClient.guard_query_size(
            OBISClient.build_params(; scientificname="Abra alba")
        ) ===
            nothing
    finally
        OBISClient.TRANSPORT[] = old
        OBISClient.configure!(; api_record_limit=old_limit)
    end
end

@testset "the export is offered only for a query it can serve" begin
    # The guard's advice has to match `export_covers`, or it sends the caller to a route
    # that cannot answer their question. Driven through a stub estimate so the test does
    # not depend on how many event records OBIS happens to hold for a given taxon.
    old_transport = OBISClient.TRANSPORT[]
    old_limit = OBISClient.config().api_record_limit
    OBISClient.TRANSPORT[] =
        (url, headers, timeout) -> (200, Dict{String,String}(), """{"records":5000000}""")
    try
        OBISClient.configure!(; api_record_limit=1000)

        # Pure event records: nothing in an export file identifies them, so the export is
        # not among the options.
        err = try
            OBISClient.guard_query_size(
                OBISClient.build_params(; scientificname="Abra alba", event=:only)
            )
            nothing
        catch e
            e
        end
        @test err isa OBISClient.OBISLargeQueryError
        msg = sprint(showerror, err)
        @test occursin("no column that identifies them", msg)
        @test !occursin("download_exports", msg)
        # The routes that do work for this query are still named.
        @test occursin("occurrence_pages", msg)

        # Absence records are in the export, so it is offered like any other query.
        err2 = try
            OBISClient.guard_query_size(
                OBISClient.build_params(; scientificname="Abra alba", absence=:only)
            )
            nothing
        catch e
            e
        end
        @test err2 isa OBISClient.OBISLargeQueryError
        @test occursin("download_exports", sprint(showerror, err2))
    finally
        OBISClient.TRANSPORT[] = old_transport
        OBISClient.configure!(; api_record_limit=old_limit)
    end
end

@testset "a previously downloaded licence table is read from disk" begin
    # The table is regenerated with the export and is large; a user who has it already
    # should not have to fetch it again to parse it.
    mktemp() do path, io
        write(io, fixture("licenses"))
        close(io)
        t = OBISClient.export_licenses(; path=path)
        @test OBISClient.nrow(t) > 10
        @test "CC-BY-4.0" in Set(t.license)
    end
end

@testset "the export bucket gets the same retry rules as the API" begin
    # The bucket is not under the API base URL and so has a request path of its own. It
    # must not quietly lose the backoff, the identification and the error reporting that
    # the API path has.
    old = OBISClient.TRANSPORT[]
    old_retries = OBISClient.config().retries
    old_base = OBISClient.config().backoff_base
    try
        OBISClient.configure!(; retries=2, backoff_base=0.001)

        attempts = Ref(0)
        OBISClient.TRANSPORT[] = function (url, headers, timeout)
            attempts[] += 1
            attempts[] == 1 && return (503, Dict{String,String}(), "temporarily down")
            return (200, Dict{String,String}(), fixture("licenses"))
        end
        t = OBISClient.export_licenses()
        @test attempts[] == 2
        @test OBISClient.nrow(t) > 10

        # A permanent failure is reported with the same advice as on the API path.
        OBISClient.TRANSPORT[] =
            (url, headers, timeout) -> (404, Dict{String,String}(), "not found")
        err = try
            OBISClient.export_licenses()
            nothing
        catch e
            e
        end
        @test err isa OBISClient.OBISAPIError
        @test occursin("No such endpoint", sprint(showerror, err))

        # And a connection failure exhausts the budget rather than looping.
        attempts[] = 0
        OBISClient.TRANSPORT[] = function (url, headers, timeout)
            attempts[] += 1
            return error("connection reset")
        end
        @test_throws OBISClient.OBISConnectionError OBISClient.export_licenses()
        @test attempts[] == 3      # the initial attempt plus two retries
    finally
        OBISClient.TRANSPORT[] = old
        OBISClient.configure!(; retries=old_retries, backoff_base=old_base)
    end
end

@testset "an export is downloaded once and then reused" begin
    with_mock() do
        mktempdir() do dir
            id = "8acba7e7-2e50-4490-8328-b78a30472508"

            path = OBISClient.download_export(id; dir=dir)
            @test path == joinpath(dir, id * ".parquet")
            @test isfile(path)
            @test DOWNLOAD_LOG == [OBISClient.export_url(id)]

            # These files run to megabytes, so re-running a script must not re-fetch one
            # that is already on disk.
            again = @test_logs (:info, r"already present") OBISClient.download_export(
                id; dir=dir
            )
            @test again == path
            @test length(DOWNLOAD_LOG) == 1

            # Unless the caller says so, which is how a stale copy gets refreshed.
            OBISClient.download_export(id; dir=dir, overwrite=true)
            @test length(DOWNLOAD_LOG) == 2

            @test_throws OBISClient.OBISValidationError OBISClient.download_export(
                "not-a-uuid"; dir=dir
            )
        end
    end
end

@testset "an interrupted download leaves nothing behind" begin
    # The file lands on `.part` and is moved into place only once it is whole, so a failure
    # cannot leave a truncated Parquet file that a later run would take for finished.
    old = OBISClient.DOWNLOADER[]
    OBISClient.DOWNLOADER[] = function (url, path, headers)
        write(path, "PAR1 half a fi")
        return error("connection reset")
    end
    try
        mktempdir() do dir
            err = try
                OBISClient.download_export("8acba7e7-2e50-4490-8328-b78a30472508"; dir=dir)
                nothing
            catch e
                e
            end
            @test err isa OBISClient.OBISConnectionError
            # Where the failure was matters: the bucket is not the API, and a user chasing
            # it should not go looking at the wrong service.
            @test occursin("unrelated to the API", sprint(showerror, err))
            @test isempty(readdir(dir))
        end
    finally
        OBISClient.DOWNLOADER[] = old
    end
end

@testset "a query's exports are downloaded one dataset at a time" begin
    with_mock() do
        mktempdir() do dir
            paths = String[]
            @test_logs (:info, r"Downloading") match_mode = :any begin
                paths = OBISClient.download_exports("Abra alba"; dir=dir)
            end
            @test length(paths) == 18
            @test all(isfile, paths)
            @test all(p -> endswith(p, ".parquet"), paths)
            # Serial, as the data access page asks: one request per dataset, in order.
            @test length(DOWNLOAD_LOG) == length(paths)
        end
    end
end

@testset "one failed export does not abandon the rest" begin
    # The export is regenerated periodically and lags the API, so a dataset that has no
    # file in the bucket yet is ordinary. Losing the other seventeen downloads over it
    # would be the wrong trade.
    with_mock() do
        mktempdir() do dir
            calls = Ref(0)
            OBISClient.DOWNLOADER[] = function (url, path, headers)
                calls[] += 1
                calls[] == 1 && error("404 from the bucket")
                write(path, "PAR1 stand-in")
                return path
            end
            paths = String[]
            @test_logs (:warn, r"Could not download the export") match_mode = :any begin
                paths = OBISClient.download_exports("Abra alba"; dir=dir)
            end
            @test length(paths) == calls[] - 1
            @test length(paths) == 17
        end
    end
end

@testset "a query that touches no dataset downloads nothing" begin
    old = OBISClient.TRANSPORT[]
    OBISClient.TRANSPORT[] =
        (url, headers, timeout) ->
            (200, Dict{String,String}(), """{"total":0,"results":[]}""")
    try
        mktempdir() do dir
            @test OBISClient.download_exports("Notaspecies atallxyz"; dir=dir) == String[]
            @test isempty(readdir(dir))
        end
    finally
        OBISClient.TRANSPORT[] = old
    end
end
