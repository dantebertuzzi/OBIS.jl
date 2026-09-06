# Reproducibility

OBIS ingests records continuously. Datasets are added, corrected and re-harvested, and the
quality pipeline is updated. The same query run twice returns different data, and the
difference grows with time.

That is a problem for anything published. A figure in a paper is the output of a query
against a database that no longer exists in that state, and nothing in the data records
which state that was.

## Caching raw responses

An optional local cache stores each raw response, addressed by a hash of the query, with
the retrieval date and the response `ETag`:

```julia
using OBIS

OBIS.configure!(cache = OBIS.QueryCache("data/obis-cache"))

recs = OBIS.occurrence("Abra alba"; limit = 5000)   # fetched and stored
again = OBIS.occurrence("Abra alba"; limit = 5000)  # served from disk, no request
```

Entries never expire. An expiring cache cannot answer "re-run this against the data as it
stood in March", which is the point. Remove entries explicitly:

```julia
OBIS.clear_cache!()
```

What is stored is the **raw response body**, not the parsed table. So a re-run reproduces
the original data even if the package's schema handling has changed in the meantime — the
stored artifact does not depend on this package's decisions.

The cache key covers the base URL, the endpoint and the parameters, sorted, so keyword
order does not matter:

```julia
OBIS.occurrence("Abra alba"; startdepth = 5, limit = 100)
OBIS.occurrence(; startdepth = 5, scientificname = "Abra alba", limit = 100)  # same entry
```

## Keeping the cache with the analysis

Put the cache in the project directory and commit it, or archive it alongside the results:

```julia
OBIS.configure!(cache = OBIS.QueryCache(joinpath(@__DIR__, "data", "obis-cache")))
```

The directory holds one `.json` response and one `.meta.json` per query. The metadata
records what was asked and when:

```julia
for e in OBIS.cache_entries()
    println(e["endpoint"], "  ", e["accessed"], "  ", e["bytes"], " bytes")
    println("  ", e["parameters"])
end
```

## Guaranteeing a re-run uses the cache

A cache that silently falls back to the network is not a guarantee. Open it read-only and
any query that is not already cached fails loudly instead of fetching today's data:

```julia
OBIS.configure!(cache = OBIS.QueryCache("data/obis-cache"; readonly = true))

recs = OBIS.occurrence("Abra alba"; limit = 5000)   # from disk

OBIS.occurrence("Zostera marina")                    # OBISAPIError: not in the cache
```

This is the mode to use when re-running a published analysis: it turns "the numbers changed
and I do not know why" into an error naming the query that was not part of the original
run.

## Citing what you actually used

The access date belongs to the request, so the citation should carry the date the data was
retrieved, not the date the script was last run. Read it from the cache:

```julia
for e in OBIS.cache_entries()
    println(e["endpoint"], " accessed ", e["accessed"])
end
```

A dataset DOI, where the provider registered one, is a stable pointer to the source
independent of OBIS's current state, and is included in the citation output:

```julia
cites = OBIS.citations(recs)
collect(skipmissing(cites.doi))
```

See [Licensing and citation](licensing.md).

## What caching does not give you

The cache pins the *responses*, not the OBIS database. It does not tell you what changed
upstream, and it cannot reconstruct a query you never ran. If reproducibility matters for a
piece of work:

- cache every query the analysis makes, from the start;
- keep the cache directory with the code;
- record the access date in the manuscript, which the citations already do;
- and where a dataset has a DOI, cite it, so a reader can reach the source directly.

For a frozen snapshot of the whole database rather than of your queries, OBIS publishes
dated bulk exports; see [Large queries](large-queries.md).
