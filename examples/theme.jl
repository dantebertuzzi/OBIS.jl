# Shared figure theme for the example scripts.
#
# Two categorical hues, validated against both chart surfaces for colour-vision deficiency
# (worst-pair ΔE 24.7 light / 26.8 dark, well clear of the ΔE 8 floor). Identity is never
# carried by colour alone: every figure also has a legend or direct labels.
#
# Included by figures.jl and orcas.jl; not a module, just definitions.

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
end

const LIGHT = Palette(
    "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7",
    "#2a78d6", "#eb6834", "#eeece6", "#f7f7f5",
)
const DARK = Palette(
    "#1a1a19", "#ffffff", "#c3c2b7", "#898781", "#2c2c2a", "#383835",
    "#3987e5", "#d95926", "#26262340", "#212120",
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
