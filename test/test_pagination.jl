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
