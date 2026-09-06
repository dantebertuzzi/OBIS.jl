# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

Initial release.

### Added

- Occurrence queries with the full filter set: taxon name and AphiaID, WKT geometry, date
  and depth ranges, dataset, node, institute and area identifiers, quality flags, and the
  measurement and extension filters.
- Tri-state `absence`, `dropped` and `event` selection, giving access to absence records
  and to records the quality pipeline dropped.
- A canonical typed schema with a fixed column set per endpoint, concrete element types,
  and non-core Darwin Core fields preserved per row in an `extra` column.
- Licence and citation joined onto every occurrence row, with the access date recorded at
  request time; `licenses` and `citations`, the latter in table, text and BibTeX form.
- Tables.jl interface on results, with an optional DataFrames extension that flattens the
  `extra` column and extends the DataAPI `nrow`/`ncol` generics.
- Lazy, resumable pagination through `occurrence_pages`, with an optional progress
  indicator and a cursor that serializes to a single string.
- An optional local cache addressed by query hash, storing raw responses with their
  retrieval date, and a read-only mode that refuses to fall back to the network.
- A query-size guard that estimates a query through `/statistics` and raises rather than
  switching access routes silently.
- The bulk export route: per-dataset GeoParquet downloads, the export licence table, and
  `export_covers` to report which queries the export cannot serve.
- The remaining endpoints: taxon, checklist, dataset, node, institute, area, country,
  facet, statistics and metrics.
- Client-side validation of geometry, dates, depths, identifiers, page sizes, field lists
  and quality flags, with errors that name the fix.
- Serial requests with an identifying `User-Agent`, exponential backoff on 429 and 5xx,
  and `Retry-After` support.
