@testset "licence normalization" begin
    # Nine spellings of three licences appeared in a single query, so normalization works
    # on prose, not on codes.
    @test OBIS.normalize_license(
        "This work is licensed under a  Creative Commons Attribution (CC-BY) 4.0 License"
    ) == "CC-BY-4.0"
    @test OBIS.normalize_license(
        "This work is licensed under a  Creative Commons Attribution (CC-BY 4.0) License"
    ) == "CC-BY-4.0"
    @test OBIS.normalize_license(
        "This work is licensed under a  Creative Commons Attribution 4.0 International"
    ) == "CC-BY-4.0"

    # Non-commercial must win over attribution: every CC-BY-NC statement also says
    # "Attribution", so the looser test would swallow the stricter licence.
    @test OBIS.normalize_license(
        "This work is licensed under a  Creative Commons Attribution Non Commercial (CC-BY-NC) 4.0 License"
    ) == "CC-BY-NC-4.0"
    @test OBIS.normalize_license(
        "This work is licensed under a  Creative Commons Attribution Non Commercial (CC-BY-NC 4.0) License"
    ) == "CC-BY-NC-4.0"

    @test OBIS.normalize_license(
        "To the extent possible under law, the publisher has waived all rights to these " *
        "data and has dedicated them to the  Public Domain (CC0 1.0)",
    ) == "CC0-1.0"

    @test OBIS.normalize_license(
        "http://creativecommons.org/publicdomain/zero/1.0/legalcode"
    ) ==
        "CC0-1.0"
    @test OBIS.normalize_license(
        "http://creativecommons.org/licenses/by-nc/4.0/legalcode"
    ) ==
        "CC-BY-NC-4.0"
    @test OBIS.normalize_license("https://creativecommons.org/licenses/by/4.0/legalcode") ==
        "CC-BY-4.0"

    @test OBIS.normalize_license("Attribution-ShareAlike (CC BY-SA)") == "CC-BY-SA-4.0"

    # Values that are not licences must not be guessed into a permissive default. Both of
    # these appear in the live corpus.
    @test OBIS.normalize_license("Restricted") == "unknown"
    @test OBIS.normalize_license("Unrestricted") == "unknown"
    @test OBIS.normalize_license("") == "unknown"
    @test OBIS.normalize_license(nothing) == "unknown"
    @test OBIS.normalize_license(missing) == "unknown"
end

@testset "licence permissions" begin
    @test OBIS.permits_redistribution("CC0-1.0")
    @test OBIS.permits_redistribution("CC-BY-NC-4.0")
    @test !OBIS.permits_redistribution("unknown")

    @test OBIS.permits_commercial_use("CC0-1.0")
    @test OBIS.permits_commercial_use("CC-BY-4.0")
    @test !OBIS.permits_commercial_use("CC-BY-NC-4.0")
    @test !OBIS.permits_commercial_use("unknown")

    @test !OBIS.requires_attribution("CC0-1.0")
    @test OBIS.requires_attribution("CC-BY-4.0")
    @test OBIS.requires_attribution("CC-BY-NC-4.0")
    # An unidentifiable rights statement is not evidence that attribution was waived.
    @test OBIS.requires_attribution("unknown")

    @test OBIS.license_url("CC-BY-NC-4.0") ==
        "https://creativecommons.org/licenses/by-nc/4.0/"
    @test OBIS.license_url("unknown") === missing
end

@testset "licences ride along with the records" begin
    with_mock() do
        recs = OBIS.occurrence("Abra alba"; limit=3)

        # An occurrence record carries no rights of its own; these are joined from the
        # dataset, and the columns exist either way.
        @test haskey(recs, :license)
        @test haskey(recs, :license_url)
        @test haskey(recs, :dataset_citation)
        @test all(x -> !ismissing(x), recs.license)
        @test all(x -> x in OBIS.ACCEPTED_LICENSES || x == "unknown", recs.license)

        # Skipping the lookup must not change the table's shape.
        without = OBIS.occurrence("Abra alba"; limit=3, licenses=false)
        @test Tables.columnnames(without) == Tables.columnnames(recs)
        @test all(ismissing, without.license)
    end
end

