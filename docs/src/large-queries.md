# Large queries

OBIS holds over 200 million occurrence records. Most useful queries are far smaller, but
some are not, and the two ways of getting a large result differ in what they can serve.

## Size a query before running it

`statistics` accepts the same filters as `occurrence` and counts the records that query
would return, in one cheap request:

```julia
using OBIS

OBIS.statistics("Mollusca")["records"]
OBIS.estimate_size(; scientificname = "Mollusca")
```

## The limit, and why it is an error

By default, `occurrence` estimates a query first and refuses to page through more than
`api_record_limit` records — 100,000 unless you change it. The refusal is deliberate rather
than a silent switch to the bulk export, because **the two routes do not return the same
records**:

- The export is a periodic snapshot and the API is live, so the same query answered from
  each differs by whatever OBIS has ingested since the export was built.
- Pure event records can be selected on the API and not in the export, which carries no
  column identifying them.
- The export is per dataset and unfiltered: you get whole files and apply the query's
  filters yourself.

Changing route silently would change the answer, so the package explains the options and
lets you choose:

```julia
OBIS.occurrence("Mollusca")
# ERROR: OBISLargeQueryError: this query matches about 12,345,678 records, above the
# configured API limit of 100,000.
#   Options, in the order most likely to help:
#
#   1. Narrow the query — add `geometry`, `startdate`/`enddate`, or a `datasetid`.
#   2. Take only part of it, with `limit = n`.
#   3. Stream it with `OBIS.occurrence_pages(...)`.
#   4. Use the bulk export, which OBIS recommends at this volume.
```

Adjust or bypass the guard as you see fit:

```julia
OBIS.configure!(api_record_limit = 1_000_000)
OBIS.occurrence("Mollusca"; check_size = false)
```

## Streaming

[`OBIS.occurrence_pages`](@ref) yields one page at a time. Nothing is fetched until
iteration begins, and only one page is in memory at once, so a query larger than memory is
still workable.

```julia
counts = Dict{String,Int}()

for page in OBIS.occurrence_pages("Mollusca"; page_size = 10_000, progress = true)
    for name in page.scientificName
        ismissing(name) || (counts[name] = get(counts, name, 0) + 1)
    end
end
```

Every page is a full [`OBIS.OBISTable`](@ref) with the same schema, so anything that works
on a complete result works on a page.

### Resuming

Pagination is keyset on the record UUID, so the entire cursor is one string. Save it and
resume — in the same session or a later one, after an interruption or a crash:

```julia
pages = OBIS.occurrence_pages("Mollusca"; page_size = 10_000)

for page in pages
    process(page)
    write("obis.cursor", OBIS.cursor(pages))
end

# Later, on a different day:
resumed = OBIS.occurrence_pages(
    "Mollusca"; page_size = 10_000, after = read("obis.cursor", String)
)
```

Note what the ordering is and is not. Records come back ordered by UUID, which is unrelated
to date, place or taxon. A partial pull is an arbitrary subset of the matches — never "the
earliest records" or "the nearest ones". If you need the earliest records, filter by date.

## The bulk export

OBIS publishes the full occurrence dataset as GeoParquet on AWS Open Data, one file per
source dataset, roughly 50 GB in total. The files are served over plain HTTPS with no
credentials, so a query's worth can be fetched by resolving the query to its datasets:

```julia
paths = OBIS.download_exports("Abra alba"; dir = "obis-export")
```

### Reading what you downloaded

The files are not the table the API returns. Their schema has 622 columns: the provider's
own terms nested under `source`, the quality pipeline's under `interpreted`, the geometry as
WKB, and the AphiaID spelled `aphiaid` rather than `aphiaID`. The field names are documented
at [github.com/iobis/obis-open-data](https://github.com/iobis/obis-open-data).

[`OBIS.read_export`](@ref) reads them into the canonical schema, so the two access routes
become interchangeable in everything downstream:

```julia
using DuckDB          # loads the extension that implements read_export

recs = OBIS.read_export(paths)

OBIS.licenses(recs)                          # works, as on an API result
OBIS.citations(recs; format = :bibtex)       # likewise
DataFrame(recs)
```

`absence` and `dropped` default to `:exclude`, as on the API, because the export contains
those records — a plain `select *` would mix them into an ordinary count without saying so.
Pass `:include` or `:only` for the other two views, and the filter is pushed into the read
rather than applied to a materialized table.

Two columns are always `missing`: the export carries `marine` and `brackish` but not
`freshwater` or `terrestrial`. The access date on the result is the file's modification
time, not today, because the records are as old as the export that carried them.

DuckDB is a weak dependency, so it is installed only if you ask for it, and Parquet2.jl is
not an alternative here: it does not support the nested struct columns the export is built
from (NOTES.md §7.4).

Nothing stops you reading the files yourself instead — they are ordinary Parquet:

```julia
using DuckDB, DBInterface
con = DBInterface.connect(DuckDB.DB)
DBInterface.execute(con, """
    select interpreted.scientificName, interpreted.decimalLatitude, interpreted.decimalLongitude
    from read_parquet('obis-export/*.parquet')
    where interpreted.speciesid = 141433
      and dropped is not true and absence is not true
""")
```

[`OBIS.export_covers`](@ref) reports whether the export can serve a query at all:

```julia
OBIS.export_covers(; scientificname = "Abra alba")     # true
OBIS.export_covers(; absence = :only)                  # true — the export carries them
OBIS.export_covers(; event = :only)                    # false — API only
```

Absence and dropped records are in the export, despite the data access page saying
otherwise, which is why the query above filters them out explicitly rather than assuming
they are absent. Checked against `/statistics` for five datasets: the export's `absence`
and `dropped` row counts matched the API's `absence = :only` and `dropped = :only` counts
exactly, and each export's total came to the default count plus them.

The full OBIS dataset is itself licensed CC BY-NC. The licence and citation for every
source dataset are published alongside it:

```julia
OBIS.export_licenses()
```

That table is regenerated with the export and lags the live API, so for a live query take
licences from the result or from `OBIS.dataset`.

## Being a good client

OBIS publishes no request quota, and its data access page asks users not to parallelize
downloads. The package follows that: requests are serial, identified by a `User-Agent`
naming the package and this repository, and backed off exponentially on failure.

The courteous way to speed up a large pull is fewer, larger requests:

```julia
OBIS.configure!(page_size = 10_000)     # the maximum the API accepts
```

On a shared or metered connection, or if you are running many queries in a loop, space them
out:

```julia
OBIS.configure!(request_gap = 1.0)
```
