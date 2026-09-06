@testset "numeric coercion" begin
    # JSON drops a zero fractional part, so the same field arrives as Int or Float across
    # records. Coordinates in particular must always come out Float64.
    @test OBIS.coerce_scalar(Float64, 3) === 3.0
    @test OBIS.coerce_scalar(Float64, 3.5) === 3.5
    @test OBIS.coerce_scalar(Float64, "3.5") === 3.5
    @test OBIS.coerce_scalar(Float64, "not a number") === missing
    @test OBIS.coerce_scalar(Float64, nothing) === missing

    @test OBIS.coerce_scalar(Int, 7) === 7
    @test OBIS.coerce_scalar(Int, 7.0) === 7
    @test OBIS.coerce_scalar(Int, 7.5) === missing
    @test OBIS.coerce_scalar(Int, "7") === 7

    @test OBIS.coerce_scalar(Bool, true) === true
    @test OBIS.coerce_scalar(Bool, "true") === true
    @test OBIS.coerce_scalar(Bool, "false") === false
    @test OBIS.coerce_scalar(Bool, 1) === true
    @test OBIS.coerce_scalar(Bool, "maybe") === missing
end

@testset "timestamps are milliseconds" begin
    # date_start and friends are Unix milliseconds. Treating them as seconds would place
    # every record about fifty thousand years in the future.
    @test OBIS.coerce_epoch_ms(1432857600000) == DateTime(2015, 5, 29)
    @test OBIS.coerce_epoch_ms("1432857600000") == DateTime(2015, 5, 29)
    @test OBIS.coerce_epoch_ms(nothing) === missing
    @test OBIS.coerce_epoch_ms("nonsense") === missing

    @test OBIS.coerce_iso_datetime("2025-09-17T10:21:41.000Z") ==
        DateTime(2025, 9, 17, 10, 21, 41)
    @test OBIS.coerce_iso_datetime("2025-05-13 16:20:21") ==
        DateTime(2025, 5, 13, 16, 20, 21)
    @test OBIS.coerce_iso_datetime("2025-09-17") == DateTime(2025, 9, 17)
    @test OBIS.coerce_iso_datetime(nothing) === missing
end

@testset "flags parse to a set" begin
    # The API sends an array; downloads use a comma-separated string. Both must work, and
    # the result is a set because flags are unordered and unique.
    @test OBIS.coerce_flagset(["ON_LAND", "NO_DEPTH"]) == Set(["ON_LAND", "NO_DEPTH"])
    @test OBIS.coerce_flagset("ON_LAND,NO_DEPTH") == Set(["ON_LAND", "NO_DEPTH"])
    @test OBIS.coerce_flagset("on_land") == Set(["ON_LAND"])

    # No flags is an empty set, never `missing`: it is a fact about the record, so set
    # membership works without missing-handling.
    @test OBIS.coerce_flagset(nothing) == Set{String}()
    @test OBIS.coerce_flagset([]) == Set{String}()
    @test !("ON_LAND" in OBIS.coerce_flagset(nothing))
end

@testset "column types are concrete" begin
    for spec in OBIS.OCCURRENCE_SCHEMA
        T = OBIS.column_type(spec)
        if spec.kind === :flagset
            @test T === Set{String}
        elseif spec.kind in (:strlist, :node_names, :institute_names)
            @test T === Vector{String}
        else
            @test T === Union{Missing,spec.type}
            @test isconcretetype(spec.type)
        end
    end
end
