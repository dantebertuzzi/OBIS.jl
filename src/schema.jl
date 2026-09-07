# The canonical typed schema.
#
# JSON objects omit absent keys, so the API returns a different field set for every query:
# a sample of 2,000 occurrence records across five taxa contained 188 distinct field names,
# of which only 25 appeared in every record. Converting records to rows directly would
# therefore produce a different column set for each query, and for the same query run again
# after OBIS ingests new data.
#
# So the package fixes a core schema instead. Core columns are always present, always
# concretely typed, and hold `missing` where a record has no value. Fields outside the core
# are preserved verbatim in an `extra` column, which keeps Darwin Core terms the provider
# supplied without letting them destabilize the main schema.
#
# Numeric coercion is not optional here. JSON has a single number type and the encoder
# drops a zero fractional part, so `decimalLatitude` arrives as an integer in about 2% of
# records; inferring types per value would yield `Union{Int64,Float64}` coordinate columns.

"""
    FieldSpec(name, type, kind)

One column of a canonical schema.

  - `name`: column name, matching the API's field name so that documentation transfers.
  - `type`: concrete element type. The column's element type is `Union{Missing,type}`
    unless `kind` supplies a non-missing default.
  - `kind`: how the raw JSON value is converted. See [`coerce_field`](@ref).
"""
struct FieldSpec
    name::Symbol
    type::Type
    kind::Symbol
end

FieldSpec(name::Symbol, type::Type) = FieldSpec(name, type, :direct)

"""
    OCCURRENCE_SCHEMA

Core columns of an occurrence table, in column order.

Includes every field OBIS's quality pipeline adds or interprets, plus the record-level
Darwin Core terms that carry the identity, taxonomy, position and time of an observation.
Verbatim provider fields outside this list — including `year`, `month` and `day`, whose
interpreted counterpart is `date_year` — are kept in the `extra` column.
"""
const OCCURRENCE_SCHEMA = FieldSpec[
    # Identity and provenance.
    FieldSpec(:id, String),
    FieldSpec(:dataset_id, String),
    # Rights travel with the record. These three are not API fields: an occurrence record
    # carries no licence at all, so they are filled from the record's dataset. They are part
    # of the schema rather than appended conditionally, so the columns exist even when the
    # lookup is switched off — a query never changes shape because of a keyword.
    FieldSpec(:license, String),
    FieldSpec(:license_url, String),
    FieldSpec(:dataset_citation, String),
    FieldSpec(:occurrenceID, String),
    FieldSpec(:eventID, String),
    FieldSpec(:catalogNumber, String),
    FieldSpec(:collectionCode, String),
    FieldSpec(:institutionCode, String),
    FieldSpec(:datasetName, String),
    FieldSpec(:datasetID, String),
    FieldSpec(:node_id, Vector{String}, :strlist),
    FieldSpec(:basisOfRecord, String),
    FieldSpec(:occurrenceStatus, String),
    # Taxonomy, as interpreted against the World Register of Marine Species.
    FieldSpec(:scientificName, String),
    FieldSpec(:originalScientificName, String),
    FieldSpec(:scientificNameID, String),
    FieldSpec(:aphiaID, Int),
    FieldSpec(:taxonRank, String),
    FieldSpec(:kingdom, String),
    FieldSpec(:phylum, String),
    FieldSpec(:class, String),
    FieldSpec(:order, String),
    FieldSpec(:family, String),
    FieldSpec(:genus, String),
    FieldSpec(:species, String),
    FieldSpec(:kingdomid, Int),
    FieldSpec(:phylumid, Int),
    FieldSpec(:classid, Int),
    FieldSpec(:orderid, Int),
    FieldSpec(:familyid, Int),
    FieldSpec(:genusid, Int),
    FieldSpec(:speciesid, Int),
    # Position.
    FieldSpec(:decimalLongitude, Float64),
    FieldSpec(:decimalLatitude, Float64),
    FieldSpec(:coordinateUncertaintyInMeters, Float64),
    FieldSpec(:geodeticDatum, String),
    # Depth and environment, added or validated by the quality pipeline.
    FieldSpec(:depth, Float64),
    FieldSpec(:minimumDepthInMeters, Float64),
    FieldSpec(:maximumDepthInMeters, Float64),
    FieldSpec(:bathymetry, Float64),
    FieldSpec(:shoredistance, Float64),
    FieldSpec(:sst, Float64),
    FieldSpec(:sss, Float64),
    # Time. `date_*` are Unix timestamps in milliseconds on the wire.
    FieldSpec(:eventDate, String),
    FieldSpec(:date_start, DateTime, :epoch_ms),
    FieldSpec(:date_mid, DateTime, :epoch_ms),
    FieldSpec(:date_end, DateTime, :epoch_ms),
    FieldSpec(:date_year, Int),
    # Quality control.
    FieldSpec(:flags, Set{String}, :flagset),
    FieldSpec(:dropped, Bool),
    FieldSpec(:absence, Bool),
    FieldSpec(:marine, Bool),
    FieldSpec(:brackish, Bool),
    FieldSpec(:freshwater, Bool),
    FieldSpec(:terrestrial, Bool),
    FieldSpec(:redlist_category, String),
    # Observation detail.
    FieldSpec(:individualCount, Float64),
    FieldSpec(:lifeStage, String),
    FieldSpec(:sex, String),
]

