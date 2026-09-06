# Licence normalization.
#
# OBIS reports a dataset's licence as free prose in `intellectualrights`, not as a code. A
# single 216-dataset query returned nine distinct spellings of what are essentially three
# licences, differing in whether the version sits inside or outside the parentheses, in
# doubled whitespace, and in two entries that are bare words rather than licence names. The
# full corpus contains 63 distinct strings.
#
# So the text is normalized to an identifier where it can be recognized, and the original
# is always kept. Text that is not recognized becomes `"unknown"` rather than a guess:
# among the observed values are `Restricted` and a share-alike licence that is not one of
# the three OBIS accepts, and quietly filing those under a permissive default would be the
# one failure mode with real consequences for a user deciding whether they may redistribute.

"""
    LICENSE_URLS

Canonical URL for each licence identifier the package recognizes.
"""
const LICENSE_URLS = Dict(
    "CC0-1.0" => "https://creativecommons.org/publicdomain/zero/1.0/",
    "CC-BY-4.0" => "https://creativecommons.org/licenses/by/4.0/",
    "CC-BY-NC-4.0" => "https://creativecommons.org/licenses/by-nc/4.0/",
    "CC-BY-SA-4.0" => "https://creativecommons.org/licenses/by-sa/4.0/",
)

"""
    ACCEPTED_LICENSES

The three licences the OBIS data policy accepts for published datasets.

Anything else in a result is either an older record, a provider error, or a licence OBIS
does not endorse, and is worth the caller's attention.
"""
const ACCEPTED_LICENSES = ("CC0-1.0", "CC-BY-4.0", "CC-BY-NC-4.0")

"""
    normalize_license(text) -> String

Derive a licence identifier from the free-text rights statement OBIS publishes.

Returns one of `"CC0-1.0"`, `"CC-BY-4.0"`, `"CC-BY-NC-4.0"`, `"CC-BY-SA-4.0"`, or
`"unknown"`. Both prose statements and licence URLs are accepted, so a value taken from the
API and one taken from the export's licence table normalize the same way.

Non-commercial is tested before attribution: every `CC-BY-NC` statement also contains the
word "Attribution", so the looser test would swallow the stricter licence.

```jldoctest
julia> OBIS.normalize_license("This work is licensed under a  Creative Commons Attribution (CC-BY) 4.0 License")
"CC-BY-4.0"

julia> OBIS.normalize_license("This work is licensed under a  Creative Commons Attribution Non Commercial (CC-BY-NC) 4.0 License")
"CC-BY-NC-4.0"

julia> OBIS.normalize_license("http://creativecommons.org/publicdomain/zero/1.0/legalcode")
"CC0-1.0"

julia> OBIS.normalize_license("Restricted")
"unknown"
```
"""
function normalize_license(text)
    (text === nothing || text === missing) && return "unknown"
    s = lowercase(String(string(text)))
    isempty(strip(s)) && return "unknown"

    # URLs are unambiguous, so they decide first.
    occursin("publicdomain/zero", s) && return "CC0-1.0"
    occursin("licenses/by-nc-sa", s) && return "unknown"   # not an OBIS licence; do not guess
    occursin("licenses/by-nc", s) && return "CC-BY-NC-4.0"
    occursin("licenses/by-sa", s) && return "CC-BY-SA-4.0"
    occursin("licenses/by/", s) && return "CC-BY-4.0"

    # Prose. Public-domain dedications first, since they mention no attribution at all.
    if occursin("cc0", s) ||
        occursin("public domain", s) ||
        occursin("waived all rights", s)
        return "CC0-1.0"
    end

    is_nc =
        occursin("non commercial", s) ||
        occursin("noncommercial", s) ||
        occursin("non-commercial", s) ||
        occursin("by-nc", s) ||
        occursin("by nc", s)
    is_sa = occursin("sharealike", s) || occursin("share alike", s) || occursin("by-sa", s)

    is_nc && return "CC-BY-NC-4.0"
    is_sa && return "CC-BY-SA-4.0"

    if occursin("attribution", s) || occursin("cc-by", s) || occursin("cc by", s)
        return "CC-BY-4.0"
    end

    return "unknown"
end

"""
    license_url(id) -> Union{Missing,String}

Canonical URL for a licence identifier, or `missing` when it is not recognized.

```jldoctest
julia> OBIS.license_url("CC-BY-NC-4.0")
"https://creativecommons.org/licenses/by-nc/4.0/"

julia> OBIS.license_url("unknown")
missing
```
"""
license_url(id::AbstractString) = get(LICENSE_URLS, String(id), missing)
license_url(::Missing) = missing

"""
    permits_redistribution(id) -> Bool

Whether a licence allows redistributing the data at all.

True for every recognized Creative Commons licence here. It is false for `"unknown"`,
because an unidentifiable rights statement is not permission — the observed unknowns
include the literal string `Restricted`.
"""
permits_redistribution(id) = String(string(id)) in keys(LICENSE_URLS)

"""
    permits_commercial_use(id) -> Bool

Whether a licence permits commercial reuse.

False for `CC-BY-NC-4.0` and for `"unknown"`. A result set containing even one
non-commercial dataset cannot be redistributed commercially as a whole, which is why
[`licenses`](@ref) reports the mix rather than a single verdict.
"""
function permits_commercial_use(id)
    s = String(string(id))
    return s in ("CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0")
end

"""
    requires_attribution(id) -> Bool

Whether a licence requires the data provider to be credited.

False only for `CC0-1.0`, the one licence here that waives the requirement. `"unknown"`
counts as requiring attribution: an unidentifiable rights statement is not evidence that
attribution was waived, and treating it as such is exactly the permissive guess the rest of
this file avoids.

This describes the legal obligation. The OBIS data policy asks that providers be credited
regardless of licence, so `false` is not advice to omit the credit.

```jldoctest
julia> OBIS.requires_attribution("CC0-1.0")
false

julia> OBIS.requires_attribution("CC-BY-4.0")
true

julia> OBIS.requires_attribution("unknown")
true
```
"""
requires_attribution(id) = String(string(id)) != "CC0-1.0"
