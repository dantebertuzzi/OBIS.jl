@testset "Tables.jl interface" begin
    with_mock() do
        t = OBIS.occurrence("Abra alba"; limit=3)

        @test Tables.istable(typeof(t))
        @test Tables.columnaccess(typeof(t))
        @test Tables.columns(t) === t
        @test Tables.rowcount(t) == 3

        sch = Tables.schema(t)
        @test length(sch.names) == OBIS.ncol(t)
        @test length(sch.types) == OBIS.ncol(t)

        # Access by name, by index, and through the interface all reach the same column.
        @test t.scientificName === Tables.getcolumn(t, :scientificName)
        @test t[:scientificName] === Tables.getcolumn(t, :scientificName)
        i = findfirst(==(:scientificName), Tables.columnnames(t))
        @test t[i] === Tables.getcolumn(t, :scientificName)

        # Row iteration is provided by Tables.jl on top of the column interface.
        rows = collect(Tables.rows(t))
        @test length(rows) == 3
        @test rows[1].id == t.id[1]

        # A generic consumer must be able to round-trip it.
        nt = Tables.columntable(t)
        @test nt.id == t.id
        @test length(Tables.rowtable(t)) == 3
    end
end

@testset "size, keys and display" begin
    with_mock() do
        t = OBIS.occurrence("Abra alba"; limit=3)
        @test size(t) == (3, OBIS.ncol(t))
        @test size(t, 1) == 3
        @test !isempty(t)
        @test :flags in keys(t)
        @test haskey(t, :flags)
        @test !haskey(t, :not_a_column)

        s = sprint(show, MIME"text/plain"(), t)
        @test occursin("OBISTable", s)
        @test occursin("accessed", s)
        @test occursin("occurrence", s)
        # The licence mix is part of the summary, because it decides what may be done
        # with the result.
        @test occursin("licenses:", s)
    end
end

@testset "extra fields are preserved, not dropped" begin
    with_mock() do
        t = OBIS.occurrence("Delphinidae"; limit=25, licenses=false, check_size=false)
        names = OBIS.extra_names(t)
        @test !isempty(names)
        @test issorted(names)

        # Nothing in `extra` duplicates a core column.
        core = Set(Tables.columnnames(t))
        @test isempty(intersect(Set(names), core))

        col = OBIS.extra_column(t, first(names))
        @test length(col) == OBIS.nrow(t)

        # An absent extra field yields a full column of missings, never an error.
        @test all(ismissing, OBIS.extra_column(t, :definitely_not_a_field))
    end
end

@testset "provenance travels with the result" begin
    with_mock() do
        t = OBIS.occurrence("Abra alba"; limit=3)
        m = OBIS.metadata(t)
        @test m.endpoint == "occurrence"
        @test m.accessed == today()
        @test m.total > OBIS.nrow(t)
        @test m.base_url == OBIS.config().base_url
        @test ("scientificname" => "Abra alba") in m.params
        @test m.package_version == string(OBIS.package_version())
    end
end

@testset "DataFrames extension" begin
    with_mock() do
        t = OBIS.occurrence("Delphinidae"; limit=25, licenses=false, check_size=false)

        df = DataFrame(t)
        @test DataFrames.nrow(df) == OBIS.nrow(t)
        @test :extra in propertynames(df)
        @test eltype(df.decimalLatitude) === Union{Missing,Float64}

        flat = DataFrame(t; flatten_extra=true)
        @test :extra ∉ propertynames(flat)
        @test DataFrames.nrow(flat) == OBIS.nrow(t)
        for nm in OBIS.extra_names(t)
            @test nm in propertynames(flat) || Symbol("extra_", nm) in propertynames(flat)
        end
    end
end

@testset "DataAPI generics work when DataFrames is loaded" begin
    with_mock() do
        t = OBIS.occurrence("Abra alba"; limit=3, licenses=false)
        # OBIS does not export these names, to avoid clashing with DataFrames. The
        # extension makes the DataFrames-provided generics work on an OBIS result.
        @test DataFrames.nrow(t) == 3
        @test DataFrames.ncol(t) == OBIS.ncol(t)
    end
end
