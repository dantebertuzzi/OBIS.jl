@testset "statistics" begin
    with_mock() do
        st = OBIS.statistics("Abra alba")
        @test st["records"] > 0
        @test st["datasets"] > 0
        @test haskey(st, "yearrange")

        # The selection changes the count, which is the evidence that these records are
        # excluded by default rather than absent.
        abs_only = OBIS.statistics("Abra alba"; absence=:only)
        @test abs_only["records"] > 0
        @test abs_only["records"] != st["records"]

        years = OBIS.statistics_years("Abra alba")
        @test years isa Vector
        @test haskey(first(years), "year")
        @test haskey(first(years), "records")

        qc = OBIS.statistics_qc("Abra alba")
        @test haskey(qc, "flags")
    end
end

@testset "facet" begin
    with_mock() do
        f = OBIS.facet("flags"; scientificname="Abra alba")
        @test haskey(f, "flags")
        entries = f["flags"]
        @test !isempty(entries)
        @test haskey(first(entries), "key")
        @test haskey(first(entries), "records")
        # Flags come back upper case, which is what the filters must match.
        @test all(e -> e["key"] == uppercase(e["key"]), entries)
    end
end

@testset "taxon" begin
    with_mock() do
        by_id = OBIS.taxon(141433)
        @test OBIS.nrow(by_id) == 1
        @test by_id.scientificName[1] == "Abra alba"
        @test by_id.taxonID[1] == 141433
        @test by_id.is_marine[1] === true

        by_name = OBIS.taxon("Abra alba")
        @test by_name.taxonID[1] == by_id.taxonID[1]
        @test Tables.columnnames(by_name) == Tables.columnnames(by_id)
    end
end

@testset "checklist" begin
    with_mock() do
        list = OBIS.checklist("Abra"; size=5)
        @test OBIS.nrow(list) == 5
        @test all(!ismissing, list.scientificName)
        @test eltype(list.records) === Union{Missing,Int}
        # A checklist and a taxon lookup share a schema, so `records` is present in both
        # and simply missing where the endpoint does not supply it.
        @test Tables.columnnames(list) == Tables.columnnames(OBIS.taxon(141433))
    end
end

@testset "node, area, country, institute" begin
    with_mock() do
        nodes = OBIS.node()
        @test OBIS.nrow(nodes) > 10
        @test all(!ismissing, nodes.id)
        @test eltype(nodes.lat) === Union{Missing,Float64}

        areas = OBIS.area()
        @test OBIS.nrow(areas) > 100
        @test eltype(areas.id) === Union{Missing,Int}

        countries = OBIS.country()
        @test OBIS.nrow(countries) > 10
        @test all(!ismissing, countries.country)

        institutes = OBIS.institute("Abra alba")
        @test OBIS.nrow(institutes) > 1
        @test eltype(institutes.records) === Union{Missing,Int}
    end
end

@testset "dataset" begin
    with_mock() do
        ds = OBIS.dataset("Abra alba")
        @test OBIS.nrow(ds) > 1
        @test all(!ismissing, ds.license)
        @test haskey(ds, :intellectualrights)
        @test eltype(ds.published) === Union{Missing,DateTime}

        # A licence identifier is derived for every dataset, and the raw text is kept.
        for (id, raw) in zip(ds.license, ds.intellectualrights)
            @test id == OBIS.normalize_license(raw)
        end

        single = OBIS.dataset_by_id("8acba7e7-2e50-4490-8328-b78a30472508")
        @test OBIS.nrow(single) == 1
        @test single.license[1] == "CC-BY-4.0"
        @test !ismissing(single.citation[1])
        @test Tables.columnnames(single) == Tables.columnnames(ds)
    end
end

@testset "endpoints that need an identifier validate it" begin
    @test_throws OBIS.OBISValidationError OBIS.dataset_by_id("not-a-uuid")
    @test_throws OBIS.OBISValidationError OBIS.node("nope")
    @test_throws OBIS.OBISValidationError OBIS.metrics()
    @test_throws OBIS.OBISValidationError OBIS.metrics_downloads(
        "8acba7e7-2e50-4490-8328-b78a30472508"; groupby="space"
    )
    @test_throws OBIS.OBISValidationError OBIS.taxon("")
end
