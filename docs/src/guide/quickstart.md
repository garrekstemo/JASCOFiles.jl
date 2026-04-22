```@meta
CurrentModule = JASCOFiles
```

# Quick start

## Reading a file

Point [`JASCOSpectrum`](@ref) at a CSV exported from a JASCO spectrometer and you get a parsed struct back:

```julia
using JASCOFiles

s = JASCOSpectrum("sample.csv")
```

The parser defaults to SHIFT-JIS decoding, which handles the Japanese metadata keys (e.g. `機種名`) that JASCO instruments sometimes emit. It also auto-detects the delimiter — commas for FTIR/Raman, tabs for V-series UV-Vis — so the same call works for any supported instrument. See [File formats](file-formats.md) for the `encoding` keyword and per-instrument quirks.

In the REPL, the spectrum shows a compact summary:

```julia-repl
julia> s = JASCOSpectrum("ftir.csv")
JASCOSpectrum: INFRARED SPECTRUM
  title:        "My Sample"
  spectrometer: "JASCO FT/IR-4700"
  date:         2023-01-11T16:49:31
  xunits:       1/CM  (12447 points)
  yunits:       ABSORBANCE
  range:        999.9101 → 7000.335
  metadata:     24 keys
```

## Accessing data

The `x` and `y` fields are plain `Vector{Float64}`, so anything that works on a Julia vector works on them directly:

```julia
s.x          # Vector{Float64} of wavenumbers, Raman shifts, or wavelengths
s.y          # Vector{Float64} of absorbance or intensity values
s.xunits     # "1/CM", "NANOMETERS", ...
s.yunits     # "ABSORBANCE", "INTENSITY", ...
s.datatype   # "INFRARED SPECTRUM", "RAMAN SPECTRUM", "UV/VIS SPECTRUM", or "" for V-730
s.title      # from the TITLE header field
s.spectrometer
s.date       # DateTime, parsed from DATE + TIME
```

The struct also implements `length` and `size`, so it behaves like a 1-D container when you only care about the count:

```julia
length(s)    # number of points
size(s)      # (n,)
```

## Metadata

Every key/value pair from the file header is preserved in `s.metadata`, a `Dict{String, Any}` keyed on the raw header string:

```julia
s.metadata["NPOINTS"]     # "12447"
s.metadata["FIRSTX"]      # "999.9101"
s.metadata["LASTX"]       # "7000.335"
s.metadata["RESOLUTION"]  # "4"
```

Values are stored as strings — the parser does not coerce types for metadata, only for the XYDATA block. The most common fields (`TITLE`, `DATA TYPE`, `XUNITS`, `YUNITS`, `DATE`, `TIME`, and `SPECTROMETER/DATA SYSTEM`) are already surfaced as typed struct fields, so reach into `metadata` only for the less-common keys.

## Dispatching on instrument type

Three predicates check what kind of spectrum you loaded:

```julia
isftir(s)     # true for DATA TYPE == "INFRARED SPECTRUM"
israman(s)    # true for DATA TYPE == "RAMAN SPECTRUM"
isuvvis(s)    # true for DATA TYPE == "UV/VIS SPECTRUM"
```

Use them to branch on instrument:

```julia
if isftir(s)
    # wavenumber-domain analysis
elseif israman(s)
    # Raman-shift analysis
end
```

or to filter a collection:

```julia
ftir_only = filter(isftir, spectra)
```

[`isuvvis`](@ref) has an extra heuristic: some JASCO instruments (notably the V-730) export files with a blank `DATA TYPE` field. When that happens, the spectrum is classified as UV-Vis if `xunits == "NANOMETERS"` and the wavelength range falls inside 100–3500 nm. [File formats](file-formats.md) covers the detection logic in full.

## Plotting

`s.x` and `s.y` are plain vectors, so any plotting package works. With Makie:

```julia
using CairoMakie

s = JASCOSpectrum("sample.csv")
fig, ax, _ = lines(s.x, s.y;
    axis = (xlabel = s.xunits, ylabel = s.yunits, title = s.title))
fig
```

For FTIR and Raman spectra you will usually want `ax.xreversed = true` so that wavenumbers decrease to the right, matching the convention used by most instrument software.
