# Integration tests against the live OBIS API.
#
# These are not part of the default suite and never run in CI on every push. Their purpose
# is to detect changes in the API that the recorded fixtures would hide: a renamed field, a
# changed page-size limit, an error that stops being reported the way it was.
#
# Run them deliberately:
#
#     julia --project=. test/integration/runtests.jl
#
# They are written to be gentle: a handful of small, serial requests with the package's own
# courtesy pacing in force.

using Test
using Dates
using Tables
using OBIS

OBIS.configure!(; request_gap=0.5, page_size=5)

@testset "OBIS live API" begin
    @testset "the envelope and field names are unchanged" begin
        recs = OBIS.occurrence("Abra alba"; limit=5, licenses=false, check_size=false)
        @test OBIS.nrow(recs) == 5

        # Fields the package treats as always present. If one of these disappears, the
        # schema needs revisiting rather than silently filling with `missing`.
        for name in
            (:id, :dataset_id, :scientificName, :decimalLatitude, :decimalLongitude,
            :flags, :dropped, :absence, :aphiaID)
            @test haskey(recs, name)
            @test !all(ismissing, Tables.getcolumn(recs, name))
        end

        @test all(x -> x isa Float64, skipmissing(recs.decimalLatitude))
        @test all(x -> x isa Float64, skipmissing(recs.decimalLongitude))
    end

    @testset "timestamps are still milliseconds" begin
        recs = OBIS.occurrence("Abra alba"; limit=20, licenses=false, check_size=false)
        dates = collect(skipmissing(recs.date_start))
        if !isempty(dates)
            # If the API ever switched to seconds, these would land near 1970.
            @test all(d -> Date(1700) < Date(d) < Date(2100), dates)
        end
    end

    @testset "flags are still upper case and case-sensitive" begin
        # This is the behaviour the package normalizes around; if it changed, the
        # normalization would become unnecessary rather than wrong, but we want to know.
        upper = OBIS.statistics("Abra alba"; flags="ON_LAND")["records"]
        @test upper > 0

        params = OBIS.QueryParams()
        params["scientificname"] = "Abra alba"
        params["flags"] = "on_land"
        lower = OBIS.api_get("statistics", params)
        @test Int(lower[:records]) == 0
    end

    @testset "absence and dropped are still API-only and non-empty" begin
        base = OBIS.statistics("Abra alba")["records"]
        absence = OBIS.statistics("Abra alba"; absence=:only)["records"]
        included = OBIS.statistics("Abra alba"; absence=:include)["records"]

        @test absence > 0
        @test included == base + absence

        dropped = OBIS.statistics("Abra alba"; dropped=:only)["records"]
        @test dropped > 0
    end

    @testset "pagination is still keyset on id" begin
        pages = OBIS.occurrence_pages("Abra alba"; page_size=5)
        p1, st = iterate(pages)
        p2, _ = iterate(pages, st)
        @test issorted(p1.id)
        @test isempty(intersect(Set(p1.id), Set(p2.id)))
        @test all(id -> id > p1.id[end], p2.id)
    end

    @testset "the page size limit is still 10,000" begin
        params = OBIS.QueryParams()
        params["scientificname"] = "Abra alba"
        params["size"] = "10000"
        params["fields"] = "id"
        payload = OBIS.api_get("occurrence", params)
        @test length(OBIS.results_of(payload)) == 10_000
    end

    @testset "an unmatched name still reports NAME_NOT_FOUND in a 200" begin
        @test_throws OBIS.OBISNameNotFoundError OBIS.occurrence(
            "Notaspecies atallxyz"; limit=1, check_size=false
        )
    end

    @testset "flags cannot be selected through fields" begin
        # The package rejects this locally; here we confirm the API behaviour it is
        # protecting against has not changed.
        params = OBIS.QueryParams()
        params["scientificname"] = "Abra alba"
        params["size"] = "1"
        params["fields"] = "id,flags"
        rec = first(OBIS.results_of(OBIS.api_get("occurrence", params)))
        @test !haskey(rec, :flags)
    end

    @testset "dataset rights are still free text under intellectualrights" begin
        ds = OBIS.dataset_by_id("8acba7e7-2e50-4490-8328-b78a30472508")
        @test OBIS.nrow(ds) == 1
        @test !ismissing(ds.intellectualrights[1])
        @test ds.license[1] in OBIS.ACCEPTED_LICENSES
        @test !ismissing(ds.citation[1])
    end

    @testset "statistics still honours every occurrence filter" begin
        # The route heuristic depends on this: a pre-flight count is only useful if it
        # counts the records the occurrence query would return.
        for kwargs in (
            (; scientificname="Abra alba"),
            (; scientificname="Abra alba", instituteid=6223),
            (; scientificname="Abra alba", startdepth=10),
            (; scientificname="Abra alba", hasextensions="DNADerivedData"),
        )
            est = OBIS.estimate_size(; kwargs...)
            params = OBIS.build_params(; kwargs..., size=1)
            actual = OBIS.total_of(OBIS.api_get("occurrence", params))
            @test est == actual
        end
    end

    @testset "undocumented endpoints that the package relies on" begin
        # `/node` as a list is not in the API specification but is used by `OBIS.node()`.
        nodes = OBIS.node()
        @test OBIS.nrow(nodes) > 10

        # `/dataset?datasetid=` is likewise undocumented and used by the rights lookup.
        ds = OBIS.dataset(; datasetid="8acba7e7-2e50-4490-8328-b78a30472508")
        @test OBIS.nrow(ds) == 1
    end

    @testset "the export bucket is reachable without credentials" begin
        licenses = OBIS.export_licenses()
        @test OBIS.nrow(licenses) > 1000
        @test "CC-BY-NC-4.0" in Set(licenses.license)
    end
end
