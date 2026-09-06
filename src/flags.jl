# Quality control flags.
#
# The API stores flags in upper case and matches them case-sensitively. A lower-case flag
# is not an error: `flags=on_land` returns zero records and `exclude=on_land` applies no
# filter at all, both with HTTP 200. Since the OBIS manual displays flags in lower case,
# the wrong case is easy to write and impossible to notice. Normalizing here is what makes
# either spelling safe.

"""
    KNOWN_FLAGS

Quality flags documented by the OBIS QC pipeline, together with flags observed live that
the pipeline reference does not list.

The vocabulary is open: OBIS adds checks over time, and the `/facet` endpoint truncates
its flag listing, so this set cannot be treated as exhaustive. Unrecognized upper-case
flags are passed through with a warning rather than rejected.
"""
const KNOWN_FLAGS = Set([
    # Coordinates. All of these drop the record from the main index.
    "NO_COORD",
    "ZERO_COORD",
    "LON_OUT_OF_RANGE",
    "LAT_OUT_OF_RANGE",
    # Taxonomy.
    "NO_MATCH",              # drops the record
    "NOT_MARINE",            # drops the record
    "NO_ACCEPTED_NAME",
    "MARINE_UNSURE",
    "SCIENTIFICNAMEID_EXTERNAL",
    # Geography.
    "ON_LAND",
    # Depth.
    "NO_DEPTH",
    "MIN_DEPTH_EXCEEDS_MAX",
    "DEPTH_EXCEEDS_BATH",
    "DEPTH_OUT_OF_RANGE",
    # Dates.
    "DATE_IN_FUTURE",
    "DATE_BEFORE_MIN",
    # WoRMS name annotations, surfaced through the same field as QC flags.
    "WORMS_ANNOTATION_RESOLVABLE",
    "WORMS_ANNOTATION_RESOLVABLE_LOSS",
    "WORMS_ANNOTATION_UNRESOLVABLE",
    "WORMS_ANNOTATION_AWAIT_EDITOR",
    "WORMS_ANNOTATION_TODO",
    "WORMS_ANNOTATION_REJECT_AMBIGUOUS",
    "WORMS_ANNOTATION_REJECT_HABITAT",
])

"""
    DROPPING_FLAGS

Flags whose presence causes OBIS to drop a record from the main index.

Records carrying these are reachable only with `dropped = :only` or `dropped = :include`,
because a dropped record is excluded from every default query and from the bulk exports.
"""
const DROPPING_FLAGS = Set([
    "NO_COORD", "ZERO_COORD", "LON_OUT_OF_RANGE", "LAT_OUT_OF_RANGE", "NO_MATCH",
    "NOT_MARINE"
])

"""
    normalize_flag(flag) -> String

Return `flag` in the upper-case form the API matches on, warning once if the flag is not
in [`KNOWN_FLAGS`](@ref).

Unknown flags are passed through rather than rejected: OBIS adds quality checks over time,
and a hard allow-list would reject a valid new flag.

```jldoctest
julia> OBIS.normalize_flag("on_land")
"ON_LAND"

julia> OBIS.normalize_flag(:no_depth)
"NO_DEPTH"
```
"""
function normalize_flag(flag)
    s = uppercase(strip(String(string(flag))))
    isempty(s) && throw(
        OBISValidationError(:flags, flag, "A quality flag must not be empty.")
    )
    if !(s in KNOWN_FLAGS)
        @warn """
        Unrecognized OBIS quality flag $(repr(s)); sending it unchanged.
        If this is a typo the API will not report it: an unmatched `flags` value returns \
        zero records, and an unmatched `exclude` value applies no filter. Known flags are \
        in `OBIS.KNOWN_FLAGS`.""" _id = Symbol("obis_unknown_flag_", s) maxlog = 1
    end
    return s
end

"""
    normalize_flags(flags) -> Vector{String}

Normalize a flag, or any iterable of flags, into the upper-case forms the API expects.

Accepts a `String`, a `Symbol`, or any iterable of those. A comma-separated string is
split, so both `"ON_LAND,NO_DEPTH"` and `["ON_LAND", "NO_DEPTH"]` work.

```jldoctest
julia> OBIS.normalize_flags(["on_land", :NO_DEPTH])
2-element Vector{String}:
 "ON_LAND"
 "NO_DEPTH"

julia> OBIS.normalize_flags("on_land,no_match")
2-element Vector{String}:
 "ON_LAND"
 "NO_MATCH"
```
"""
normalize_flags(flags::AbstractString) =
    [normalize_flag(f) for f in split(flags, ',') if !isempty(strip(f))]
normalize_flags(flag::Symbol) = [normalize_flag(flag)]
normalize_flags(flags) = [normalize_flag(f) for f in flags]

"""
    drops_record(flag) -> Bool

Whether a record carrying `flag` is dropped from the OBIS main index.

```jldoctest
julia> OBIS.drops_record("NO_MATCH")
true

julia> OBIS.drops_record("on_land")
false
```
"""
drops_record(flag) = uppercase(strip(String(string(flag)))) in DROPPING_FLAGS
