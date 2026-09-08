@testset "flag normalization" begin
    @test OceanBIS.normalize_flag("on_land") == "ON_LAND"
    @test OceanBIS.normalize_flag(:NO_DEPTH) == "NO_DEPTH"
    @test OceanBIS.normalize_flags(["on_land", :no_match]) == ["ON_LAND", "NO_MATCH"]
    @test OceanBIS.normalize_flags("ON_LAND,no_depth") == ["ON_LAND", "NO_DEPTH"]
    @test OceanBIS.normalize_flags("ON_LAND, NO_DEPTH ") == ["ON_LAND", "NO_DEPTH"]

    # An unknown flag is passed through, because OBIS adds checks over time, but it warns:
    # the API would accept it silently and return nothing.
    @test (@test_logs (:warn,) OceanBIS.normalize_flag("NOT_A_REAL_FLAG")) ==
        "NOT_A_REAL_FLAG"

    @test OceanBIS.drops_record("NO_MATCH")
    @test OceanBIS.drops_record("no_coord")
    @test !OceanBIS.drops_record("ON_LAND")

    @test_throws OceanBIS.OBISValidationError OceanBIS.normalize_flag("")
end

@testset "record selection is tri-state" begin
    @test OceanBIS.selection_value(:absence, nothing) === nothing
    @test OceanBIS.selection_value(:absence, :exclude) === nothing
    @test OceanBIS.selection_value(:absence, :include) == "include"
    @test OceanBIS.selection_value(:absence, :only) == "true"
    # `true`/`false` are a natural guess and map to the nearest meaning.
    @test OceanBIS.selection_value(:absence, true) == "true"
    @test OceanBIS.selection_value(:absence, false) === nothing
    @test_throws OceanBIS.OBISValidationError OceanBIS.selection_value(:absence, :yes)
end

@testset "geometry validation" begin
    @test OceanBIS.validate_geometry(
        "POLYGON ((2.3 51.8, 2.3 51.6, 2.6 51.6, 2.3 51.8))"
    ) isa
        String
    @test OceanBIS.validate_geometry("point(3 51)") isa String

    # The API answers invalid WKT with HTTP 200 and an empty result set, so these must be
    # caught locally or they become a silent "no records here".
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_geometry("NOTWKT")
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_geometry(
        "POLYGON ((1 2, 3 4)"
    )
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_geometry("")
end

@testset "date handling" begin
    @test OceanBIS.format_date(:startdate, Date(2015, 5, 29)) == "2015-05-29"
    @test OceanBIS.format_date(:startdate, DateTime(2015, 5, 29, 12)) == "2015-05-29"
    @test OceanBIS.format_date(:startdate, "2015-05-29") == "2015-05-29"
    @test_throws OceanBIS.OBISValidationError OceanBIS.format_date(:startdate, "29/05/2015")
    @test_throws OceanBIS.OBISValidationError OceanBIS.format_date(:startdate, "2015-13-01")
    @test_throws OceanBIS.OBISValidationError OceanBIS.format_date(:startdate, 2015)
end

@testset "depth and identifier validation" begin
    @test OceanBIS.validate_depth(:startdepth, 10) == 10
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_depth(:startdepth, 50_000)
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_depth(:startdepth, "deep")

    @test OceanBIS.validate_uuid(:datasetid, "8acba7e7-2e50-4490-8328-b78a30472508") ==
        "8acba7e7-2e50-4490-8328-b78a30472508"
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_uuid(
        :datasetid, "not-a-uuid"
    )

    @test OceanBIS.validate_size(1000) == 1000
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_size(20_000)
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_size(0)
end

@testset "fields validation" begin
    # `id` is the pagination cursor and is added even when the caller omits it.
    @test OceanBIS.validate_fields(["scientificName"]) == "id,scientificName"
    @test OceanBIS.validate_fields("id,scientificName") == "id,scientificName"
    # `flags` is silently dropped by the API when requested through `fields`.
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_fields(["id", "flags"])
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_fields(String[])
end

@testset "parameter assembly" begin
    q = OceanBIS.build_params(;
        scientificname="Abra alba",
        startdate=Date(2010, 1, 1),
        enddate=Date(2020, 1, 1),
        absence=:only,
        flags="on_land",
    )
    d = Dict(OceanBIS.pairs(q))
    @test d["scientificname"] == "Abra alba"
    @test d["startdate"] == "2010-01-01"
    @test d["absence"] == "true"
    @test d["flags"] == "ON_LAND"
    @test !haskey(d, "dropped")     # unset selections are omitted, not sent as "false"

    # `aphiaid` is an alias; the wire name is `taxonid`.
    q2 = OceanBIS.build_params(; aphiaid=141433)
    @test Dict(OceanBIS.pairs(q2))["taxonid"] == "141433"
    @test_throws OceanBIS.OBISValidationError OceanBIS.build_params(; aphiaid=1, taxonid=2)

    # Contradictory ranges are caught before the request.
    @test_throws OceanBIS.OBISValidationError OceanBIS.build_params(;
        startdate=Date(2020, 1, 1), enddate=Date(2010, 1, 1)
    )
    @test_throws OceanBIS.OBISValidationError OceanBIS.build_params(;
        startdepth=100, enddepth=10
    )
    @test_throws OceanBIS.OBISValidationError OceanBIS.build_params(; scientificname="   ")
end

@testset "cache keys are order independent" begin
    a = OceanBIS.build_params(; scientificname="Abra alba", startdepth=5)
    b = OceanBIS.build_params(; startdepth=5, scientificname="Abra alba")
    ka = OceanBIS.cache_key("occurrence", a; base_url="https://api.obis.org/v3/")
    kb = OceanBIS.cache_key("occurrence", b; base_url="https://api.obis.org/v3/")
    @test ka == kb

    c = OceanBIS.build_params(; scientificname="Abra alba", startdepth=6)
    @test ka != OceanBIS.cache_key("occurrence", c; base_url="https://api.obis.org/v3/")
end

@testset "a page size must be a whole number of records" begin
    # `size = 2.5` is a mistake, not a value to round: the API would take the truncation
    # silently and the caller would never learn which one they got.
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_size(2.5)
    @test OceanBIS.validate_size(10.0) == 10
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_size(0)
    @test_throws OceanBIS.OBISValidationError OceanBIS.validate_size(
        OceanBIS.MAX_PAGE_SIZE + 1
    )
end

@testset "tags accept one value or several" begin
    @test Dict(OceanBIS.pairs(OceanBIS.build_params(; tags="marine")))["tags"] == "marine"
    @test Dict(OceanBIS.pairs(OceanBIS.build_params(; tags=["marine", "benthic"])))["tags"] ==
        "marine,benthic"
end

@testset "a validation error names the value that was wrong" begin
    # The point of validating locally is that the message can say more than the API's
    # would; repeating the offending value back is most of that.
    msg = sprint(showerror, OceanBIS.OBISValidationError(:size, 20_000, "Too large."))
    @test occursin("size", msg)
    @test occursin("20000", msg)
    @test occursin("Too large.", msg)

    # Some checks are about an absent value rather than a wrong one, and those say so
    # without an empty parenthesis.
    absent = sprint(
        showerror, OceanBIS.OBISValidationError(:datasetid, nothing, "Required.")
    )
    @test !occursin("(got", absent)
end
