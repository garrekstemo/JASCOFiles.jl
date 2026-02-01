# JASCOFiles.jl

[![CI](https://github.com/garrekstemo/JASCOFiles.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/garrekstemo/JASCOFiles.jl/actions/workflows/CI.yml)
[![docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://garrekstemo.github.io/JASCOFiles.jl/dev/)

JASCOFiles.jl reads CSV files exported from JASCO spectrometers (FTIR, Raman, UV-Vis).
It does not read .jws files directly—export raw data to CSV from the JASCO software.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/garrekstemo/JASCOFiles.jl")
```

## Usage

```julia
using JASCOFiles

# Load a spectrum (works for FTIR, Raman, or UV-Vis)
s = Spectrum("path/to/spectrum.csv")

# Access data
s.x        # wavenumber or wavelength
s.y        # absorbance, intensity, etc.
s.xunits   # "1/CM", "nm", etc.
s.yunits   # "ABSORBANCE", "INTENSITY", etc.
s.datatype # "INFRARED SPECTRUM", "RAMAN SPECTRUM", etc.

# Type predicates for dispatch
isftir(s)   # true if FTIR spectrum
israman(s)  # true if Raman spectrum
isuvvis(s)  # true if UV-Vis spectrum

# All metadata from the file header
s.metadata["NPOINTS"]
s.metadata["FIRSTX"]
```

## Supported Instruments

| Instrument | `datatype` field | Status |
|------------|------------------|--------|
| FTIR | `"INFRARED SPECTRUM"` | Supported |
| Raman | `"RAMAN SPECTRUM"` | Supported |
| UV-Vis | `"UV/VIS SPECTRUM"` | Planned |
