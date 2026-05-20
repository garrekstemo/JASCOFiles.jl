```@meta
CurrentModule = JASCOFiles
```

# Public API

Only exported types and functions are considered part of the public API. Raw header fields not covered by the exposed struct fields are still available through `s.metadata`.

## Index

```@index
Pages = ["public.md"]
```

## Reading files

```@autodocs
Modules = [JASCOFiles]
Pages = ["parser.jl"]
Private = false
```

## Types

```@autodocs
Modules = [JASCOFiles]
Pages = ["types.jl"]
Private = false
```

## Type predicates and Base methods

```@autodocs
Modules = [JASCOFiles]
Pages = ["utils.jl"]
Private = false
```

## Transmittance ↔ absorbance conversions

```@autodocs
Modules = [JASCOFiles]
Pages = ["transforms.jl"]
Private = false
```

## Plotting helpers

`xlabel` and `ylabel` produce nicely formatted axis labels (e.g. `"Wavenumber (cm⁻¹)"`, `"Transmittance (%)"`) from a spectrum's units. They work without any plotting backend loaded.

```@autodocs
Modules = [JASCOFiles]
Pages = ["plotting.jl"]
Private = false
```

## Plotting with Makie

When Makie is loaded, `plot(s)` is available via a package extension. Load a backend first (`using CairoMakie` or `using GLMakie`):

```julia
using JASCOFiles, CairoMakie

s = JASCOSpectrum("sample.csv")
fig, ax, ln = plot(s)
fig, ax, ln = plot(s; color = :tomato)
fig, ax, ln = plot(s; axis = (xreversed = false,))
```

Axis defaults are filled from the spectrum:
- `xlabel` from [`xlabel`](@ref)`(s)`
- `ylabel` from [`ylabel`](@ref)`(s)`
- `title` from `s.title`
- `xreversed = isftir(s)` (standard IR orientation: wavenumber decreases left-to-right)

Pass an `axis` NamedTuple to override any of these. Other keyword arguments are forwarded to `Makie.lines`.

The extension also hooks `Makie.convert_arguments`, so `lines(s)`, `scatter(s)`, and `lines!(ax, s)` work directly without going through `s.x`/`s.y`.
