@testset "cache stores and replays responses" begin
    mktempdir() do dir
        cache = OBIS.QueryCache(dir)
        old = OBIS.config().cache
        try
            OBIS.configure!(; cache=cache)
            with_mock() do
                first = OBIS.occurrence("Abra alba"; limit=3)
                n_requests = length(REQUEST_LOG)
                @test n_requests >= 1

                # A repeat of the same query is served from disk.
                empty!(REQUEST_LOG)
                second = OBIS.occurrence("Abra alba"; limit=3)
                @test isempty(REQUEST_LOG)
                @test second.id == first.id
                @test second.decimalLatitude == first.decimalLatitude
            end
        finally
            OBIS.configure!(; cache=old)
        end
    end
end

@testset "cache entries record provenance" begin
    mktempdir() do dir
        cache = OBIS.QueryCache(dir)
        old = OBIS.config().cache
        try
            OBIS.configure!(; cache=cache)
            with_mock() do
                OBIS.occurrence("Abra alba"; limit=3, licenses=false)
            end

            entries = OBIS.cache_entries(cache)
            @test !isempty(entries)
            e = first(entries)
            @test haskey(e, "endpoint")
            @test haskey(e, "retrieved")
            @test haskey(e, "parameters")
            @test e["package_version"] == string(OBIS.package_version())
            @test e["bytes"] > 0

            # What is stored is the raw response, not the parsed table, so a re-run
            # reproduces the original data even if the package's parsing has changed.
            key = e["key"]
            body = read(joinpath(dir, key * ".json"), String)
            @test occursin("\"results\"", body)

            @test OBIS.clear_cache!(cache) == length(entries)
            @test isempty(OBIS.cache_entries(cache))
        finally
            OBIS.configure!(; cache=old)
        end
    end
end

@testset "a read-only cache refuses to reach the network" begin
    mktempdir() do dir
        old = OBIS.config().cache
        try
            OBIS.configure!(; cache=OBIS.QueryCache(dir))
            with_mock() do
                OBIS.occurrence("Abra alba"; limit=3, licenses=false)
            end

            # Reproducing an analysis must fail loudly if the data is not the data that was
            # cached, rather than quietly fetching today's version.
            OBIS.configure!(; cache=OBIS.QueryCache(dir; readonly=true))
            with_mock() do
                replayed = OBIS.occurrence("Abra alba"; limit=3, licenses=false)
                @test OBIS.nrow(replayed) == 3
                @test isempty(REQUEST_LOG)

                @test_throws OBIS.OBISAPIError OBIS.occurrence(
                    "Abra alba"; absence=:only, limit=3, licenses=false, check_size=false
                )
            end
        finally
            OBIS.configure!(; cache=old)
        end
    end
end

@testset "cache keys separate different queries" begin
    mktempdir() do dir
        cache = OBIS.QueryCache(dir)
        a = OBIS.build_params(; scientificname="Abra alba")
        b = OBIS.build_params(; scientificname="Abra alba", absence=:only)
        @test OBIS.cache_key("occurrence", a; base_url="https://api.obis.org/v3/") !=
            OBIS.cache_key("occurrence", b; base_url="https://api.obis.org/v3/")
        # The endpoint is part of the key, so two endpoints with identical filters do not
        # collide.
        @test OBIS.cache_key("occurrence", a; base_url="https://api.obis.org/v3/") !=
            OBIS.cache_key("checklist", a; base_url="https://api.obis.org/v3/")
    end
end

@testset "an unreadable cache entry is skipped, not fatal" begin
    mktempdir() do dir
        cache = OBIS.QueryCache(dir)
        # A truncated write — an interrupted process, a full disk — must not make the whole
        # cache unlistable, which would leave the user with no way to see or clear it.
        write(joinpath(dir, "broken.meta.json"), "{ not json")
        @test OBIS.cache_entries(cache) == Dict{String,Any}[]
    end
end
