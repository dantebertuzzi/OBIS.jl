# The result type and its Tables.jl interface.
#
# Results implement Tables.jl rather than wrapping a DataFrame, so the package depends on
# neither DataFrames, CSV, Arrow nor Parquet while working with all of them. A result also
# carries the query that produced it and the date it was retrieved, because a citation
# needs an access date and only the client knows it.

"""
    QueryMeta

Provenance of a result: what was asked, of which service, and when.

The access date is recorded at request time because the OBIS citation format requires
`Accessed: YYYY-MM-DD` and nothing in the data itself supplies it. Carrying it on the
result is what lets [`citations`](@ref) produce a correct citation with no bookkeeping by
the caller.

# Fields

  - `endpoint`: API path the records came from.
  - `params`: query parameters as sent, in canonical order.
  - `accessed`: date of retrieval, for citations.
  - `retrieved`: UTC timestamp of retrieval.
  - `total`: number of records the API reported as matching, which may exceed the number
    held here when a query was limited or paged partially.
  - `base_url`: service the records came from.
  - `package_version`: version of this package that fetched them.
"""
struct QueryMeta
    endpoint::String
    params::Vector{Pair{String,String}}
    accessed::Date
    retrieved::DateTime
    total::Int
    base_url::String
    package_version::String
end

function QueryMeta(endpoint::AbstractString, params::QueryParams, total::Integer)
    return QueryMeta(
        String(endpoint),
        sorted_pairs(params),
        today(),
        now(UTC),
        Int(total),
        CONFIG.base_url,
        string(package_version()),
    )
end

"""
    OBISTable

A typed, column-oriented table of OBIS records that implements the Tables.jl interface.

The column set is fixed by the schema for the endpoint, so two queries against the same
endpoint always produce the same columns in the same order, with `missing` where a record
carried no value. Fields outside the core schema are preserved per row in the `extra`
column as a `Dict{Symbol,Any}`.

Columns are reached by property access, by index, or through any Tables.jl consumer:

```julia
tbl.scientificName          # a column
tbl[:decimalLatitude]       # the same column
DataFrame(tbl)              # with DataFrames loaded
CSV.write("out.csv", tbl)   # with CSV loaded
```

Use [`citations`](@ref) and [`licenses`](@ref) on a table to obtain the attribution its
data requires, and [`metadata`](@ref) to recover the query and access date.
"""
struct OBISTable <: Tables.AbstractColumns
    names::Vector{Symbol}
    lookup::Dict{Symbol,Int}
    columns::Vector{AbstractVector}
    meta::QueryMeta
end

function OBISTable(names::Vector{Symbol}, columns::Vector{AbstractVector}, meta::QueryMeta)
    length(names) == length(columns) || error(
        "internal error: $(length(names)) column names for $(length(columns)) columns"
    )
    return OBISTable(names, Dict(nm => i for (i, nm) in enumerate(names)), columns, meta)
end

# Internal accessors. `getproperty` is claimed by the Tables.jl column interface below, so
# the struct's own fields must be reached with `getfield`.
_names(t::OBISTable) = getfield(t, :names)
_columns(t::OBISTable) = getfield(t, :columns)
_lookup(t::OBISTable) = getfield(t, :lookup)

"""
    metadata(t::OBISTable) -> QueryMeta

Return the query, access date and reported total behind a result.

```julia
julia> meta = OceanBIS.metadata(tbl);

julia> meta.accessed        # the date to put in a citation
2026-09-06
```
"""
metadata(t::OBISTable) = getfield(t, :meta)

"""
    nrow(t::OBISTable) -> Int

Number of records held in the table.

This can be smaller than `metadata(t).total`, which is how many records the API reported
as matching the query.
"""
nrow(t::OBISTable) = isempty(_columns(t)) ? 0 : length(first(_columns(t)))

"""
    ncol(t::OBISTable) -> Int

Number of columns, including `extra`.
"""
ncol(t::OBISTable) = length(_names(t))

Base.size(t::OBISTable) = (nrow(t), ncol(t))
Base.size(t::OBISTable, d::Integer) = size(t)[d]
Base.isempty(t::OBISTable) = nrow(t) == 0

# --- Tables.jl -------------------------------------------------------------------------

Tables.istable(::Type{OBISTable}) = true
Tables.columnaccess(::Type{OBISTable}) = true
Tables.columns(t::OBISTable) = t
Tables.columnnames(t::OBISTable) = _names(t)
Tables.getcolumn(t::OBISTable, i::Int) = _columns(t)[i]
Tables.getcolumn(t::OBISTable, nm::Symbol) = _columns(t)[_lookup(t)[nm]]
Tables.getcolumn(t::OBISTable, ::Type{T}, i::Int, ::Symbol) where {T} = _columns(t)[i]
Tables.rowcount(t::OBISTable) = nrow(t)

function Tables.schema(t::OBISTable)
    return Tables.Schema(_names(t), Type[eltype(c) for c in _columns(t)])
