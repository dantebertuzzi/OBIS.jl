# Internals

These are not part of the public interface and may change without a breaking release. They
are documented because the manual refers to them when explaining how the schema and the
request layer behave.

## Reference material

```@docs
OBIS.disclaimer
OBIS.OBIS_DISCLAIMER
OBIS.RECORD_SELECTIONS
```

## The schema

The canonical schema is what makes a result's columns the same for every query against an
endpoint. Each entry declares a column name, a concrete element type, and how the raw JSON
value is converted.

```@docs
OBIS.FieldSpec
OBIS.OCCURRENCE_SCHEMA
OBIS.TAXON_SCHEMA
OBIS.DATASET_SCHEMA
OBIS.NODE_SCHEMA
OBIS.INSTITUTE_SCHEMA
OBIS.AREA_SCHEMA
OBIS.COUNTRY_SCHEMA
OBIS.coerce_field
OBIS.coerce_scalar
OBIS.coerce_strlist
OBIS.coerce_named_list
OBIS.column_type
OBIS.schema_names
OBIS.coerce_epoch_ms
OBIS.coerce_iso_datetime
OBIS.coerce_flagset
OBIS.build_table
OBIS.json_to_julia
OBIS.empty_table
OBIS.take_rows
OBIS.concat_tables
```

## Request layer

```@docs
OBIS.api_get
OBIS.raw_request
OBIS.build_url
OBIS.request_headers
OBIS.retryable
OBIS.backoff_delay
OBIS.throttle!
OBIS.check_response
OBIS.results_of
OBIS.total_of
OBIS.TRANSPORT
OBIS.default_transport
OBIS.http_error_advice
OBIS.LAST_REQUEST
```

## Parameter handling

```@docs
OBIS.build_params
OBIS.QueryParams
OBIS.selection_value
OBIS.validate_geometry
OBIS.format_date
OBIS.validate_depth
OBIS.validate_uuid
OBIS.validate_size
OBIS.validate_fields
OBIS.sorted_pairs
```

## Rights and citation

```@docs
OBIS.CitationEntry
OBIS.citation_entries
OBIS.format_citation
OBIS.bibtex_escape
OBIS.dataset_counts
OBIS.dataset_info
OBIS.dataset_filters
OBIS.attach_licenses
OBIS.finalize_dataset_table
OBIS.fetch_dataset_records
OBIS.DatasetInfo
```

## Access routes

```@docs
OBIS.guard_query_size
OBIS.stats_filters
OBIS.parse_licenses_tsv
OBIS.raw_request_absolute
OBIS.download_file
```

## Cache

```@docs
OBIS.cache_key
OBIS.cached_body
OBIS.store_body!
```

## Constants and helpers

```@docs
OBIS.DEFAULT_BASE_URL
OBIS.DEFAULT_EXPORT_URL
OBIS.REPO_URL
OBIS.MAX_PAGE_SIZE
OBIS.format_count
```
