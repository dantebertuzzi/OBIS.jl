using Aqua

# Aqua checks the things that are easy to get wrong and hard to notice: method ambiguities,
# undefined exports, stale dependencies, and compat entries that drift out of date.
Aqua.test_all(OceanBIS; ambiguities=false)

# Ambiguities are checked against this package alone; testing recursively would report
# ambiguities in dependencies, which are not this package's to fix.
@testset "no ambiguities within OBIS" begin
    Aqua.test_ambiguities(OceanBIS)
end
