# Public API

Everything a caller needs. Functions the package uses internally are in
[Internals](internals.md).

## The module

```@docs
OceanBIS
```

## Occurrences

```@docs
OceanBIS.occurrence
OceanBIS.occurrence_pages
OceanBIS.occurrence_by_id
OceanBIS.OccurrencePages
OceanBIS.cursor
OceanBIS.fetched
OceanBIS.expected
```

## Taxa and checklists

```@docs
OceanBIS.taxon
OceanBIS.taxon_annotations
OceanBIS.checklist
OceanBIS.checklist_redlist
OceanBIS.checklist_newest
```

## Datasets, nodes, institutes, areas, countries

```@docs
OceanBIS.dataset
OceanBIS.dataset_by_id
OceanBIS.dataset_errors
OceanBIS.node
OceanBIS.node_activities
OceanBIS.institute
OceanBIS.institute_by_id
OceanBIS.area
OceanBIS.country
OceanBIS.metrics
OceanBIS.metrics_downloads
```

## Statistics and facets

```@docs
OceanBIS.statistics
OceanBIS.statistics_years
OceanBIS.statistics_env
OceanBIS.statistics_qc
OceanBIS.statistics_composition
OceanBIS.facet
OceanBIS.estimate_size
```

## Results

```@docs
OceanBIS.OBISTable
OceanBIS.QueryMeta
OceanBIS.metadata
OceanBIS.nrow
OceanBIS.ncol
OceanBIS.extra_names
OceanBIS.extra_column
```

## Licensing and citation

```@docs
OceanBIS.licenses
OceanBIS.citations
OceanBIS.obis_citation
OceanBIS.normalize_license
OceanBIS.license_url
OceanBIS.permits_redistribution
OceanBIS.permits_commercial_use
OceanBIS.requires_attribution
OceanBIS.ACCEPTED_LICENSES
OceanBIS.LICENSE_URLS
```

## Quality flags

```@docs
OceanBIS.KNOWN_FLAGS
OceanBIS.DROPPING_FLAGS
OceanBIS.normalize_flag
OceanBIS.normalize_flags
OceanBIS.drops_record
```

## The bulk export

```@docs
OceanBIS.export_covers
OceanBIS.export_url
OceanBIS.export_archive_url
OceanBIS.download_export
OceanBIS.download_exports
OceanBIS.export_licenses
OceanBIS.read_export
```

## Configuration and caching

```@docs
OceanBIS.config
OceanBIS.configure!
OceanBIS.ClientConfig
OceanBIS.QueryCache
OceanBIS.cache_entries
OceanBIS.clear_cache!
OceanBIS.default_cache_dir
OceanBIS.package_version
```

## Errors

```@docs
OceanBIS.OBISError
OceanBIS.OBISValidationError
OceanBIS.OBISNameNotFoundError
OceanBIS.OBISAPIError
OceanBIS.OBISConnectionError
OceanBIS.OBISLargeQueryError
```
