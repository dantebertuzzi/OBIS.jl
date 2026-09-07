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

@testset "a value that cannot be represented becomes missing, never an error" begin
    # A single odd record must not fail a whole pull, so every coercion has a total
    # answer. All of these shapes occur: a null where a number is expected, a nested
    # object where a string is, a timestamp outside the representable range.
    @test OBIS.coerce_scalar(Int, nothing) === missing
    @test OBIS.coerce_scalar(Int, [1, 2]) === missing

    # An object or array under a string field is a structural surprise, not a value:
    # stringifying it would put raw JSON in a column that otherwise reads as prose.
    @test OBIS.coerce_scalar(String, JSON3.read("""{"a":1}""")) === missing
    @test OBIS.coerce_scalar(String, JSON3.read("""[1,2]""")) === missing

    # A scalar of the wrong type is still a value, so it is rendered rather than dropped.
    @test OBIS.coerce_scalar(String, 42) == "42"
    @test OBIS.coerce_scalar(String, true) == "true"

    # Far outside DateTime's range: `unix2datetime` throws, and `missing` is the honest
    # answer for a timestamp the package cannot represent.
    @test OBIS.coerce_epoch_ms(1e30) === missing

    @test OBIS.coerce_iso_datetime("not a date") === missing
    @test OBIS.coerce_iso_datetime("") === missing
end

@testset "node and institute names are lifted out of their objects" begin
    # `node` and `institute` arrive as arrays of objects; the schema keeps the names, since
    # a column of JSON objects is not something a user can group or filter on.
    v = JSON3.read("""[{"name":"Ocean Node","id":1},{"name":"Second"}]""")
    @test OBIS.coerce_named_list(v, :name) == ["Ocean Node", "Second"]

    # Anything that is not an object, or an object without the key, is skipped rather than
    # turned into a placeholder that would count as a node.
    mixed = JSON3.read("""["bare string",{"id":7},{"name":"Kept"}]""")
    @test OBIS.coerce_named_list(mixed, :name) == ["Kept"]

    # Absent is an empty list, not `missing`: the record has no nodes, which is a fact.
    @test OBIS.coerce_named_list(nothing, :name) == String[]
    @test OBIS.coerce_named_list(missing, :name) == String[]
end
