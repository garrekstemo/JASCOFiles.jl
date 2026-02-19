# JASCOFiles.jl

Julia package for reading JASCO spectrometer CSV files.

## Package Structure

```
src/
├── JASCOFiles.jl    # Module definition and exports
├── types.jl         # AbstractJASCOSpectrum and JASCOSpectrum struct
├── parser.jl        # File parsing logic
└── utils.jl         # Base method extensions and type predicates

test/
├── runtests.jl      # Test suite
└── data/            # Test data files
    ├── ftir_test.csv
    ├── ftir_malformed.csv
    ├── raman_test.csv
    └── raman_malformed.csv
```

## Type Hierarchy

```julia
abstract type AbstractJASCOSpectrum end

struct JASCOSpectrum <: AbstractJASCOSpectrum
    title::String
    date::DateTime
    spectrometer::String
    datatype::String
    xunits::String
    yunits::String
    x::Vector{Float64}
    y::Vector{Float64}
    metadata::Dict{String,Any}
end
```

## Public API

- `JASCOSpectrum(path; encoding=enc"SHIFT-JIS")` - Parse a JASCO CSV file
- `read_spectrum(path; kwargs...)` - Alias for JASCOSpectrum constructor
- `isftir(s)` - Returns `true` if spectrum is FTIR
- `israman(s)` - Returns `true` if spectrum is Raman
- `isuvvis(s)` - Returns `true` if spectrum is UV-Vis

## JASCO File Format

All JASCO spectrometer CSV files share a common structure:

1. **Header section**: Comma-separated key-value metadata pairs
2. **XYDATA marker**: Literal line containing "XYDATA"
3. **Data section**: Comma-separated x,y coordinate pairs

Common metadata fields:
- `TITLE`, `DATA TYPE`, `ORIGIN`, `DATE`, `TIME`
- `SPECTROMETER/DATA SYSTEM`, `XUNITS`, `YUNITS`
- `FIRSTX`, `LASTX`, `NPOINTS`

Encoding: SHIFT-JIS (Japanese character support)

## Supported Instruments

| Instrument | DATA TYPE field | Status |
|------------|-----------------|--------|
| FTIR | INFRARED SPECTRUM | Implemented |
| Raman | RAMAN SPECTRUM | Implemented |
| UV-Vis | UV/VIS SPECTRUM | Planned |

## Development

```julia
julia --project=.
using Revise, JASCOFiles
```

Run tests:
```julia
using Pkg; Pkg.test()
```

## Dependencies

- `Dates` (stdlib)
- `StringEncodings` - SHIFT-JIS encoding support
