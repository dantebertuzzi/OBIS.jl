# Streaming, resumable pagination.
#
# `/occurrence` pages by keyset on the record UUID: results come back ordered by `id`
# ascending, and `after` is an exclusive lower bound. Two properties follow that this file
# is built on. The cursor is a plain UUID string, so a pull can be checkpointed to disk and
# resumed in a later session with no server-side state. And a pull can be consumed page by
# page, so a query larger than memory is still workable.
#
# The ordering is by UUID, which is effectively arbitrary with respect to taxon, place and
# date. A partially consumed pull is therefore a quasi-random subset of the matches, never
# "the first N by date"; `first_n` says so where a caller is most likely to assume otherwise.

"""
    OccurrencePages

A lazy iterator over pages of occurrence records.

Each iteration yields an [`OBISTable`](@ref) holding one page. Nothing is fetched until
iteration starts, and only one page is held in memory at a time, so a query far larger than
memory can still be processed.

The cursor is a record UUID. Read it with [`cursor`](@ref) after any page to checkpoint
progress, and pass it back as `after` to resume — in the same session or a later one.

Construct with [`occurrence_pages`](@ref).

# Examples

```julia
# Process a large query without holding it in memory.
total = 0
for page in OBISClient.occurrence_pages(scientificname = "Mollusca")
    total += OBISClient.nrow(page)
end

# Checkpoint, then resume in another session.
pages = OBISClient.occurrence_pages(scientificname = "Mollusca")
for page in pages
    process(page)
    write("checkpoint.txt", OBISClient.cursor(pages))
    break
end

resumed = OBISClient.occurrence_pages(
    scientificname = "Mollusca", after = read("checkpoint.txt", String)
)
```
"""
mutable struct OccurrencePages
    params::QueryParams
    page_size::Int
    start_after::Union{Nothing,String}
    cursor::Union{Nothing,String}
    fetched::Int
    total::Int
    progress::Bool
    with_licenses::Bool
end

"""
    cursor(pages::OccurrencePages) -> Union{Nothing,String}

The UUID of the last record yielded so far, or `nothing` before the first page.

Persist this to resume a pull later: it is the whole of the pagination state.
"""
cursor(p::OccurrencePages) = p.cursor

"""
    fetched(pages::OccurrencePages) -> Int

How many records have been yielded so far.
"""
fetched(p::OccurrencePages) = p.fetched

"""
    expected(pages::OccurrencePages) -> Int

How many records the API reports as matching, known after the first page is fetched.
"""
expected(p::OccurrencePages) = p.total

Base.IteratorSize(::Type{OccurrencePages}) = Base.SizeUnknown()
Base.eltype(::Type{OccurrencePages}) = OBISTable

function Base.iterate(p::OccurrencePages, state=nothing)
    if state === nothing
        p.cursor = p.start_after
        p.fetched = 0
    elseif state === :done
        return nothing
    end

    q = copy_params(p.params)
    q["size"] = p.page_size
    p.cursor === nothing || (q["after"] = p.cursor)

    payload = api_get("occurrence", q)
    records = results_of(payload)
    total = total_of(payload, p.total)
    p.total = total

    if isempty(records)
        p.progress && finish_progress(p)
        return nothing
    end

    last_id = nothing
    for r in Iterators.reverse(records)
        if r isa JSON3.Object && haskey(r, :id)
            last_id = String(r[:id])
            break
        end
    end

    p.fetched += length(records)
    meta = QueryMeta("occurrence", q, total)
    tbl = build_table(records, OCCURRENCE_SCHEMA, meta)
    p.with_licenses && (tbl = attach_licenses(tbl, p.params))

    p.progress && report_progress(p)

    if last_id === nothing
        # Without an `id` the cursor cannot advance, so continuing would re-fetch the same
        # page forever. This only happens when `fields` excludes `id`, which the parameter
        # validator prevents, but the loop must not be able to spin regardless.
        @warn "Stopping pagination: the response carried no `id`, so the cursor cannot advance."
        return (tbl, :done)
    end

    p.cursor = last_id
    return (tbl, p.cursor)
end

function copy_params(q::QueryParams)
    out = QueryParams()
    for (k, v) in pairs(q)
        (k == "size" || k == "after") && continue
        push!(out.pairs, k => v)
    end
    return out
end

function report_progress(p::OccurrencePages)
    pct = p.total > 0 ? round(100 * p.fetched / p.total; digits=1) : 0.0
    print(
        stderr,
        "\rOBIS: ",
        format_count(p.fetched),
        " / ",
        format_count(p.total),
        " records (",
        pct,
        "%)",
    )
    flush(stderr)
    return nothing
end

function finish_progress(p::OccurrencePages)
    print(stderr, "\rOBIS: ", format_count(p.fetched), " records retrieved.\n")
    flush(stderr)
    return nothing
end

"""
    concat_tables(tables) -> OBISTable

Concatenate tables that share a schema into one.

Used to assemble a complete result from paged responses. All inputs must have identical
column names, which they do by construction because the schema is fixed per endpoint.
"""
function concat_tables(tables::Vector{OBISTable}, meta::QueryMeta)
    isempty(tables) && error("internal error: nothing to concatenate")
    length(tables) == 1 && return OBISTable(_names(tables[1]), _columns(tables[1]), meta)

    names = _names(first(tables))
    for t in tables
        _names(t) == names || error("internal error: inconsistent schema across pages")
    end

    columns = AbstractVector[]
    for j in eachindex(names)
        parts = [_columns(t)[j] for t in tables]
        el = reduce(promote_type, (eltype(p) for p in parts))
        out = Vector{el}(undef, sum(length, parts))
        k = 1
        for part in parts
            copyto!(out, k, part, 1, length(part))
            k += length(part)
        end
        push!(columns, out)
    end

    return OBISTable(names, columns, meta)
end