@testset "licenses() summarizes what may be redistributed" begin
    with_mock() do
        recs = OBIS.occurrence("Abra alba"; limit=3)
        summary = OBIS.licenses(recs)

        @test summary isa OBIS.OBISTable
        @test Tables.columnnames(summary) == [
            :license,
            :datasets,
            :records,
            :permits_redistribution,
            :permits_commercial_use,
            :requires_attribution,
            :url,
        ]
        @test sum(summary.records) == OBIS.nrow(recs)
        @test all(n -> n >= 1, summary.datasets)
        @test eltype(summary.permits_commercial_use) === Bool
    end
end

@testset "citations carry the access date" begin
    with_mock() do
        recs = OBIS.occurrence("Abra alba"; limit=3)
        cites = OBIS.citations(recs)

        @test cites isa OBIS.OBISTable
        @test OBIS.nrow(cites) >= 1
        @test sum(cites.records) == OBIS.nrow(recs)

        # The access date comes from the request, because nothing in the data supplies it.
        @test all(d -> d == OBIS.metadata(recs).accessed, cites.accessed)
        for f in cites.formatted
            @test occursin("Accessed: $(OBIS.metadata(recs).accessed)", f)
            @test occursin("Ocean Biodiversity Information System", f)
        end

        text = OBIS.citations(recs; format=:text)
        @test text isa String
        @test occursin("Accessed:", text)

        bib = OBIS.citations(recs; format=:bibtex)
        @test occursin("@misc{obis_", bib)
        @test occursin("howpublished", bib)
        @test count("@misc{", bib) == OBIS.nrow(cites)

        @test_throws OBIS.OBISValidationError OBIS.citations(recs; format=:ris)
    end
end

@testset "BibTeX escaping" begin
    @test OBIS.bibtex_escape("Fish & Chips") == "Fish \\& Chips"
    @test OBIS.bibtex_escape("100% of {records}") == "100\\% of \\{records\\}"
    @test OBIS.bibtex_escape("a_b") == "a\\_b"

    # `~` and `^` are not escapes in BibTeX but commands, so a citation containing either
    # would compile to something other than the text the provider wrote.
    @test OBIS.bibtex_escape("10~20 m") == "10\\textasciitilde{}20 m"
    @test OBIS.bibtex_escape("m^2") == "m\\textasciicircum{}2"
end

@testset "the database citation" begin
    c = OBIS.obis_citation(;
        description="Distribution records of Abra alba",
        accessed=Date(2026, 9, 6),
        year=2026,
    )
    @test occursin("OBIS (2026)", c)
    @test occursin("Accessed: 2026-09-06", c)
    @test occursin("Intergovernmental Oceanographic Commission of UNESCO", c)
end

@testset "a dataset with no citation string is still identifiable" begin
    e = OBIS.CitationEntry(
        "8acba7e7-2e50-4490-8328-b78a30472508",
        "ICES Zoobenthos Community dataset",
        missing,                      # provider supplied no citation
        missing,
        "CC-BY-4.0",
        "https://creativecommons.org/licenses/by/4.0/",
        DateTime(2025, 9, 17),
        42,
        Date(2026, 9, 6),
    )
    formatted = OBIS.format_citation(e)
    @test occursin("ICES Zoobenthos Community dataset", formatted)
    @test occursin("2025", formatted)
    @test occursin("Accessed: 2026-09-06", formatted)
end

@testset "licenses() refuses a table that carries no rights" begin
    with_mock() do
        # The reference endpoints have no licence column, and a rights summary of one
        # would be an empty table rather than an answer. The error names the fix.
        err = try
            OBIS.licenses(OBIS.node())
            nothing
        catch e
            e
        end
        @test err isa OBIS.OBISValidationError
        @test occursin("OBIS.dataset", sprint(showerror, err))
    end
end

@testset "citations survive a failed bulk dataset lookup" begin
    # The bulk `dataset?…` form fetches metadata for a whole result in one request. When it
    # fails the citations are still worth having, so the package falls back to one request
    # per dataset rather than abandoning them.
    meta = with_mock() do
        OBIS.metadata(OBIS.occurrence("Abra alba"; limit=3, licenses=false))
    end
    id = "8acba7e7-2e50-4490-8328-b78a30472508"

    old = OBIS.TRANSPORT[]
    OBIS.TRANSPORT[] = function (url, headers, timeout)
        # Only the bulk form fails; `dataset/{id}` is served from the recorded fixture.
        occursin("dataset?", url) &&
            return (500, Dict{String,String}(), """{"error":"Invalid date format"}""")
        return mock_transport(url, headers, timeout)
    end
    try
        records = OBIS.fetch_dataset_records(meta, [id])
        @test haskey(records, id)
    finally
        OBIS.TRANSPORT[] = old
    end