"""
    TAXON_SCHEMA

Core columns of a taxon or checklist table.

`records` is populated by `/checklist` and absent from `/taxon`, so it is `missing` for the
latter rather than a column that appears and disappears between the two.
"""
const TAXON_SCHEMA = FieldSpec[
    FieldSpec(:taxonID, Int),
    FieldSpec(:scientificName, String),
    FieldSpec(:scientificNameAuthorship, String),
    FieldSpec(:taxonRank, String),
    FieldSpec(:taxonomicStatus, String),
    FieldSpec(:acceptedNameUsage, String),
    FieldSpec(:acceptedNameUsageID, Int),
    FieldSpec(:kingdom, String),
    FieldSpec(:phylum, String),
    FieldSpec(:class, String),
    FieldSpec(:order, String),
    FieldSpec(:family, String),
    FieldSpec(:genus, String),
    FieldSpec(:species, String),
    FieldSpec(:kingdomid, Int),
    FieldSpec(:phylumid, Int),
    FieldSpec(:classid, Int),
    FieldSpec(:orderid, Int),
    FieldSpec(:familyid, Int),
    FieldSpec(:genusid, Int),
    FieldSpec(:speciesid, Int),
    FieldSpec(:is_marine, Bool),
    FieldSpec(:is_brackish, Bool),
    FieldSpec(:is_freshwater, Bool),
    FieldSpec(:is_terrestrial, Bool),
    FieldSpec(:ncbi_id, Int),
    FieldSpec(:records, Int),
]

"""
    DATASET_SCHEMA

Core columns of a dataset table.

`license` and `license_url` are not API fields. OBIS reports the licence as free prose in
`intellectualrights`, so the package derives a normalized identifier and a canonical URL
from it and keeps the original text alongside. See [`normalize_license`](@ref).
"""
const DATASET_SCHEMA = FieldSpec[
    FieldSpec(:id, String),
    FieldSpec(:title, String),
    FieldSpec(:citation, String),
    FieldSpec(:citation_id, String),
    FieldSpec(:license, String),
    FieldSpec(:license_url, String),
    FieldSpec(:intellectualrights, String),
    FieldSpec(:url, String),
    FieldSpec(:archive, String),
    FieldSpec(:core, String),
    FieldSpec(:abstract, String),
    FieldSpec(:extent, String),
    FieldSpec(:records, Int),
    FieldSpec(:published, DateTime, :iso_datetime),
    FieldSpec(:created, DateTime, :iso_datetime),
    FieldSpec(:updated, DateTime, :iso_datetime),
    FieldSpec(:node_names, Vector{String}, :node_names),
    FieldSpec(:institute_names, Vector{String}, :institute_names),
]

"""
    NODE_SCHEMA

Core columns of a node table.
"""
const NODE_SCHEMA = FieldSpec[
    FieldSpec(:id, String),
    FieldSpec(:name, String),
    FieldSpec(:description, String),
    FieldSpec(:theme, String),
    FieldSpec(:type, String),
    FieldSpec(:lon, Float64),
    FieldSpec(:lat, Float64),
]

"""
    INSTITUTE_SCHEMA

Core columns of an institute table. `id` is the OceanExpert identifier.
"""
const INSTITUTE_SCHEMA = FieldSpec[
    FieldSpec(:id, Int),
    FieldSpec(:name, String),
    FieldSpec(:country, String),
    FieldSpec(:records, Int),
]

"""
    AREA_SCHEMA

Core columns of an area table.
"""
const AREA_SCHEMA = FieldSpec[
    FieldSpec(:id, Int), FieldSpec(:name, String), FieldSpec(:type, String)
]

"""
    COUNTRY_SCHEMA

Core columns of a country table.
"""
const COUNTRY_SCHEMA = FieldSpec[
    FieldSpec(:id, Int), FieldSpec(:country, String), FieldSpec(:code, String)
]

# ---------------------------------------------------------------------------------------
# Coercion
# ---------------------------------------------------------------------------------------

"""
    coerce_field(spec, value)

Convert one raw JSON value into the type its [`FieldSpec`](@ref) declares.

Returns `missing` when the value is absent or cannot be represented, except for `:flagset`
and list kinds, which return an empty collection. An empty flag set means "no quality flags
were raised", which is a fact about the record rather than a gap in it, so `flags` is never
`missing` and set membership tests need no missing-handling.
"""
function coerce_field(spec::FieldSpec, value)
    if spec.kind === :flagset
        return coerce_flagset(value)
    elseif spec.kind === :strlist
        return coerce_strlist(value)
    elseif spec.kind === :node_names
        return coerce_named_list(value, :name)
    elseif spec.kind === :institute_names
        return coerce_named_list(value, :name)
    end

    (value === nothing || value === missing) && return missing

    if spec.kind === :epoch_ms
        return coerce_epoch_ms(value)
    elseif spec.kind === :iso_datetime
        return coerce_iso_datetime(value)
    end

    return coerce_scalar(spec.type, value)
