# JASCOFiles.jl

[![CI](https://github.com/garrekstemo/JASCOFiles.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/garrekstemo/JASCOFiles.jl/actions/workflows/CI.yml)
[![docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://garrekstemo.github.io/JASCOFiles.jl/dev/)
[![codecov](https://codecov.io/gh/garrekstemo/JASCOFiles.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/garrekstemo/JASCOFiles.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![license](https://img.shields.io/github/license/garrekstemo/JASCOFiles.jl)](LICENSE)

JASCOFiles.jl reads CSV files exported from JASCO spectrometers (FTIR, Raman, UV-Vis).
It does not read .jws files directly—export raw data to CSV from the JASCO software.

## Installation

To install JASCOFiles.jl, use the Julia package manager:

```julia
using Pkg
Pkg.add("JASCOFiles")
```

## Usage

```julia
using JASCOFiles

# Load a spectrum (works for FTIR, Raman, or UV-Vis)
s = JASCOSpectrum("path/to/spectrum.csv")

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

# All metadata from header and footer
s.metadata["TIME"]
s.metadata["Accumulation"]
```

## Convenience features

```julia
# Convert between transmittance and absorbance (JASCO's percent-T convention)
t = absorbance_to_transmittance(s)   # yunits → "TRANSMITTANCE"
a = transmittance_to_absorbance(t)   # yunits → "ABS", round-trips back

# Footer keys with Japanese names are also accessible via English aliases
s.metadata["積算回数"]       # "16"
s.metadata["Accumulation"]  # "16"
s.metadata["光源"]           # "Standard light source"
s.metadata["Light source"]  # "Standard light source"
```

## Supported Instruments

| Instrument | `datatype` field |
|------------|------------------|
| FTIR | `"INFRARED SPECTRUM"` |
| Raman | `"RAMAN SPECTRUM"` |
| UV-Vis | `"UV/VIS SPECTRUM"` |

If you have a file from an instrument, firmware version, or file-format variant not covered above, please [open an issue or PR](https://github.com/garrekstemo/JASCOFiles.jl/issues) with a representative file attached.
