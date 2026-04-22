```@meta
CurrentModule = JASCOFiles
```

# JASCOFiles.jl

```@docs
JASCOFiles
```

JASCOFiles.jl reads the CSV files exported from JASCO spectrometers (FTIR, Raman, and UV-Vis) into a concrete [`JASCOSpectrum`](@ref) struct. Common header fields are surfaced as struct fields; the full raw header is preserved in `s.metadata`. The parser auto-detects the delimiter (comma for FTIR/Raman, tab for V-series UV-Vis) and decodes SHIFT-JIS by default, so the same one-liner loads every file a JASCO instrument produces.

The package is deliberately small: parsing only. There is no analysis code here — downstream packages (fitting, plotting, peak finding) build on top of this struct.

## Installation

```julia
using Pkg
Pkg.add("JASCOFiles")
```

## At a glance

```julia
using JASCOFiles

s = JASCOSpectrum("sample.csv")

s.datatype   # e.g. "INFRARED SPECTRUM", "RAMAN SPECTRUM", "UV/VIS SPECTRUM" or ""
s.x          # Vector{Float64} of wavenumbers or wavelengths
s.y          # Vector{Float64} of absorbance or intensity
s.xunits     # e.g. "1/CM", "NANOMETERS"
s.yunits     # e.g. "ABSORBANCE", "INTENSITY"

isftir(s)    # true if DATA TYPE is INFRARED SPECTRUM
israman(s)   # true if DATA TYPE is RAMAN SPECTRUM
isuvvis(s)   # true if DATA TYPE is UV/VIS SPECTRUM (or a V-series file
             #   with blank DATA TYPE and xunits in NANOMETERS)

s.metadata["NPOINTS"]   # raw header value, always a string
```

See the [Quick start](guide/quickstart.md) for a walkthrough and [File formats](guide/file-formats.md) for per-instrument details, encoding notes, and parser limitations.

## Issues and contributions

If you run into a JASCO file this package mis-parses — especially one from a firmware version or instrument line not yet covered — please open an issue at [github.com/garrekstemo/JASCOFiles.jl/issues](https://github.com/garrekstemo/JASCOFiles.jl/issues). A minimal excerpt of the offending file (sample names can be redacted) is the most helpful thing to attach.