end

"Convert to `Float64`, accepting the integers JSON produces for whole numbers."
function coerce_scalar(::Type{Float64}, v)
    v isa Real && return Float64(v)
    v isa AbstractString && return something(tryparse(Float64, strip(String(v))), missing)
    return missing
end

function coerce_scalar(::Type{Int}, v)
    v isa Integer && return Int(v)
    # A whole-valued float is the same identifier; a fractional one is not an Int.
    v isa Real && return isinteger(v) ? Int(v) : missing
    v isa AbstractString && return something(tryparse(Int, strip(String(v))), missing)
    return missing
end

function coerce_scalar(::Type{Bool}, v)
    v isa Bool && return v
    v isa Integer && return v != 0
    if v isa AbstractString
        s = lowercase(strip(String(v)))
        s in ("true", "1", "yes") && return true
        s in ("false", "0", "no") && return false
    end
    return missing
end

function coerce_scalar(::Type{String}, v)
    v isa AbstractString && return String(v)
    (v isa JSON3.Object || v isa JSON3.Array) && return missing
    return String(string(v))
end

coerce_scalar(::Type, v) = missing

"""
    coerce_epoch_ms(v) -> Union{Missing,DateTime}

Convert a Unix timestamp in **milliseconds** to a `DateTime`.

The API's `date_start`, `date_mid` and `date_end` are milliseconds, not seconds, so
`unix2datetime` applied directly would place every record about fifty thousand years into
the future.
"""
function coerce_epoch_ms(v)
    ms = v isa Real ? Float64(v) : (v isa AbstractString ? tryparse(Float64, v) : nothing)
    ms === nothing && return missing
    try
        return Dates.unix2datetime(ms / 1000)
    catch
        return missing
    end
end

"""
    coerce_iso_datetime(v) -> Union{Missing,DateTime}

Parse the timestamp forms OBIS metadata uses.

Dataset timestamps are ISO 8601 with milliseconds and a `Z` suffix, while occurrence
`modified` values use a space separator and no zone, so both are accepted.
"""
function coerce_iso_datetime(v)
    v isa AbstractString || return missing
    s = strip(String(v))
    isempty(s) && return missing
    s = replace(s, r"Z$" => "")
    s = replace(s, r"[+-]\d{2}:?\d{2}$" => "")
    s = replace(s, ' ' => 'T')
    for fmt in (
        dateformat"yyyy-mm-ddTHH:MM:SS.sss",
        dateformat"yyyy-mm-ddTHH:MM:SS",
        dateformat"yyyy-mm-ddTHH:MM",
        dateformat"yyyy-mm-dd",
    )
        d = tryparse(DateTime, s, fmt)
        d === nothing || return d
    end
    return missing
end

"""
    coerce_flagset(v) -> Set{String}

Parse quality flags into a set.

The API sends a JSON array; the CSV downloads use a comma-separated string. Both are
accepted so that flag handling is the same whichever surface the values came from. A set
is the honest representation: flags are unordered and each is present at most once.
"""
function coerce_flagset(v)
    (v === nothing || v === missing) && return Set{String}()
    v isa AbstractString && return Set(
        uppercase(strip(String(s))) for s in split(v, ',') if !isempty(strip(s))
    )
    out = Set{String}()
    for f in v
        # A `missing` element is not a flag. JSON never produces one, but a Parquet list
        # column is typed `Union{Missing,String}` and an export read comes through here.
        (f === nothing || f === missing) && continue
        s = uppercase(strip(String(string(f))))
        isempty(s) || push!(out, s)
    end
    return out
end

"Parse a JSON array of strings; a bare string becomes a one-element vector."
function coerce_strlist(v)
    (v === nothing || v === missing) && return String[]
    v isa AbstractString && return [String(v)]
    return [String(string(x)) for x in v if x !== nothing && x !== missing]
end

"Pull one key out of each object in a JSON array of objects."
function coerce_named_list(v, key::Symbol)
    (v === nothing || v === missing) && return String[]
    out = String[]
    for item in v
        item isa JSON3.Object || continue
        val = get(item, key, nothing)
        val === nothing || push!(out, String(string(val)))
    end
    return out
end

"""
    column_type(spec) -> Type

Element type of the column a [`FieldSpec`](@ref) describes.

Collection-valued columns are never `missing`: an empty collection already says "nothing
here", and adding `missing` would force every caller to handle two kinds of emptiness.
"""
function column_type(spec::FieldSpec)
    spec.kind === :flagset && return Set{String}
    spec.kind in (:strlist, :node_names, :institute_names) && return Vector{String}
    return Union{Missing,spec.type}
end

"""
    schema_names(schema) -> Vector{Symbol}

Column names of a schema, in order.
"""
schema_names(schema::Vector{FieldSpec}) = [s.name for s in schema]
