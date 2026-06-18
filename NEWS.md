# JASCOFiles.jl release notes

## 3.0.0

**Breaking — JASCOFiles is now a pure reader.**

Removed from the public API:

- `transmittance_to_absorbance`
- `absorbance_to_transmittance`
- `xlabel`
- `ylabel`

The reader emits raw data plus the instrument's native unit strings
(`xunits`/`yunits`); unit conversions and axis labels belong to the analysis
layer. Migrate:

- Conversions and formatted labels: use OpticalSpectroscopy on a `Spectrum`.
- A quick standalone percent-transmittance → absorbance: `-log10.(s.y ./ 100)`.

The built-in Makie `plot(s)` recipe is unchanged — it still fills axis labels,
title, and `xreversed` from the spectrum.
