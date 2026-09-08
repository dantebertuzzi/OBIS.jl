@testset "statistics" begin
    with_mock() do
        st = OBISClient.statistics("Abra alba")
        @test st["records"] > 0
        @test st["datasets"] > 0
        @test haskey(st, "yearrange")

        # The selection changes the count, which is the evidence that these records are
        # excluded by default rather than absent.
        abs_only = OBISClient.statistics("Abra alba"; absence=:only)
        @test abs_only["records"] > 0
        @test abs_only["records"] != st["records"]

        years = OBISClient.statistics_years("Abra alba")
        @test years isa Vector
        @test haskey(first(years), "year")
        @test haskey(first(years), "records")

        qc = OBISClient.statistics_qc("Abra alba")
        @test haskey(qc, "flags")
    end
end

@testset "facet" begin
    with_mock() do
        f = OBISClient.facet("flags"; scientificname="Abra alba")
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
        by_id = OBISClient.taxon(141433)
        @test OBISClient.nrow(by_id) == 1
        @test by_id.scientificName[1] == "Abra alba"
        @test by_id.taxonID[1] == 141433
        @test by_id.is_marine[1] === true

        by_name = OBISClient.taxon("Abra alba")
        @test by_name.taxonID[1] == by_id.taxonID[1]
        @test Tables.columnnames(by_name) == Tables.columnnames(by_id)
    end
end

@testset "checklist" begin
    with_mock() do
        list = OBISClient.checklist("Abra"; size=5)
        @test OBISClient.nrow(list) == 5
        @test all(!ismissing, list.scientificName)
        @test eltype(list.records) === Union{Missing,Int}
        # A checklist and a taxon lookup share a schema, so `records` is present in both
        # and simply missing where the endpoint does not supply it.
        @test Tables.columnnames(list) == Tables.columnnames(OBISClient.taxon(141433))
    end
end

@testset "node, area, country, institute" begin
    with_mock() do
        nodes = OBISClient.node()
        @test OBISClient.nrow(nodes) > 10
        @test all(!ismissing, nodes.id)
        @test eltype(nodes.lat) === Union{Missing,Float64}

        areas = OBISClient.area()
        @test OBISClient.nrow(areas) > 100
        @test eltype(areas.id) === Union{Missing,Int}

        countries = OBISClient.country()
        @test OBISClient.nrow(countries) > 10
        @test all(!ismissing, countries.country)

        institutes = OBISClient.institute("Abra alba")
        @test OBISClient.nrow(institutes) > 1
        @test eltype(institutes.records) === Union{Missing,Int}
    end
end

@testset "dataset" begin
    with_mock() do
        ds = OBISClient.dataset("Abra alba")
        @test OBISClient.nrow(ds) > 1
        @test all(!ismissing, ds.license)
        @test haskey(ds, :intellectualrights)
        @test eltype(ds.published) === Union{Missing,DateTime}

        # A licence identifier is derived for every dataset, and the raw text is kept.
        for (id, raw) in zip(ds.license, ds.intellectualrights)
            @test id == OBISClient.normalize_license(raw)
        end

        single = OBISClient.dataset_by_id("8acba7e7-2e50-4490-8328-b78a30472508")
        @test OBISClient.nrow(single) == 1
        @test single.license[1] == "CC-BY-4.0"
        @test !ismissing(single.citation[1])
        @test Tables.columnnames(single) == Tables.columnnames(ds)
    end
end

@testset "endpoints that need an identifier validate it" begin
    @test_throws OBISClient.OBISValidationError OBISClient.dataset_by_id("not-a-uuid")
    @test_throws OBISClient.OBISValidationError OBISClient.node("nope")
    @test_throws OBISClient.OBISValidationError OBISClient.metrics()
    @test_throws OBISClient.OBISValidationError OBISClient.metrics_downloads(
        "8acba7e7-2e50-4490-8328-b78a30472508"; groupby="space"
    )
    @test_throws OBISClient.OBISValidationError OBISClient.taxon("")
end

@testset "download metrics" begin
    with_mock() do
        id = "8acba7e7-2e50-4490-8328-b78a30472508"

        # `/metrics` answers with a bare object rather than the usual envelope, so it is
        # returned as plain Julia data instead of a table.
        yearly = OBISClient.metrics(; datasetid=id)
        @test yearly isa Dict
        @test haskey(yearly, "downloads")
        @test !isempty(yearly["downloads"])

        totals = OBISClient.metrics_downloads(id)
        @test totals["downloads"] > 0
        @test totals["records"] > 0

        # `groupby = "time"` swaps the aggregate for one entry per download event, which is
        # a different shape from the same endpoint.
        events = OBISClient.metrics_downloads(
            id; startdate=Date(2018, 10, 1), enddate=Date(2018, 12, 1), groupby="time"
        )
        @test haskey(events, "downloads")
        @test all(e -> haskey(e, "time"), events["downloads"])
    end
end

@testset "page size is validated when it is configured, not when it is sent" begin
    # The API rejects an oversized page with HTTP 400 after the request has gone out; the
    # package refuses it at the point the mistake was made.
    old = OBISClient.config().page_size
    try
        @test_throws OBISClient.OBISValidationError OBISClient.configure!(; page_size=0)
        @test_throws OBISClient.OBISValidationError OBISClient.configure!(;
            page_size=OBISClient.MAX_PAGE_SIZE + 1
        )
        OBISClient.configure!(; page_size=500)
        @test OBISClient.config().page_size == 500
    finally
        OBISClient.configure!(; page_size=old)
    end
end
