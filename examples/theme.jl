# Shared figure theme for the example scripts.
#
# Two categorical hues, validated against both chart surfaces for colour-vision deficiency
# (worst-pair ΔE 24.7 light / 26.8 dark, well clear of the ΔE 8 floor). Identity is never
# carried by colour alone: every figure also has a legend or direct labels.
#
# `seq` and `div` are the value scales the maps in brazil.jl need. A sequential ramp is one
# hue, ordered so that "near zero" sits nearest the surface — light-to-dark on the light
# surface, dark-to-light on the dark one, which is why the dark ramp is stepped rather than
# flipped wholesale. A diverging ramp is two hues around a neutral grey midpoint, so that
# "no departure" reads as nothing rather than as a colour. Both are checked for lightness
# monotonicity, which is the check that applies to a value scale; the categorical ΔE gates
# are not the right test for one.
#
# Included by figures.jl, orcas.jl and brazil.jl; not a module, just definitions.

struct Palette
    surface::String
    ink::String
    ink2::String
    muted::String
    grid::String
    axis::String
    series1::String
    series2::String
    land::String
    sea::String
    # Opaque land, for maps where filled cells are drawn underneath it: the translucent
    # `land` above would let the data show through and read as a value.
    landfill::String
    # Value scales: one hue for magnitude, two hues around a neutral for polarity.
    seq::Vector{String}
    div::Vector{String}
end

const LIGHT = Palette(
    "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7",
    "#2a78d6", "#eb6834", "#eeece6", "#f7f7f5", "#eeece6",
    ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf", "#184f95", "#0d366b"],
    ["#752322", "#d2383a", "#f9aaa3", "#f0efec", "#9ec5f4", "#2a78d6", "#104281"],
)
const DARK = Palette(
    "#1a1a19", "#ffffff", "#c3c2b7", "#898781", "#2c2c2a", "#383835",
    "#3987e5", "#d95926", "#26262340", "#212120", "#262623",
    ["#0d366b", "#184f95", "#256abf", "#3987e5", "#6da7ec", "#9ec5f4", "#cde2fb"],
    ["#f9aaa3", "#e34948", "#a92126", "#383835", "#1c5cab", "#3987e5", "#9ec5f4"],
)

function theme_for(p::Palette)
    return Theme(;
        backgroundcolor=p.surface,
        textcolor=p.ink,
        fontsize=13,
        figure_padding=18,
        Axis=(
            backgroundcolor=p.surface,
            xgridcolor=p.grid,
            ygridcolor=p.grid,
            xgridwidth=1,
            ygridwidth=1,
            leftspinevisible=false,
            rightspinevisible=false,
            topspinevisible=false,
            bottomspinecolor=p.axis,
            xtickcolor=p.muted,
            ytickcolor=p.muted,
            xticklabelcolor=p.ink2,
            yticklabelcolor=p.ink2,
            xlabelcolor=p.ink2,
            ylabelcolor=p.ink2,
            titlecolor=p.ink,
            titlealign=:left,
            titlesize=15,
            subtitlecolor=p.ink2,
            subtitlesize=12,
            subtitlegap=6,
        ),
        Legend=(
            framevisible=false,
            labelcolor=p.ink2,
            labelsize=12,
            patchsize=(12, 12),
        ),
    )
end

save_both(name, build) =
    for (suffix, p) in (("", LIGHT), ("-dark", DARK))
        with_theme(theme_for(p)) do
            fig = build(p)
            path = joinpath(OUT, string(name, suffix, ".png"))
            save(path, fig; px_per_unit=2)
            println("  wrote ", relpath(path, dirname(@__DIR__)))
        end
    end