end

@testset "citation metadata is skipped rather than fetched fifty times over" begin
    # Above fifty datasets the per-dataset fallback would be fifty-odd requests against a
    # service that publishes no quota. Incomplete entries are the lesser harm, and the
    # warning says how to retrieve the metadata deliberately.
    meta = with_mock() do
        OBIS.metadata(OBIS.occurrence("Abra alba"; limit=3, licenses=false))
    end
    ids = [string("00000000-0000-0000-0000-", lpad(i, 12, '0')) for i in 1:51]

    with_mock() do
        records = Dict{String,Any}()
        @test_logs (:warn, r"Citation metadata is unavailable") match_mode = :any begin
            records = OBIS.fetch_dataset_records(meta, ids)
        end
        @test !any(id -> haskey(records, id), ids)
        # None of the fifty-one was requested on its own.
        @test !any(u -> occursin("dataset/", u), REQUEST_LOG)
    end
end

@testset "a dataset whose metadata is unreachable still gets a citation" begin
    # Dropping the entry would under-report what a result was built from. The citation is
    # emitted with what is known — the identifier and the record count — and a licence of
    # "unknown" rather than a permissive guess.
    recs = with_mock() do
        OBIS.occurrence("Abra alba"; limit=3, licenses=false)
    end

    old = OBIS.TRANSPORT[]
    OBIS.TRANSPORT[] =
        (url, headers, timeout) ->
            (500, Dict{String,String}(), """{"error":"Invalid date format"}""")
    try
        cites = OBIS.citations(recs)
        @test OBIS.nrow(cites) >= 1
        @test all(==("unknown"), cites.license)
        @test all(ismissing, cites.title)
        # The accounting still adds up, which is what makes the table usable.
        @test sum(cites.records) == OBIS.nrow(recs)
    finally
        OBIS.TRANSPORT[] = old
    end
end

@testset "rights are looked up per dataset when a query has no filters" begin
    # A table assembled from ids alone — a resumed pull, a concatenation — has no query to
    # fetch rights in bulk with, so each dataset is fetched on its own.
    with_mock() do
        id = "8acba7e7-2e50-4490-8328-b78a30472508"
        info = OBIS.dataset_info(OBIS.QueryParams(), [id])
        @test haskey(info, id)
        @test info[id].license in OBIS.ACCEPTED_LICENSES
        @test any(u -> occursin("dataset/$(id)", u), REQUEST_LOG)
    end
end

@testset "rights lookup stops rather than issuing one request per dataset" begin
    # Fifty-one datasets would be fifty-one requests to fill in a column that is allowed to
    # be `missing`. The records are what the caller asked for; the rights are not worth
    # that much traffic, and the warning says how to get them deliberately.
    ids = [string("00000000-0000-0000-0000-", lpad(i, 12, '0')) for i in 1:51]
    with_mock() do
        info = nothing
        @test_logs (:warn, r"Rights information is missing") match_mode = :any begin
            info = OBIS.dataset_info(OBIS.QueryParams(), ids)
        end
        @test isempty(info)
        @test isempty(REQUEST_LOG)
    end
end

@testset "an unreachable dataset leaves the licence missing, not the records" begin
    # Rights are a nice-to-have joined onto the records; a failure to fetch them must not
    # cost the caller the data they actually asked for.
    old = OBIS.TRANSPORT[]
    OBIS.TRANSPORT[] = function (url, headers, timeout)
        occursin("dataset", url) &&
            return (500, Dict{String,String}(), """{"error":"Invalid date format"}""")
        return mock_transport(url, headers, timeout)
    end
    try
        # The individual lookups fail one by one and are swallowed.
        @test isempty(
            OBIS.dataset_info(
                OBIS.QueryParams(), ["8acba7e7-2e50-4490-8328-b78a30472508"]
            ),
        )

        # And the bulk lookup failing leaves the table intact, with a warning rather than
        # an exception.
        recs = nothing
        @test_logs (:warn, r"Could not retrieve dataset rights") match_mode = :any begin
            recs = OBIS.occurrence("Abra alba"; limit=3)
        end
        @test OBIS.nrow(recs) == 3
        @test all(ismissing, recs.license)
    finally
        OBIS.TRANSPORT[] = old
    end
end
