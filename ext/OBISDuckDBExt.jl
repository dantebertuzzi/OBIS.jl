# Reading the bulk export into the canonical schema.
#
# The export route is the one OBIS recommends for volume, but its files carry a different
# table from the API's: 622 columns, the provider's terms nested under `source` and the
# pipeline's under `interpreted`. Left at that, choosing the recommended route costs a user
# the schema, the types, and the rights and citation machinery this package exists for.
#
# DuckDB rather than Parquet2.jl because Parquet2 cannot read these files at all — nested
# struct columns are unsupported, and everything the canonical schema needs lives inside
# one. Being a weak dependency means the ~52 MiB DuckDB artifact is paid for only by users
# who take the export route.

module OBISDuckDBExt

using Dates
using DuckDB
using OBIS
using Tables

using OBIS:
    CONFIG,
    FieldSpec,
    OBISTable,
    OCCURRENCE_SCHEMA,
    QueryMeta,
    QueryParams,
    coerce_field,
    column_type,
    export_select,
    package_version,
    selection_value,
    sorted_pairs

"Single-quote a path for a SQL literal."
sql_string(s::AbstractString) = string('\'', replace(String(s), "'" => "''"), '\'')

"""
    file_list(path) -> (sql, paths)

The `read_parquet` argument and the files behind it.

A vector is passed through as a SQL list so that many dataset exports read as one table,
which is the shape `download_exports` returns.
"""
function file_list(path::AbstractString)
    isfile(path) || throw(
        ArgumentError(
            "No export file at $(path). `read_export` takes a path, or a vector of them " *
            "as returned by `OBIS.download_exports`.",
        ),
    )
    return sql_string(path), [String(path)]
end

function file_list(paths::AbstractVector{<:AbstractString})
    isempty(paths) && throw(ArgumentError("`read_export` was given no files."))
    for p in paths
        isfile(p) || throw(ArgumentError("No export file at $(p)."))
    end
    return string('[', join(sql_string.(paths), ", "), ']'), String.(paths)
end

"""
    selection_predicate(column, sel) -> Union{Nothing,String}

The `WHERE` term for one tri-state selection, or `nothing` when it restricts nothing.

`IS NOT TRUE` rather than `= false`: the column is nullable, and a null there means the same
as false — not an absence record — but `= false` would drop the row.
"""
function selection_predicate(column::AbstractString, sel)
    value = selection_value(Symbol(column), sel)
    value === nothing && return string(column, " IS NOT TRUE")
    value == "true" && return string(column, " IS TRUE")
    return nothing        # :include — both kinds wanted
end

function read_export_impl(
    path;
    absence=:exclude,
    dropped=:exclude,
    licenses=true,
    limit::Union{Nothing,Integer}=nothing,
    source_terms::Bool=false,
)
    from, files = file_list(path)

    selects = String[export_select(spec) for spec in OCCURRENCE_SCHEMA]
    source_terms && push!(selects, "source AS \"__source\"")

    wheres = filter(
        !isnothing,
        [
            selection_predicate("absence", absence),
            selection_predicate("dropped", dropped),
        ],
    )

    sql = string(
        "SELECT ",
        join(selects, ", "),
        " FROM read_parquet(",
        from,
        ")",
        isempty(wheres) ? "" : string(" WHERE ", join(wheres, " AND ")),
        limit === nothing ? "" : string(" LIMIT ", Int(limit)),
    )

    con = DBInterface.connect(DuckDB.DB)
    raw = try
        Tables.columntable(DBInterface.execute(con, sql))
    finally
        DBInterface.close!(con)
    end

    return build_export_table(raw, files, absence, dropped, licenses, source_terms)
end

"""
    build_export_table(raw, files, absence, dropped, licenses, source_terms) -> OBISTable

Coerce the columns DuckDB returned into the canonical schema.

Every value goes through `coerce_field`, the same function the API path uses, so the two
routes cannot drift in how they read a value: a whole-valued float is still an `Int`, a
timestamp is still milliseconds, and an absent value is still `missing`.
"""
function build_export_table(raw, files, absence, dropped, licenses, source_terms::Bool)
    n = isempty(raw) ? 0 : length(first(raw))

    names = Symbol[spec.name for spec in OCCURRENCE_SCHEMA]
    columns = AbstractVector[]
    for spec in OCCURRENCE_SCHEMA
        values = getproperty(raw, spec.name)
        column = Vector{column_type(spec)}(undef, n)
        for i in 1:n
            column[i] = coerce_field(spec, values[i])
        end
        push!(columns, column)
    end

    extra = Vector{Dict{Symbol,Any}}(undef, n)
    if source_terms
        core = Set(spec.name for spec in OCCURRENCE_SCHEMA)
        blocks = raw.__source
        for i in 1:n
            d = Dict{Symbol,Any}()
            block = blocks[i]
            if block !== missing && block !== nothing
                for (k, v) in pairs(block)
                    (v === missing || v === nothing || k in core) && continue
                    d[k] = v
                end
            end
            extra[i] = d
        end
    else
        for i in 1:n
            extra[i] = Dict{Symbol,Any}()
        end
    end
    push!(names, :extra)
    push!(columns, extra)

    table = OBISTable(names, columns, export_meta(files, absence, dropped, n))
    licenses === false && return table
    return attach_export_licenses(
        table, licenses === true ? OBIS.export_licenses() : licenses
    )
end

"""
    export_meta(files, absence, dropped, n) -> QueryMeta

Provenance for an export read.

The access date is the newest file's modification time rather than today: the records are as
old as the export that carried them, and a citation built from this table has to say when
the data was actually obtained.
"""
function export_meta(files, absence, dropped, n::Integer)
    params = QueryParams()
    params["files"] = join(basename.(files), ',')
    params["absence"] = String(string(absence))
    params["dropped"] = String(string(dropped))
    accessed = Date(unix2datetime(maximum(mtime, files)))
    return QueryMeta(
        "export/occurrence",
        sorted_pairs(params),
        accessed,
        now(UTC),
        Int(n),
        CONFIG.export_url,
        string(package_version()),
    )
end

"""
    attach_export_licenses(t, licence_table) -> OBISTable

Fill `license`, `license_url` and `dataset_citation` from the export's licence table.

The rows carry no rights of their own — `interpreted.license` is declared in the schema but
was empty in every export examined — so they are joined per dataset, exactly as the API path
joins them from `/dataset`.
"""
function attach_export_licenses(t::OBISTable, licence_table)
    index = Dict{String,NTuple{3,Union{Missing,String}}}()
    for i in 1:OBIS.nrow(licence_table)
        id = licence_table.dataset_id[i]
        ismissing(id) && continue
        index[String(id)] = (
            licence_table.license[i],
            licence_table.license_url[i],
            licence_table.citation[i],
        )
    end

    ids = Tables.getcolumn(t, :dataset_id)
    for (column, position) in
        ((:license, 1), (:license_url, 2), (:dataset_citation, 3))
        values = Tables.getcolumn(t, column)
        for i in eachindex(values)
            id = ids[i]
            ismissing(id) && continue
            hit = get(index, String(id), nothing)
            hit === nothing || (values[i] = hit[position])
        end
    end
    return t
end

end
