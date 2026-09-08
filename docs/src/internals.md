# Internals

These are not part of the public interface and may change without a breaking release. They
are documented because the manual refers to them when explaining how the schema and the
request layer behave.

## Reference material

```@docs
OceanBIS.disclaimer
OceanBIS.OBIS_DISCLAIMER
OceanBIS.RECORD_SELECTIONS
```

## The schema

The canonical schema is what makes a result's columns the same for every query against an
endpoint. Each entry declares a column name, a concrete element type, and how the raw JSON
value is converted.

```@docs
OceanBIS.FieldSpec
OceanBIS.OCCURRENCE_SCHEMA
OceanBIS.TAXON_SCHEMA
OceanBIS.DATASET_SCHEMA
OceanBIS.NODE_SCHEMA
OceanBIS.INSTITUTE_SCHEMA
OceanBIS.AREA_SCHEMA
OceanBIS.COUNTRY_SCHEMA
OceanBIS.coerce_field
OceanBIS.coerce_scalar
OceanBIS.coerce_strlist
OceanBIS.coerce_named_list
OceanBIS.column_type
OceanBIS.schema_names
OceanBIS.coerce_epoch_ms
OceanBIS.coerce_iso_datetime
OceanBIS.coerce_flagset
OceanBIS.build_table
OceanBIS.json_to_julia
OceanBIS.empty_table
OceanBIS.take_rows
OceanBIS.concat_tables
```

## Request layer

```@docs
OceanBIS.api_get
OceanBIS.raw_request
OceanBIS.build_url
OceanBIS.request_headers
OceanBIS.retryable
OceanBIS.backoff_delay
OceanBIS.throttle!
OceanBIS.check_response
OceanBIS.results_of
OceanBIS.total_of
OceanBIS.TRANSPORT
OceanBIS.default_transport
OceanBIS.DOWNLOADER
OceanBIS.default_downloader
OceanBIS.http_error_advice
OceanBIS.LAST_REQUEST
```

## Parameter handling

```@docs
OceanBIS.build_params
OceanBIS.QueryParams
OceanBIS.selection_value
OceanBIS.validate_geometry
OceanBIS.format_date
OceanBIS.validate_depth
OceanBIS.validate_uuid
OceanBIS.validate_size
OceanBIS.validate_fields
OceanBIS.sorted_pairs
```

## Rights and citation

```@docs
OceanBIS.CitationEntry
OceanBIS.citation_entries
OceanBIS.format_citation
OceanBIS.bibtex_escape
OceanBIS.dataset_counts
OceanBIS.dataset_info
OceanBIS.dataset_filters
OceanBIS.attach_licenses
OceanBIS.finalize_dataset_table
OceanBIS.fetch_dataset_records
OceanBIS.DatasetInfo
```

## Access routes

```@docs
OceanBIS.guard_query_size
OceanBIS.stats_filters
OceanBIS.parse_licenses_tsv
OceanBIS.raw_request_absolute
OceanBIS.download_file
OceanBIS.EXPORT_COLUMN_SOURCES
OceanBIS.export_select
```

## Cache

```@docs
OceanBIS.cache_key
OceanBIS.cached_body
OceanBIS.store_body!
```

## Constants and helpers

```@docs
OceanBIS.DEFAULT_BASE_URL
OceanBIS.DEFAULT_EXPORT_URL
OceanBIS.REPO_URL
OceanBIS.MAX_PAGE_SIZE
OceanBIS.format_count
```
