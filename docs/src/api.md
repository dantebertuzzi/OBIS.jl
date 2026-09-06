# API reference

## The module

```@docs
OBIS.OBIS
```

## Occurrences

```@docs
OBIS.occurrence
OBIS.occurrence_pages
OBIS.occurrence_by_id
OBIS.OccurrencePages
OBIS.cursor
OBIS.fetched
OBIS.expected
```

## Taxa and checklists

```@docs
OBIS.taxon
OBIS.taxon_annotations
OBIS.checklist
OBIS.checklist_redlist
OBIS.checklist_newest
```

## Datasets, nodes, institutes, areas, countries

```@docs
OBIS.dataset
OBIS.dataset_by_id
OBIS.dataset_errors
OBIS.node
OBIS.node_activities
OBIS.institute
OBIS.institute_by_id
OBIS.area
OBIS.country
OBIS.metrics
OBIS.metrics_downloads
```

## Statistics and facets

```@docs
OBIS.statistics
OBIS.statistics_years
OBIS.statistics_env
OBIS.statistics_qc
OBIS.statistics_composition
OBIS.facet
OBIS.estimate_size
```

## Results

```@docs
OBIS.OBISTable
OBIS.QueryMeta
OBIS.metadata
OBIS.nrow
OBIS.ncol
OBIS.extra_names
OBIS.extra_column
```

## Licensing and citation

```@docs
OBIS.licenses
OBIS.citations
OBIS.obis_citation
OBIS.normalize_license
OBIS.license_url
OBIS.permits_redistribution
OBIS.permits_commercial_use
OBIS.requires_attribution
OBIS.ACCEPTED_LICENSES
OBIS.LICENSE_URLS
```

## Quality flags

```@docs
OBIS.KNOWN_FLAGS
OBIS.DROPPING_FLAGS
OBIS.normalize_flag
OBIS.normalize_flags
OBIS.drops_record
```

## The bulk export

```@docs
OBIS.export_covers
OBIS.export_url
OBIS.export_archive_url
OBIS.download_export
OBIS.download_exports
OBIS.export_licenses
```

## Configuration and caching

```@docs
OBIS.config
OBIS.configure!
OBIS.ClientConfig
OBIS.QueryCache
OBIS.cache_entries
OBIS.clear_cache!
OBIS.default_cache_dir
OBIS.package_version
```

## Errors

```@docs
OBIS.OBISError
OBIS.OBISValidationError
OBIS.OBISNameNotFoundError
OBIS.OBISAPIError
OBIS.OBISConnectionError
OBIS.OBISLargeQueryError
```

## Reference material

```@docs
OBIS.disclaimer
OBIS.OBIS_DISCLAIMER
OBIS.RECORD_SELECTIONS
OBIS.OCCURRENCE_SCHEMA
OBIS.TAXON_SCHEMA
OBIS.DATASET_SCHEMA
OBIS.FieldSpec
OBIS.coerce_field
OBIS.column_type
```
