```@meta
CurrentModule = JASCOFiles
```

# File formats

[`JASCOSpectrum`](@ref) reads the CSV exports produced by JASCO's FTIR, Raman, and V-series UV-Vis spectrometers.
All three instruments share the same basic layout, but they differ in delimiter, encoding habits, and which header fields they actually populate.
This page documents what the parser expects, what it fills in when a field is missing, and the known limitations of the current implementation.

## Common structure

Every supported JASCO file follows this layout:

1. A **header** of delimited `KEY<delim>VALUE` pairs, one per line.
2. A **data section** of delimited `x,y` pairs, one per line.
3. A **footer** of further `KEY<delim>VALUE` pairs (measurement settings, operator name, instrument serial number, etc.), separated from the data by a blank line.

The parser captures both the header and the footer into `s.metadata`. See [Footer metadata](#Footer-metadata) below for the section markers it skips and the Japanese→English alias behavior.

## Per-instrument variants

### FTIR

Comma-delimited. `DATA TYPE` is set to `INFRARED SPECTRUM` and `XUNITS` is typically `1/CM`.

```
TITLE,
DATA TYPE,INFRARED SPECTRUM
DATE,23/01/11
TIME,16:49:31
XUNITS,1/CM
YUNITS,ABSORBANCE
XYDATA
999.9101,0.572538
```

### Raman

Also comma-delimited. `DATA TYPE` is `RAMAN SPECTRUM` and `XUNITS` is typically `1/CM` (Raman shift).

```
TITLE,C1
DATA TYPE,RAMAN SPECTRUM
DATE,24/11/05
XUNITS,1/CM
YUNITS,INTENSITY
XYDATA
545.8049,199
```

### UV-Vis (V-series, e.g. V-730)

**Tab-delimited**, and `DATA TYPE` is emitted **blank**. `XUNITS` is `NANOMETERS`.

```
TITLE<TAB>
DATA TYPE<TAB>
DATE<TAB>26/02/12
SPECTROMETER/DATA SYSTEM<TAB>JASCO Corp., V-730, Rev. 1.00
XUNITS<TAB>NANOMETERS
YUNITS<TAB>ABSORBANCE
XYDATA
1000<TAB>-0.0983645
```

Because `DATA TYPE` is blank, UV-Vis files cannot be recognised by the string `"UV/VIS SPECTRUM"` alone — see [UV-Vis classification](#UV-Vis-classification) below.

## Encoding

The default encoding is **SHIFT-JIS**, which is what JASCO instruments emit natively. This is necessary for the Japanese metadata keys that appear in some exports, such as `機種名` ("model name"). Pass any `StringEncodings.Encoding` via the `encoding` keyword to override:

```julia
using StringEncodings
s = JASCOSpectrum("sample.csv"; encoding=enc"UTF-8")
```

## Metadata fields

Header and footer entries are both stored in `s.metadata::Dict{String,Any}`. A handful of header keys are also given dedicated struct fields:

| Header key                 | Struct field        | Notes                                              |
|----------------------------|---------------------|----------------------------------------------------|
| `TITLE`                    | `s.title`           |                                                    |
| `DATE` + `TIME`            | `s.date`            | Parsed as a single `DateTime`; see below           |
| `SPECTROMETER/DATA SYSTEM` | `s.spectrometer`    | Falls back to `機種名` if the English key is absent |
| `DATA TYPE`                | `s.datatype`        | Blank on V-series UV-Vis                           |
| `XUNITS`                   | `s.xunits`          |                                                    |
| `YUNITS`                   | `s.yunits`          |                                                    |

The following keys are common but are left in `s.metadata` only — they are not promoted to struct fields:

| Header key    | Typical value                          |
|---------------|----------------------------------------|
| `ORIGIN`      | `JASCO`                                |
| `OWNER`       | Operator name (often blank)            |
| `LOCALE`      | Windows LCID (e.g. `1041` = Japanese)  |
| `FIRSTX`      | First x value as a string              |
| `LASTX`       | Last x value                           |
| `NPOINTS`     | Number of data points                  |
| `DELTAX`      | X-step size (sign indicates direction) |
| `RESOLUTION`  | Instrument resolution (often blank)    |
| `FIRSTY`, `MAXY`, `MINY` | Y summary statistics        |

All values are stored as the raw `String` read from the file.

## Missing-field defaults

To make every [`JASCOSpectrum`](@ref) field have a definite value, missing header keys fall back to placeholder values rather than `missing`:

| Struct field      | Default when key is missing |
|-------------------|-----------------------------|
| `title`           | `"Untitled"`                |
| `spectrometer`    | `"Unknown"`                 |
| `datatype`        | `"Unknown"`                 |
| `xunits`          | `"cm-1"`                    |
| `yunits`          | `"Abs"`                     |
| `date`            | `DateTime(2000)`            |

Check `haskey(s.metadata, "RESOLUTION")` when you need to distinguish a genuinely recorded value from a missing one.

## Date format

JASCO writes `DATE` as `yy/mm/dd` and `TIME` as `HH:MM:SS`. The parser concatenates them and prepends `"20"` to form a four-digit year before parsing with `dateformat"yy/mm/ddTHH:MM:SS"`.

## UV-Vis classification

Because V-series UV-Vis exports leave `DATA TYPE` blank, a simple string compare against `"UV/VIS SPECTRUM"` is not enough. [`isuvvis`](@ref) uses a small heuristic:

1. If `s.datatype == "UV/VIS SPECTRUM"`, return `true` immediately.
2. Otherwise, if `s.datatype` is non-empty, return `false` (it is a different instrument).
3. If `s.datatype` is blank, require `s.xunits == "NANOMETERS"` **and** the full wavelength range to fall within `100 ≤ x ≤ 3500` nm.

The wavelength window is deliberately wider than the visible range so that UV-Vis/NIR extensions are still recognised, but narrow enough to exclude IR data that happens to be expressed in other units. A file with blank `DATA TYPE` and `XUNITS = "1/CM"` will not be classified as UV-Vis.

[`isftir`](@ref) and [`israman`](@ref) are strict string matches against `"INFRARED SPECTRUM"` and `"RAMAN SPECTRUM"` respectively and do not need a heuristic.

## Footer metadata

JASCO exports include a second metadata block after the data section. The parser detects it by the **blank line** that separates it from the data, and captures every `KEY<delim>VALUE` row it finds there into `s.metadata` alongside the header keys.

Footer information:

- **FTIR** footers typically include detector type, integration count, resolution, apodization, zero-filling, scan speed, gain, aperture, and light source.
- **Raman** footers often include acquisition settings like laser wavelength, laser power, grating, slit, objective lens, CCD temperature, and the rejection filter.
- **V-series UV-Vis** footers include a `[測定情報]` ("measurement information") section with model name, serial number, photometric mode, bandwidth, response, scan speed, and light source, often followed by a `[付属品情報]` ("accessory information") section.

### Section markers and decorations

Footer blocks frequently include bracketed section headers like `[測定情報]`, `[コメント情報]`, `[データ情報]`, and `[付属品情報]`. JASCO FTIR exports also prefix the footer with a literal `##### Extended Information` line. None of these decorations are stored — only the actual `KEY<delim>VALUE` rows are kept.

### Japanese→English aliases

JASCO FTIR and V-series UV-Vis exports use Japanese keys in the footer (e.g. `積算回数`, `光源`, `検出器`). By default the parser preserves the original Japanese key and adds an English-aliased entry resolving to the same value:

```julia-repl
julia> s = JASCOSpectrum("ftir.csv");

julia> s.metadata["積算回数"]
"16"

julia> s.metadata["Accumulation"]
"16"
```

A small set of Japanese values is also translated. For example, `光源 = 標準光源` becomes:

```julia-repl
julia> s.metadata["光源"]
"Standard light source"

julia> s.metadata["Light source"]
"Standard light source"
```

Pass `translate=false` to disable both translations and keep only the originals:

```julia
s = JASCOSpectrum("ftir.csv"; translate=false)
s.metadata["光源"]                   # "標準光源"
haskey(s.metadata, "Light source")  # false
```

If you encounter a Japanese term that isn't yet mapped, a PR adding an entry is welcome.