end

Base.getindex(t::OBISTable, nm::Symbol) = Tables.getcolumn(t, nm)
Base.getindex(t::OBISTable, i::Int) = Tables.getcolumn(t, i)
Base.haskey(t::OBISTable, nm::Symbol) = haskey(_lookup(t), nm)
Base.keys(t::OBISTable) = _names(t)

# --- Construction ----------------------------------------------------------------------

"""
    build_table(records, schema, meta) -> OBISTable

Turn decoded JSON records into a typed table with a fixed column set.

Every core column is materialized whether or not any record carried the field, which is
what makes the schema stable across queries. Remaining fields are collected per row into
`extra`.
"""
function build_table(records, schema::Vector{FieldSpec}, meta::QueryMeta)
    n = length(records)
    core = Set(s.name for s in schema)

    names = Symbol[s.name for s in schema]
    columns = AbstractVector[Vector{column_type(s)}(undef, n) for s in schema]
    extra = Vector{Dict{Symbol,Any}}(undef, n)

    for (i, rec) in enumerate(records)
        for (j, spec) in enumerate(schema)
            raw = rec isa JSON3.Object ? get(rec, spec.name, nothing) : nothing
            columns[j][i] = coerce_field(spec, raw)
        end

        d = Dict{Symbol,Any}()
        if rec isa JSON3.Object
            for (k, v) in pairs(rec)
                k in core && continue
                d[k] = json_to_julia(v)
            end
        end
        extra[i] = d
    end

    push!(names, :extra)
    push!(columns, extra)
    return OBISTable(names, columns, meta)
end

"""
    json_to_julia(v)

Convert a JSON value into plain Julia containers.

Conversion is deliberate rather than storing the `JSON3` views directly: those views
reference the parsed buffer, so keeping them would pin the whole response in memory for as
long as any row survives.

Objects become `Dict{String,Any}`, matching the field names the API documentation uses. The
top level of a row's `extra` is keyed by `Symbol` instead, because those names are column
names.
"""
function json_to_julia(v)
    v === nothing && return missing
    v isa JSON3.Object &&
        return Dict{String,Any}(String(k) => json_to_julia(x) for (k, x) in pairs(v))
    v isa JSON3.Array && return Any[json_to_julia(x) for x in v]
    v isa AbstractString && return String(v)
    return v
end

"""
    extra_names(t::OBISTable) -> Vector{Symbol}

Names of the non-core fields present anywhere in the table, sorted.

These are the Darwin Core terms the providers supplied that fall outside the core schema.
Which of them appear depends on the query, which is exactly why they are held apart from
the core columns.

```julia
julia> OceanBIS.extra_names(tbl)
12-element Vector{Symbol}:
 :day
 :eventTime
 ⋮
```
"""
function extra_names(t::OBISTable)
    haskey(t, :extra) || return Symbol[]
    out = Set{Symbol}()
    for d in Tables.getcolumn(t, :extra)
        union!(out, keys(d))
    end
    return sort!(collect(out))
end

"""
    extra_column(t::OBISTable, name) -> Vector

Lift one non-core field out of `extra` into a plain column, with `missing` where a record
did not carry it.

```julia
julia> OceanBIS.extra_column(tbl, :waterBody)
```
"""
function extra_column(t::OBISTable, name)
    nm = Symbol(name)
    haskey(t, :extra) || throw(
        OBISValidationError(:name, name, "This table has no `extra` column.")
    )
    return [get(d, nm, missing) for d in Tables.getcolumn(t, :extra)]
end

# --- Display ---------------------------------------------------------------------------

function Base.show(io::IO, ::MIME"text/plain", t::OBISTable)
    meta = metadata(t)
    n, m = size(t)
    print(
        io,
        "OBISTable: ",
        format_count(n),
        " record",
        n == 1 ? "" : "s",
        ", ",
        m,
        " columns",
    )
    if meta.total > n
        print(io, " (of ", format_count(meta.total), " matching)")
    end
    print(io, "\n  endpoint:  ", meta.endpoint)
    print(io, "\n  accessed:  ", meta.accessed)
    if !isempty(meta.params)
        print(io, "\n  query:     ")
        join(io, (string(k, '=', v) for (k, v) in meta.params), ", ")
    end

    if haskey(t, :license) && n > 0
        ls = sort!(
            unique(
                String[ismissing(x) ? "unknown" : x for x in Tables.getcolumn(t, :license)]
            ),
        )
        print(io, "\n  licenses:  ", join(ls, ", "))
    end

    if n > 0
        preview = [nm for nm in _names(t) if nm !== :extra]
        print(io, "\n  columns:   ")
        shown = first(preview, 8)
        join(io, shown, ", ")
        length(preview) > length(shown) &&
            print(io, ", … (", length(preview) - length(shown), " more)")
    end
    return nothing
end

Base.show(io::IO, t::OBISTable) = show(io, MIME"text/plain"(), t)
