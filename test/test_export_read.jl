# Reading a bulk export into the canonical schema.
#
# The fixtures are five-row slices of two real per-dataset exports, cut from the files with
# their schema intact — 622 columns, the provider's terms nested under `source` and the
# pipeline's under `interpreted`. A hand-written Parquet would have flattened away the one
# thing the reader exists to cope with.

const EXPORT_DROPPED = joinpath(FIXTURE_DIR, "export_dropped.parquet")
const EXPORT_ABSENCE = joinpath(FIXTURE_DIR, "export_absence.parquet")

@testset "an export reads into the same table an API query returns" begin
    # The point of the reader: after it, the two access routes are interchangeable in
    # everything downstream. Same columns, same order, same element types.
    recs = with_mock() do
        OBISClient.occurrence("Abra alba"; limit=3, licenses=false)
    end
    export_table = OBISClient.read_export(EXPORT_DROPPED; licenses=false)

    @test Tables.columnnames(export_table) == Tables.columnnames(recs)
    for name in Tables.columnnames(recs)
        @test eltype(Tables.getcolumn(export_table, name)) ==
            eltype(Tables.getcolumn(recs, name))
    end

    # And the values arrive coerced, not as whatever Parquet held.
    @test all(x -> x isa Float64, skipmissing(export_table.decimalLatitude))
    @test eltype(export_table.flags) === Set{String}
    @test all(f -> f isa Set{String}, export_table.flags)
    @test export_table.date_start[1] isa DateTime
    @test Date(1700) < Date(export_table.date_start[1]) < Date(2100)
end

@testset "absence and dropped default to the API's view" begin
    # The export contains both, so a plain read would quietly mix them into an ordinary
    # count. Defaulting to `:exclude` makes the same query mean the same thing on both
    # routes; the file fixtures hold three of each against two ordinary records.
    @test OBISClient.nrow(OBISClient.read_export(EXPORT_DROPPED; licenses=false)) == 2
    @test OBISClient.nrow(OBISClient.read_export(EXPORT_ABSENCE; licenses=false)) == 2

    only_dropped = OBISClient.read_export(EXPORT_DROPPED; dropped=:only, licenses=false)
    @test OBISClient.nrow(only_dropped) == 3
    @test all(only_dropped.dropped)

    only_absence = OBISClient.read_export(EXPORT_ABSENCE; absence=:only, licenses=false)
    @test OBISClient.nrow(only_absence) == 3
    @test all(only_absence.absence)

    both = OBISClient.read_export(EXPORT_ABSENCE; absence=:include, licenses=false)
    @test OBISClient.nrow(both) == 5
    @test count(both.absence) == 3

    @test_throws OBISClient.OBISValidationError OBISClient.read_export(
        EXPORT_ABSENCE; absence=:maybe, licenses=false
    )
end

@testset "rights are joined onto export rows" begin
    # An occurrence row carries no rights in the export either — `interpreted.license` is
    # declared in the schema and was empty in every file examined — so they come from the
    # licence table published alongside it. This is what makes `licenses` and `citations`
    # work on the bulk route.
    with_mock() do
        table = OBISClient.read_export(EXPORT_DROPPED)
        @test all(==("CC-BY-4.0"), table.license)
        # The URL is the one the licence table publishes, not the canonical form: the table
        # is the provider's statement, and normalizing it away would lose what was said.
        @test all(
            u -> u == "http://creativecommons.org/licenses/by/4.0/legalcode",
            table.license_url,
        )

        # This dataset published no citation text, and the column says so rather than the
        # read failing or inventing one; the other fixture's dataset did publish one.
        @test all(ismissing, table.dataset_citation)
        other = OBISClient.read_export(EXPORT_ABSENCE)
        @test all(!ismissing, other.dataset_citation)
        @test occursin("Posidonia oceanica", other.dataset_citation[1])

        summary = OBISClient.licenses(table)
        @test OBISClient.nrow(summary) == 1
        @test summary.license == ["CC-BY-4.0"]
        @test sum(summary.records) == OBISClient.nrow(table)
        @test all(summary.permits_redistribution)

        # A licence table can be passed in, so reading many files costs one fetch.
        reused = OBISClient.export_licenses()
        @test OBISClient.read_export(EXPORT_DROPPED; licenses=reused).license ==
            table.license

        @test all(ismissing, OBISClient.read_export(EXPORT_DROPPED; licenses=false).license)
    end
