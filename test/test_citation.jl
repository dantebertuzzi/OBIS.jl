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
