@testset "occurrence returns a stable typed table" begin
    with_mock() do
        recs = OceanBIS.occurrence("Abra alba"; limit=3)

        @test recs isa OceanBIS.OBISTable
        @test OceanBIS.nrow(recs) == 3
        @test Tables.istable(typeof(recs))
        @test Tables.columnaccess(typeof(recs))

        # Every core column exists whatever the query returned.
        for spec in OceanBIS.OCCURRENCE_SCHEMA
            @test haskey(recs, spec.name)
        end
        @test haskey(recs, :extra)

        # Coordinates are Float64 even though some records encode them as integers.
        @test eltype(recs.decimalLatitude) === Union{Missing,Float64}
        @test eltype(recs.decimalLongitude) === Union{Missing,Float64}
        @test all(x -> ismissing(x) || x isa Float64, recs.decimalLatitude)

        @test eltype(recs.flags) === Set{String}
        @test eltype(recs.date_start) === Union{Missing,DateTime}
        @test eltype(recs.aphiaID) === Union{Missing,Int}
        @test eltype(recs.dropped) === Union{Missing,Bool}

        @test all(!ismissing, recs.id)
        @test all(!ismissing, recs.dataset_id)
    end
end

@testset "the schema does not change between queries" begin
    with_mock() do
        a = OceanBIS.occurrence("Abra alba"; limit=3)
        b = OceanBIS.occurrence(
            "Abra alba"; absence=:only, limit=3, licenses=false, check_size=false
        )
        c = OceanBIS.occurrence("Delphinidae"; limit=25, licenses=false, check_size=false)

        # Three queries against different data, one column set. This is the property the
        # package exists to provide: a record set from a different taxon, with a different
        # set of Darwin Core fields populated, still produces the same table shape.
        @test Tables.columnnames(a) == Tables.columnnames(b)
        @test Tables.columnnames(a) == Tables.columnnames(c)
        @test Tables.schema(a).types == Tables.schema(c).types

        # The Delphinidae fixture carries fields the Abra alba one does not; they are kept,
        # in `extra`, rather than being dropped or added as columns.
        @test !isempty(OceanBIS.extra_names(c))
        @test length(OceanBIS.extra_column(c, first(OceanBIS.extra_names(c)))) ==
            OceanBIS.nrow(c)
    end
end

@testset "empty results keep the full schema" begin
    with_mock() do
        empty = OceanBIS.occurrence(
            "Abra alba";
            geometry="POLYGON ((0 0, 0 0.001, 0.001 0.001, 0.001 0, 0 0))",
            limit=3,
            licenses=false,
            check_size=false,
        )
        @test OceanBIS.nrow(empty) == 0
        @test Tables.columnnames(empty) ==
            Tables.columnnames(OceanBIS.occurrence("Abra alba"; limit=3))
    end
end

@testset "absence and dropped records are reachable" begin
    with_mock() do
        absences = OceanBIS.occurrence(
            "Abra alba"; absence=:only, limit=3, licenses=false, check_size=false
        )
        @test OceanBIS.nrow(absences) == 3
        @test all(x -> x === true, absences.absence)

        dropped = OceanBIS.occurrence(
            "Abra alba"; dropped=:only, limit=3, licenses=false, check_size=false
        )
        @test OceanBIS.nrow(dropped) == 3
        @test all(x -> x === true, dropped.dropped)

        # These records exist and are excluded from a default query. That is the whole
        # point of exposing the selection.
        default = OceanBIS.occurrence("Abra alba"; limit=3)
        @test all(x -> x === false, default.absence)
        @test all(x -> x === false, default.dropped)
    end
end

@testset "flag filtering round-trips" begin
    with_mock() do
        # Lower case is normalized; without that the API would return zero records and
        # report no error.
        onland = OceanBIS.occurrence(
            "Abra alba"; flags="on_land", limit=3, licenses=false, check_size=false
        )
        @test OceanBIS.nrow(onland) == 3
        @test all(r -> "ON_LAND" in r, onland.flags)
    end
end

@testset "an unmatched name is an error, not an empty result" begin
    with_mock() do
        # The API answers with HTTP 200 and `error: NAME_NOT_FOUND`, which would otherwise
        # read as "this taxon has no records".
        @test_throws OceanBIS.OBISNameNotFoundError OceanBIS.occurrence(
            "Notaspecies atallxyz"; limit=3, check_size=false
        )
    end
end

@testset "oversized pages are rejected before the request" begin
    with_mock() do
        @test_throws OceanBIS.OBISValidationError OceanBIS.occurrence_pages(
            "Abra alba"; page_size=20_000
        )
    end
end

@testset "single record lookup" begin
    with_mock() do
        rec = OceanBIS.occurrence_by_id("0001837f-afc5-45a9-a76d-b63ab73fb93c")
        @test OceanBIS.nrow(rec) == 1
        @test rec.scientificName[1] == "Abra alba"
        @test rec.decimalLatitude[1] isa Float64
    end
end
