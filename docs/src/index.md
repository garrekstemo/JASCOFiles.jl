```@meta
CurrentModule = JASCOFiles
```

# JASCOFiles.jl

```@docs
JASCOFiles
```

JASCOFiles.jl reads JASCO spectrometer files (FTIR, Raman, and UV-Vis) into a [`JASCOSpectrum`](@ref) struct holding the x-axis (wavenumber or wavelength), the y-axis (absorbance, transmittance, or intensity), the recording date, the instrument name, etc. The full raw header is preserved in `s.metadata`. Three file families are supported through the single `JASCOSpectrum(path)` entry point: CSV/text exports, the modern binary `.jws`/`.jrs` format, and the legacy OLE-container `.jws` format written by Spectra Manager 1.x (including Raman files with non-linear CCD axes).

The parser auto-detects the delimiter (comma for FTIR/Raman, tab for V-series UV-Vis) and decodes Japanese text encoding (SHIFT-JIS) by default, so the same `JASCOSpectrum(path)` call loads every file a JASCO instrument produces.

The package is deliberately small so that it loads quickly. Some basic operations are included for convenience, like transforming between absorbance and transmittance, or plotting a spectrum in one line when Makie is loaded.

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
s.date       # DateTime parsed from DATE + TIME, or nothing if the file has none
```

Header fields that are missing from the file are empty strings, and a
missing or unparseable timestamp gives `s.date === nothing` — the struct
never fabricates placeholder values. The number of points is `length(s.x)`.

## Building and modifying spectra

Spectra can be constructed directly with keywords (only `x` and `y` are
required), and copied with selected fields replaced:

```julia
s = JASCOSpectrum(x=[400.0, 401.0], y=[0.1, 0.2], yunits="ABSORBANCE")
s2 = JASCOSpectrum(s; title="renamed")            # copy, new title
s3 = JASCOSpectrum(s; y=s.y .* 2, yunits="")      # copy, new data
```

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

With Makie loaded, you can plot a spectrum in one line:

```julia
using JASCOFiles, CairoMakie

s = JASCOSpectrum("sample.csv")
fig, ax, ln = plot(s)
fig
```

`plot(s)` fills in the axis labels and title from `s`, and reverses the x-axis for FTIR so wavenumbers decrease left-to-right (the convention used by most instrument software). Override any default via an `axis` NamedTuple; other keyword arguments are forwarded to Makie's `lines`:

```julia
plot(s; color = :tomato)
plot(s; axis = (xreversed = false, title = "My sample"))
```

For full control, `s.x` and `s.y` are plain vectors and `s.xunits`/`s.yunits` are the instrument's unit strings, so any plotting package works. JASCOFiles is a pure reader and ships no conversions or axis-label helpers — use [OpticalSpectroscopy.jl](https://github.com/garrekstemo/OpticalSpectroscopy.jl) for transmittance↔absorbance and formatted axis labels:

```julia
fig, ax, ln = lines(s.x, s.y; axis = (title = s.title,))
```

## DataFrames and CSV

A `JASCOSpectrum` plugs into the [Tables.jl](https://github.com/JuliaData/Tables.jl) ecosystem with `:x` and `:y` columns. `DataFrame`, `CSV.write`, `Arrow.write`, and other Tables consumers work directly:

```julia
using JASCOFiles, DataFrames

s = JASCOSpectrum("sample.csv")
df = DataFrame(s)            # columns :x and :y
```

```julia
using JASCOFiles, CSV

CSV.write("sample_xy.csv", JASCOSpectrum("sample.csv"))
```

You never need to `using Tables` yourself — DataFrames, CSV, and friends pull it in transitively, and the package extension loads as soon as both `JASCOFiles` and a Tables consumer are in the same session.

For labelled headers when exporting, rename after conversion:

```julia
df = rename!(DataFrame(s), :x => :wavenumber, :y => :absorbance)
CSV.write("sample_named.csv", df)
```

## Issues and contributions

If you run into a JASCO file this package mis-parses — especially one from a firmware version or instrument line not yet covered — please open an issue at [github.com/garrekstemo/JASCOFiles.jl/issues](https://github.com/garrekstemo/JASCOFiles.jl/issues). A minimal excerpt of the offending file is the most helpful thing to attach.
