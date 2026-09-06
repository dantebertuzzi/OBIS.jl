@testset "query size estimation" begin
    with_mock() do
        n = OBIS.estimate_size(; scientificname="Abra alba")
        @test n > 0
        @test n == OBIS.statistics("Abra alba")["records"]

        # Pagination parameters change what a page holds, not how many records match, so
        # they must not reach the estimate.
        params = OBIS.build_params(; scientificname="Abra alba", size=10, after="x")
        @test OBIS.estimate_size(params) == n
    end
end

@testset "a large query is refused, not silently rerouted" begin
    with_mock() do
        old = OBIS.config().api_record_limit
        try
            OBIS.configure!(; api_record_limit=1000)
            err = try
                OBIS.occurrence("Mollusca")
                nothing
            catch e
                e
            end
            @test err isa OBIS.OBISLargeQueryError

            msg = sprint(showerror, err)
            # The message must name every way forward, because the two routes do not cover
            # the same records and the choice belongs to the caller.
            @test occursin("limit =", msg)
            @test occursin("occurrence_pages", msg)
            @test occursin("download_exports", msg)
            @test occursin("api_record_limit", msg)
            @test occursin("check_size = false", msg)

            # A limited or explicitly unchecked pull is allowed through.
            OBIS.configure!(; api_record_limit=1000)
            @test OBIS.nrow(OBIS.occurrence("Abra alba"; limit=3, licenses=false)) == 3
        finally
            OBIS.configure!(; api_record_limit=old)
        end
    end
end

@testset "export coverage" begin
    @test OBIS.export_covers()
    @test OBIS.export_covers(; scientificname="Abra alba")
    @test OBIS.export_covers(; absence=:exclude)

    # The export excludes dropped records, and OBIS documentation is inconsistent about
    # absence records, so these queries stay on the API.
    @test !OBIS.export_covers(; absence=:only)
    @test !OBIS.export_covers(; absence=:include)
    @test !OBIS.export_covers(; dropped=:only)
    @test !OBIS.export_covers(; event=:only)
end

@testset "export URLs" begin
    id = "8acba7e7-2e50-4490-8328-b78a30472508"
    @test OBIS.export_url(id) ==
        "https://obis-open-data.s3.amazonaws.com/occurrence/$(id).parquet"
    @test OBIS.export_archive_url(id) ==
        "https://obis-open-data.s3.amazonaws.com/dwca/$(id).zip"
    @test_throws OBIS.OBISValidationError OBIS.export_url("not-a-uuid")
end

@testset "an API-only query cannot be sent to the export" begin
    @test_throws OBIS.OBISValidationError OBIS.download_exports(
        "Abra alba"; absence=:only
    )
end

@testset "the export licence table parses" begin
    with_mock() do
        licenses = OBIS.export_licenses()
        @test OBIS.nrow(licenses) > 10
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
    t = OBIS.parse_licenses_tsv(text)
    @test OBIS.nrow(t) == 2
    @test t.dataset_id == ["aaa", "bbb"]
    @test t.license == ["CC0-1.0", "CC-BY-4.0"]
    @test occursin("spans lines", t.citation[2])
end