end

@testset "several exports read as one table" begin
    # `download_exports` returns a vector of paths, so this is the shape that composes.
    with_mock() do
        table = OBISClient.read_export([EXPORT_DROPPED, EXPORT_ABSENCE])
        @test OBISClient.nrow(table) == 4          # two ordinary records from each file
        @test length(unique(table.dataset_id)) == 2

        # Both datasets are CC-BY here, but the summary is still per licence rather than a
        # single verdict, and it accounts for every record.
        @test sum(OBISClient.licenses(table).records) == OBISClient.nrow(table)
    end
end

@testset "export provenance is the file's date, not today" begin
    # The records are as old as the export that carried them. A citation built from this
    # table has to say when the data was obtained, and that is when the file was written.
    table = OBISClient.read_export(EXPORT_DROPPED; licenses=false)
    meta = OBISClient.metadata(table)
    @test meta.endpoint == "export/occurrence"
    @test meta.accessed == Date(unix2datetime(mtime(EXPORT_DROPPED)))
    @test meta.base_url == OBISClient.config().export_url
    @test Dict(meta.params)["files"] == "export_dropped.parquet"
    @test Dict(meta.params)["dropped"] == "exclude"
end

@testset "the provider's own terms are opt-in" begin
    # `source` has 188 fields. Reading them costs more than the whole core schema does, so
    # the caller asks for them rather than paying by default.
    plain = OBISClient.read_export(EXPORT_DROPPED; licenses=false)
    @test all(isempty, plain.extra)

    full = OBISClient.read_export(EXPORT_DROPPED; licenses=false, source_terms=true)
    @test any(!isempty, full.extra)
    # The provider's name before the taxonomy match is a column of its own, so it is not
    # duplicated into `extra`.
    @test !any(d -> haskey(d, :scientificName), full.extra)
    @test !ismissing(full.originalScientificName[1])
end

@testset "limit stops the read rather than the table" begin
    @test OBISClient.nrow(
        OBISClient.read_export(EXPORT_ABSENCE; absence=:include, licenses=false, limit=2)
    ) == 2
end

@testset "a missing file is an error that names it" begin
    err = try
        OBISClient.read_export(joinpath(FIXTURE_DIR, "no_such_export.parquet"))
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("no_such_export.parquet", sprint(showerror, err))

    @test_throws ArgumentError OBISClient.read_export(String[])
end

@testset "the SELECT list is built from the schema" begin
    # Built rather than written out, so a column added to the schema is read from the
    # export without a second list to remember.
    selects = [OBISClient.export_select(spec) for spec in OBISClient.OCCURRENCE_SCHEMA]
    @test length(selects) == length(OBISClient.OCCURRENCE_SCHEMA)

    # The four that sit at the top level of the file rather than under `interpreted`.
    @test OBISClient.export_select(OBISClient.OCCURRENCE_SCHEMA[1]) == "_id AS \"id\""
    @test any(s -> s == "flags AS \"flags\"", selects)
    @test any(s -> s == "absence AS \"absence\"", selects)

    # The pipeline's AphiaID is lower case in the export.
    @test any(s -> s == "interpreted.aphiaid AS \"aphiaID\"", selects)

    # The columns the export does not carry read as NULL and come out `missing`.
    @test any(s -> s == "NULL AS \"freshwater\"", selects)
    @test any(s -> s == "NULL AS \"terrestrial\"", selects)

    # Everything else is the pipeline's own value, which is what the API serves.
    @test any(s -> s == "interpreted.\"decimalLatitude\" AS \"decimalLatitude\"", selects)
end
