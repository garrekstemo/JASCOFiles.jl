```@meta
CurrentModule = JASCOFiles
```

# JASCOFiles.jl

```@docs
JASCOFiles
```

JASCOFiles.jl reads the CSV files exported from JASCO spectrometers (FTIR, Raman, and UV-Vis) into a [`JASCOSpectrum`](@ref) struct holding the x-axis (wavenumber or wavelength), the y-axis (absorbance, transmittance, or intensity), the recording date, the instrument name, etc. The full raw header is preserved in `s.metadata`.

The parser auto-detects the delimiter (comma for FTIR/Raman, tab for V-series UV-Vis) and decodes Japanese text encoding (SHIFT-JIS) by default, so the same `JASCOSpectrum(path)` call loads every file a JASCO instrument produces.

The package is deliberately small so that it loads quickly. There is no analysis or plotting functionality, but some basic operations are included for convenience, like transforming between absorbance and transmittance using the same assumptions JASCO uses internally.

## Installation

```julia
using Pkg
Pkg.add("JASCOFiles")
```

## Reading a file

Point [`JASCOSpectrum`](@ref) at a CSV exported from a JASCO spectrometer and you get a parsed struct back:

```julia
using JASCOFiles

s = JASCOSpectrum("sample.csv")
```

In the REPL, the spectrum prints a compact summary:

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

## What's in a spectrum

The x- and y-axis data are plain Julia numeric arrays, and the common header fields are available directly on the struct:

```julia
s.x          # wavenumbers, Raman shifts, or wavelengths
s.y          # absorbance, transmittance, or intensity values
s.xunits     # "1/CM", "NANOMETERS", ...
s.yunits     # "ABSORBANCE", "INTENSITY", ...
s.datatype   # "INFRARED SPECTRUM", "RAMAN SPECTRUM", "UV/VIS SPECTRUM", or "" for V-730
s.title      # from the TITLE header field
s.spectrometer
s.date       # DateTime, parsed from DATE + TIME
```

You can also ask how many points the spectrum has with `length(s)`.

## Metadata

Every key/value pair from the file is preserved in `s.metadata`, a `Dict{String, Any}` keyed on the raw key from the file:

```julia
s.metadata["NPOINTS"]     # "12447"
s.metadata["FIRSTX"]      # "999.9101"
s.metadata["LASTX"]       # "7000.335"
s.metadata["RESOLUTION"]  # "4"
```

Values are stored as strings — they aren't converted to numbers automatically. The main header fields (TITLE, DATA TYPE, XUNITS, YUNITS, DATE, TIME, SPECTROMETER/DATA SYSTEM) are already accessible directly on the struct, so is used `metadata` for less common keys like instrument settings (laser power, detector type, integration count, etc.). See [File formats](guide/file-formats.md) for the per-instrument key list.

## Checking the instrument

Three functions check what kind of spectrum is loaded:

```julia
isftir(s)     # true for DATA TYPE == "INFRARED SPECTRUM"
israman(s)    # true for DATA TYPE == "RAMAN SPECTRUM"
isuvvis(s)    # true for DATA TYPE == "UV/VIS SPECTRUM"
```

Use them to branch:

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

## Plotting

`s.x` and `s.y` are plain vectors, so any plotting package works. With Makie:

```julia
using CairoMakie

s = JASCOSpectrum("sample.csv")
fig, ax, l = lines(s.x, s.y;
    axis = (xlabel = s.xunits, ylabel = s.yunits, title = s.title))
fig
```

For FTIR and Raman spectra you can set `ax.xreversed = true` so that wavenumbers decrease to the right, matching the convention used by most instrument software.

## Issues and contributions

If you run into a JASCO file this package mis-parses — especially one from a firmware version or instrument line not yet covered — please open an issue at [github.com/garrekstemo/JASCOFiles.jl/issues](https://github.com/garrekstemo/JASCOFiles.jl/issues). A minimal excerpt of the offending file is the most helpful thing to attach.
