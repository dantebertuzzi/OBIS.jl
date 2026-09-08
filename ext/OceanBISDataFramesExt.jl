# DataFrames integration, loaded only when the user already has DataFrames.
#
# `DataFrame(tbl)` works through the Tables.jl interface without this extension. What it
# adds is the part Tables.jl cannot express: flattening the `extra` column, whose contents
# vary per row, into ordinary columns.

module OceanBISDataFramesExt

using OceanBIS
using DataFrames
using DataFrames: DataAPI
using Tables

# OBIS does not export `nrow`/`ncol`, because DataFrames exports the same names and having
# both in scope would make every call site ambiguous. Extending the DataAPI generics here
# means that a user who has loaded DataFrames can write `nrow(tbl)` on an OBIS result and
# get the expected answer.
DataAPI.nrow(t::OceanBIS.OBISTable) = OceanBIS.nrow(t)
DataAPI.ncol(t::OceanBIS.OBISTable) = OceanBIS.ncol(t)

"""
    DataFrames.DataFrame(t::OBISTable; flatten_extra = false)

Convert a result to a `DataFrame`.

With `flatten_extra = true`, the non-core Darwin Core fields held in `extra` become
columns of their own, with `missing` where a record did not carry them, and the `extra`
column is dropped. Which columns that produces depends on the query, which is why it is
opt-in: the core schema is stable, the flattened one is not.

```julia
df = DataFrame(OceanBIS.occurrence("Abra alba"; limit = 100); flatten_extra = true)
```
"""
function DataFrames.DataFrame(t::OceanBIS.OBISTable; flatten_extra::Bool=false)
    df = DataFrame(Tables.columntable(t); copycols=false)
    flatten_extra || return df

    names = OceanBIS.extra_names(t)
    isempty(names) && return select!(df, Not(:extra))

    for nm in names
        col = OceanBIS.extra_column(t, nm)
        target = hasproperty(df, nm) ? Symbol("extra_", nm) : nm
        df[!, target] = col
    end
    return select!(df, Not(:extra))
end

end # module
