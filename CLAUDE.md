# JASCOFiles.jl

Julia package for reading JASCO spectrometer files: the CSV/text exports and the native binary `.jws` / `.jrs` files.

## Package Structure

```
src/
├── JASCOFiles.jl    # Module definition and exports
├── types.jl         # AbstractJASCOSpectrum and JASCOSpectrum struct + constructors
├── parser.jl        # CSV/text reader + magic-byte dispatch for binary formats
├── binary.jl        # Modern .jws/.jrs (SPECMAN/SPECIRM "L~S " flat format)
├── legacy.jl        # Legacy .jws (Spectra Manager 1.x, OLE2/CFB container)
├── transforms.jl    # Unit-aware transmittance ↔ absorbance
└── utils.jl         # Type predicates

test/
├── runtests.jl      # Test suite
└── data/            # Fixtures: CSV/text exports + modern and legacy binaries
```

Format specs live in `docs/superpowers/specs/`: `2026-06-04` (modern flat
format), `2026-06-11` (legacy OLE container, incl. the NRS Raman addendum).

## Type Hierarchy

```julia
abstract type AbstractJASCOSpectrum end

struct JASCOSpectrum <: AbstractJASCOSpectrum
    title::String
    date::Union{DateTime, Nothing}   # nothing when the file has no parseable timestamp
    spectrometer::String             # "" when absent — fields are never fabricated
    datatype::String
    xunits::String
    yunits::String
    x::Vector{Float64}
    y::Vector{Float64}
    metadata::Dict{String,Any}
end
```

## Public API

- `JASCOSpectrum(path; encoding=enc"SHIFT-JIS", translate=true)` - Parse a JASCO file (CSV/text, or binary `.jws`/`.jrs`)
- `JASCOSpectrum(; x, y, kwargs...)` - Keyword constructor (only `x`, `y` required)
- `JASCOSpectrum(s; kwargs...)` - Copy constructor with selected fields replaced
- `isftir(s)` / `israman(s)` / `isuvvis(s)` - Instrument-type predicates
- `transmittance_to_absorbance(s)` - Scale inferred from `yunits` ("TRANSMITTANCE" = %T, "TRANSMITTANCE_FRAC" = 0–1); explicit `percent` overrides; output `yunits = "ABSORBANCE"`
- `absorbance_to_transmittance(s; percent)` - `percent` is a REQUIRED keyword (true → %T)
- `xlabel(s)` / `ylabel(s)` - Formatted axis labels

## JASCO File Format

All JASCO spectrometer files share a common structure:

1. **Header section**: Delimited key-value metadata pairs (comma or tab)
2. **XYDATA marker**: Literal line containing "XYDATA"
3. **Data section**: Delimited x,y coordinate pairs
4. **Optional footer**: Instrument-specific metadata after the data section,
   separated from the data by a blank line. Parsed when present; Japanese keys
   and a small set of Japanese values are translated to English via dual-key
   aliases (e.g. `metadata["積算回数"]` and `metadata["Accumulation"]` both
   resolve to the same value). Pass `translate=false` to disable. Translation
   tables live in `src/translations.jl` and are easy to extend.

Common header metadata fields:
- `TITLE`, `DATA TYPE`, `ORIGIN`, `DATE`, `TIME`
- `SPECTROMETER/DATA SYSTEM`, `XUNITS`, `YUNITS`
- `FIRSTX`, `LASTX`, `NPOINTS`

Common footer metadata fields (English aliases):
- `Sample name`, `Company`, `Operator`, `Creation date`
- `Model Name`, `Serial Number`, `Measurement Date`
- `Light source`, `Detector`, `Accumulation`, `Resolution`
- `Aperture`, `Scan speed`, `Apodization`, `Zero-filling` (FTIR)
- `Laser wavelength`, `Grating`, `Slit`, `CCD temperature` (Raman)
- `Photometric mode`, `UV/Vis bandwidth`, `Response` (UV-Vis)

Encoding: SHIFT-JIS (Japanese character support)

## Supported Instruments

| Instrument | DATA TYPE field | Delimiter | Status |
|------------|-----------------|-----------|--------|
| FTIR | INFRARED SPECTRUM | comma | Implemented |
| Raman | RAMAN SPECTRUM | comma | Implemented |
| UV-Vis | UV/VIS SPECTRUM or blank (V-series) | tab or comma | Implemented |
| FTIR/UV-Vis | (binary) | .jws / .jrs | Implemented (native) |

The parser auto-detects the delimiter from the first header line. V-series
UV-Vis files (e.g. V-730) use tab separators and leave `DATA TYPE` blank;
`isuvvis` infers UV-Vis from `XUNITS == "NANOMETERS"` and wavelength range
when `DATA TYPE` is empty.

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
