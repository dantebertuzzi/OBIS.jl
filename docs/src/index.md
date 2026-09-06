# OBIS.jl

A Julia client for OBIS, the Ocean Biodiversity Information System, a programme of the
Intergovernmental Oceanographic Commission of UNESCO.

OBIS aggregates marine biodiversity observations from thousands of datasets into one
integrated database, currently over 200 million occurrence records. This package retrieves
them.

## Installation

```julia
using Pkg
Pkg.add("OBIS")
```

## A first query

```julia
using OBIS

recs = OBIS.occurrence("Abra alba"; limit = 500)

recs.scientificName
recs.decimalLatitude
recs.flags
```

Results implement the Tables.jl interface, so they convert to whatever you already use —
`DataFrame(recs)`, `CSV.write("out.csv", recs)`, Arrow, Parquet — without this package
depending on any of them.

## What the package guarantees

**A stable, typed schema.** The same columns in the same order for every query against an
endpoint, with concrete types and `missing` for absent values. Darwin Core fields outside
the core schema are preserved per row in an `extra` column.

**Rights that travel with the data.** Every occurrence row carries the licence and citation
of the dataset it came from, and the result records the date it was retrieved.
[`OBIS.licenses`](@ref) says what you may do with a result; [`OBIS.citations`](@ref)
produces the credit it requires.

**Access to what the downloads omit.** Absence records and records dropped by the quality
pipeline are available through the API and not through the bulk downloads.

**A choice between access routes.** A query too large for the API raises an error naming
the alternatives rather than switching routes silently, because the routes do not cover the
same records.

## Where to go next

- [Getting started](getting-started.md) — the query interface, filters, and results.
- [Interpreting OBIS data](interpreting.md) — what the records mean, and the four ways a
  correct query becomes a wrong conclusion. Read this before analysing anything.
- [Licensing and citation](licensing.md) — your obligations, and how the package meets
  them.
- [Large queries](large-queries.md) — streaming, resuming, and the bulk export.
- [Reproducibility](reproducibility.md) — caching so an analysis can be re-run.
- [API reference](api.md).

## Scope

The package is a client and nothing more. It does not model, plot, or ship data. Analysis
belongs in packages built for it; OBIS records have a DOI and an access date, and freezing
a copy inside a package would break the citation it exists to support.
