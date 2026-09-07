@testset "pagination advances by cursor" begin
    with_mock() do
        pages = OBIS.occurrence_pages("Abra alba"; page_size=3)

        # Nothing is fetched until iteration starts.
        @test OBIS.cursor(pages) === nothing
        @test isempty(REQUEST_LOG)

        first_page, state = iterate(pages)
        @test OBIS.nrow(first_page) == 3
        @test OBIS.cursor(pages) == first_page.id[end]
        @test OBIS.fetched(pages) == 3
        @test OBIS.expected(pages) > 3
        @test length(REQUEST_LOG) == 1

        second_page, _ = iterate(pages, state)
        @test OBIS.nrow(second_page) == 3
        @test OBIS.fetched(pages) == 6

        # The cursor is exclusive, so pages must not overlap.
        @test isempty(intersect(Set(first_page.id), Set(second_page.id)))

        # Every page has the same schema, so pages can be concatenated or streamed
        # interchangeably.
        @test Tables.columnnames(first_page) == Tables.columnnames(second_page)
    end
end

@testset "a pull resumes from a saved cursor" begin
    with_mock() do
        pages = OBIS.occurrence_pages("Abra alba"; page_size=3)
        page1, _ = iterate(pages)
        checkpoint = OBIS.cursor(pages)

        # The cursor is a plain UUID: the whole of the pagination state fits in a string,
        # which is what makes resuming in a later session possible.
        @test checkpoint isa String
        @test length(checkpoint) == 36

        resumed = OBIS.occurrence_pages("Abra alba"; page_size=3, after=checkpoint)
        page2, _ = iterate(resumed)
        @test isempty(intersect(Set(page1.id), Set(page2.id)))
    end
end

@testset "concatenation preserves schema and provenance" begin
    with_mock() do
        pages = OBIS.occurrence_pages("Abra alba"; page_size=3)
        p1, st = iterate(pages)
        p2, _ = iterate(pages, st)

        meta = OBIS.metadata(p1)
        joined = OBIS.concat_tables([p1, p2], meta)
        @test OBIS.nrow(joined) == 6
        @test Tables.columnnames(joined) == Tables.columnnames(p1)
        @test eltype(joined.decimalLatitude) === Union{Missing,Float64}
        @test joined.id == vcat(p1.id, p2.id)
    end
end

@testset "limit stops the pull" begin
    with_mock() do
        recs = OBIS.occurrence("Abra alba"; limit=3, licenses=false)
        @test OBIS.nrow(recs) == 3
        # A limited pull must not request more pages than it needs.
        @test length(REQUEST_LOG) == 1
    end
end

@testset "take_rows keeps the schema" begin
    with_mock() do
        recs = OBIS.occurrence("Abra alba"; limit=3, licenses=false)
        two = OBIS.take_rows(recs, 2)
        @test OBIS.nrow(two) == 2
        @test Tables.columnnames(two) == Tables.columnnames(recs)
        @test OBIS.metadata(two).accessed == OBIS.metadata(recs).accessed
    end
end

@testset "progress goes to stderr, not to stdout" begin
    # A long pull needs to say how far it has got, but stdout belongs to the caller: a
    # piped `julia script.jl > records.csv` must not have a progress line in it.
    with_mock() do
        out = mktemp() do path, io
            redirect_stderr(io) do
                pages = OBIS.occurrence_pages("Abra alba"; page_size=3, progress=true)
                iterate(pages)
                # A caller-imposed stop needs a closing line of its own; an iterator run to
                # exhaustion prints one itself.
                OBIS.occurrence("Abra alba"; limit=3, licenses=false, progress=true)
            end
            flush(io)
            read(path, String)
        end
        @test occursin("OBIS:", out)
        @test occursin("%", out)
        @test occursin("records retrieved", out)
    end
end

@testset "a page without ids stops instead of spinning" begin
    # The cursor is the last `id` on the page, so a response without one cannot advance it
    # and re-requesting would return the same page forever. `fields` cannot exclude `id` —
    # the validator refuses — but the loop must not be able to spin regardless.
    old = OBIS.TRANSPORT[]
    OBIS.TRANSPORT[] =
        (url, headers, timeout) -> (
            200,
            Dict{String,String}(),
            """{"total":2,"results":[{"scientificName":"Abra alba"}]}""",
        )
    try
        pages = OBIS.occurrence_pages("Abra alba"; page_size=1)
        page, state = @test_logs (:warn, r"cursor cannot advance") iterate(pages)
        @test OBIS.nrow(page) == 1
        @test state === :done

        # The records already fetched are still handed over; only the pull ends.
        @test iterate(pages, state) === nothing
    finally
        OBIS.TRANSPORT[] = old
    end
end

@testset "an exhausted pull ends without a limit to stop it" begin
    # A pull with no `limit` runs until the API stops returning records. The empty page is
    # the only signal that it is over, so it must end the loop rather than being treated
    # as a failure or as a page of zero records to append.
    old = OBIS.TRANSPORT[]
    old_size = OBIS.config().page_size
    served = Ref(0)
    OBIS.TRANSPORT[] = function (url, headers, timeout)
        served[] += 1
        served[] == 1 && return mock_transport(url, headers, timeout)
        return (200, Dict{String,String}(), """{"total":3,"results":[]}""")
    end
    try
        OBIS.configure!(; page_size=3)
        recs = OBIS.occurrence("Abra alba"; check_size=false, licenses=false)
        @test OBIS.nrow(recs) == 3
        @test served[] == 2
    finally
        OBIS.TRANSPORT[] = old
        OBIS.configure!(; page_size=old_size)
    end
end
