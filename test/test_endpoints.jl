@testset "statistics" begin
    with_mock() do
        st = OceanBIS.statistics("Abra alba")
        @test st["records"] > 0
        @test st["datasets"] > 0
        @test haskey(st, "yearrange")

        # The selection changes the count, which is the evidence that these records are
        # excluded by default rather than absent.
        abs_only = OceanBIS.statistics("Abra alba"; absence=:only)
        @test abs_only["records"] > 0
        @test abs_only["records"] != st["records"]

        years = OceanBIS.statistics_years("Abra alba")
        @test years isa Vector
        @test haskey(first(years), "year")
        @test haskey(first(years), "records")

        qc = OceanBIS.statistics_qc("Abra alba")
        @test haskey(qc, "flags")
    end
end

@testset "facet" begin
    with_mock() do
        f = OceanBIS.facet("flags"; scientificname="Abra alba")
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
        by_id = OceanBIS.taxon(141433)
        @test OceanBIS.nrow(by_id) == 1
        @test by_id.scientificName[1] == "Abra alba"
        @test by_id.taxonID[1] == 141433
        @test by_id.is_marine[1] === true

        by_name = OceanBIS.taxon("Abra alba")
        @test by_name.taxonID[1] == by_id.taxonID[1]
        @test Tables.columnnames(by_name) == Tables.columnnames(by_id)
    end
end

@testset "checklist" begin
    with_mock() do
        list = OceanBIS.checklist("Abra"; size=5)
        @test OceanBIS.nrow(list) == 5
        @test all(!ismissing, list.scientificName)
        @test eltype(list.records) === Union{Missing,Int}
        # A checklist and a taxon lookup share a schema, so `records` is present in both
        # and simply missing where the endpoint does not supply it.
        @test Tables.columnnames(list) == Tables.columnnames(OceanBIS.taxon(141433))
    end
end

@testset "node, area, country, institute" begin
    with_mock() do
        nodes = OceanBIS.node()
        @test OceanBIS.nrow(nodes) > 10
        @test all(!ismissing, nodes.id)
        @test eltype(nodes.lat) === Union{Missing,Float64}

        areas = OceanBIS.area()
        @test OceanBIS.nrow(areas) > 100
        @test eltype(areas.id) === Union{Missing,Int}

        countries = OceanBIS.country()
        @test OceanBIS.nrow(countries) > 10
        @test all(!ismissing, countries.country)

        institutes = OceanBIS.institute("Abra alba")
        @test OceanBIS.nrow(institutes) > 1
        @test eltype(institutes.records) === Union{Missing,Int}
    end
end

@testset "dataset" begin
    with_mock() do
        ds = OceanBIS.dataset("Abra alba")
        @test OceanBIS.nrow(ds) > 1
        @test all(!ismissing, ds.license)
        @test haskey(ds, :intellectualrights)
        @test eltype(ds.published) === Union{Missing,DateTime}

        # A licence identifier is derived for every dataset, and the raw text is kept.
        for (id, raw) in zip(ds.license, ds.intellectualrights)
            @test id == OceanBIS.normalize_license(raw)
        end

        single = OceanBIS.dataset_by_id("8acba7e7-2e50-4490-8328-b78a30472508")
        @test OceanBIS.nrow(single) == 1
        @test single.license[1] == "CC-BY-4.0"
        @test !ismissing(single.citation[1])
        @test Tables.columnnames(single) == Tables.columnnames(ds)
    end
end

@testset "endpoints that need an identifier validate it" begin
    @test_throws OceanBIS.OBISValidationError OceanBIS.dataset_by_id("not-a-uuid")
    @test_throws OceanBIS.OBISValidationError OceanBIS.node("nope")
    @test_throws OceanBIS.OBISValidationError OceanBIS.metrics()
    @test_throws OceanBIS.OBISValidationError OceanBIS.metrics_downloads(
        "8acba7e7-2e50-4490-8328-b78a30472508"; groupby="space"
    )
    @test_throws OceanBIS.OBISValidationError OceanBIS.taxon("")
end

@testset "download metrics" begin
    with_mock() do
        id = "8acba7e7-2e50-4490-8328-b78a30472508"

        # `/metrics` answers with a bare object rather than the usual envelope, so it is
        # returned as plain Julia data instead of a table.
        yearly = OceanBIS.metrics(; datasetid=id)
        @test yearly isa Dict
        @test haskey(yearly, "downloads")
        @test !isempty(yearly["downloads"])

        totals = OceanBIS.metrics_downloads(id)
        @test totals["downloads"] > 0
        @test totals["records"] > 0

        # `groupby = "time"` swaps the aggregate for one entry per download event, which is
        # a different shape from the same endpoint.
        events = OceanBIS.metrics_downloads(
            id; startdate=Date(2018, 10, 1), enddate=Date(2018, 12, 1), groupby="time"
        )
        @test haskey(events, "downloads")
        @test all(e -> haskey(e, "time"), events["downloads"])
    end
end

@testset "page size is validated when it is configured, not when it is sent" begin
    # The API rejects an oversized page with HTTP 400 after the request has gone out; the
    # package refuses it at the point the mistake was made.
    old = OceanBIS.config().page_size
    try
        @test_throws OceanBIS.OBISValidationError OceanBIS.configure!(; page_size=0)
        @test_throws OceanBIS.OBISValidationError OceanBIS.configure!(;
            page_size=OceanBIS.MAX_PAGE_SIZE + 1
        )
        OceanBIS.configure!(; page_size=500)
        @test OceanBIS.config().page_size == 500
    finally
        OceanBIS.configure!(; page_size=old)
    end
end
