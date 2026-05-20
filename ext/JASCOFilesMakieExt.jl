module JASCOFilesMakieExt

using JASCOFiles
using Makie

# Enable `lines(s)`, `scatter(s)`, `lines!(ax, s)`, etc. `PointBased` is a
# Makie conversion-trait singleton; matching on the instance covers every
# plot type whose conversion_trait is PointBased() (Lines, Scatter, etc.).
function Makie.convert_arguments(t::Makie.PointBased, s::JASCOSpectrum)
    return Makie.convert_arguments(t, s.x, s.y)
end

"""
    plot(s::JASCOSpectrum; axis=NamedTuple(), kwargs...)

Plot a JASCO spectrum with axis labels and orientation chosen from `s`.
Available when Makie is loaded; load a backend (`using CairoMakie` or
`using GLMakie`) first. Returns a `FigureAxisPlot` that destructures into
`(figure, axis, plot)`.

Axis defaults:
- `xlabel` from `xlabel(s)`
- `ylabel` from `ylabel(s)`
- `title`  from `s.title`
- `xreversed = isftir(s)` (standard IR orientation: wavenumber decreases
  left-to-right)

Pass an `axis` NamedTuple to override any of these. Extra keyword arguments
are forwarded to `Makie.lines` (e.g. `color`, `linewidth`).

```julia
using JASCOFiles, CairoMakie

s = JASCOSpectrum("sample.csv")
fig, ax, ln = plot(s)
fig, ax, ln = plot(s; color = :tomato)
fig, ax, ln = plot(s; axis = (xreversed = false,))
```
"""
function Makie.plot(s::JASCOSpectrum;
                    axis::NamedTuple = NamedTuple(),
                    kwargs...)
    default_axis = (
        xlabel    = JASCOFiles.xlabel(s),
        ylabel    = JASCOFiles.ylabel(s),
        title     = s.title,
        xreversed = JASCOFiles.isftir(s),
    )
    return Makie.lines(s.x, s.y;
        axis = merge(default_axis, axis),
        kwargs...,
    )
end

end # module
