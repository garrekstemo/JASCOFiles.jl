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

## Binary files (`.jws` / `.jrs`)

`JASCOSpectrum(path)` also reads JASCO's native binary spectra directly (FTIR and
UV-Vis). Two on-disk formats share one container (`SPECMAN R2.0.0`):

- **`.jws`** — written by the desktop **Spectra Manager** software (header
  stamped `SPECMAN`, `i80x86`, `MSVC`).
- **`.jrs`** — the same spectrum written by the spectrometer's **onboard
  firmware** (`SPECIRM`, `MCF5328`, `CodeWarrior`).

The spectral data is identical between them; only the writer-provenance header
fields differ. Both decode to the same `JASCOSpectrum`.

Little-endian, fixed-offset header, then a trailing `Float32` data block:

| Offset | Type | Field |
|--------|------|-------|
| `0x00` | char[4] | magic `"L~S "` |
| `0x08` | str | format id (`SPECMAN` / `SPECIRM`) |
| `0x84` | Int32 | NPOINTS |
| `0x88`/`0x90`/`0x98` | Float64 | FIRSTX / LASTX / DELTAX (signed) |
| `0xA0` | UInt8 | x-unit code (`0` = cm⁻¹, `3` = nm) |
| `0xA4` | UInt8 | y-mode code (see below) |
| `0xC8` | Int64 | data-block length (= NPOINTS × 4) |
| `0x140` | str | instrument model |
| `0x160` | str | serial number |
| `0x180` | str | title |
| `0x2C0` | Int32 | acquisition time (Unix epoch, UTC) |
| `filesize − len` … EOF | Float32[NPOINTS] | y-data |

`datatype` and `xunits` are decoded from the instrument model (`FT/IR…` →
infrared/`1/CM`; `V-…` → UV-Vis/`NANOMETERS`, with `DATA TYPE` left blank to
match the V-series text export). `yunits` is decoded from the y-mode code:

| `0xA4` | `YUNITS` |
|--------|----------|
| `0x00` | TRANSMITTANCE |
| `0x02` | REFLECTANCE |
| `0x03` | ABSORBANCE |
| `0x08` | INTENSITY (single-beam background) |
| `0x09` / `0x0a` | INTENSITY (single-beam reference / sample) |

Unsupported instruments and unknown y-mode codes throw an `ArgumentError`
naming the file. Timestamps decode as UTC (the stored epoch), unlike the CSV
path which records local time.

## Legacy binary files (Spectra Manager 1.x)

Older Spectra Manager versions wrote `.jws` as an **OLE2 compound document**
(the same container as pre-2007 Microsoft Office files; magic
`D0 CF 11 E0`). `JASCOSpectrum(path)` detects the container from the magic
bytes — the extension is the same, so no caller-side distinction is needed.

Inside the container, named streams hold the data: `DataInfo` (grid:
NPOINTS, FIRSTX/LASTX/DELTAX, axis descriptors), `Y-Data` (`Float32`
values), and optional metadata streams (`SampleInfo`, `UserInfo`,
`ModuleInfo` with instrument model/serial, `MeasParam` acquisition
parameters, `BaseInfo` original path and timestamps). Strings are UTF-16LE
(not Shift-JIS); dates are OLE Automation dates stored in UTC.

Two instrument families are supported:

- **FTIR** (`FT/IR` series): linear grid reconstructed from
  FIRSTX + DELTAX. Acquisition parameters (accumulation, resolution,
  aperture, scan speed, gain, filter, light source, detector) are decoded
  to named metadata keys.
- **Raman** (NRS series): non-linear CCD axis read from an explicit
  `X-Data` stream; `DELTAX` is zero in these files. Acquisition parameters
  are kept as raw `MeasParam.tag<N>` entries because the tag numbering
  differs per instrument family.

JASCO marks invalid points with `-1.18e-38` (−`floatmin(Float32)`); these
pass through unmodified, exactly as JASCO's own CSV exports print them. The
full reverse-engineered layout lives in
`docs/superpowers/specs/2026-06-11-legacy-jws-ole-reader-design.md`,
validated against a 445-file lab corpus with 200+ paired CSV exports.

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

Header fields that are absent from the file stay honest — they are never replaced with fabricated placeholders:

| Struct field      | Value when key is missing |
|-------------------|---------------------------|
| `title`           | `"Untitled"`              |
| `spectrometer`    | `""`                      |
| `datatype`        | `""`                      |
| `xunits`          | `""`                      |
| `yunits`          | `""`                      |
| `date`            | `nothing`                 |

Check `haskey(s.metadata, "RESOLUTION")` when you need to distinguish a genuinely recorded value from a missing one.

## Date format

JASCO usually writes `DATE` as `yy/mm/dd` (some variants use a four-digit year) and `TIME` as `HH:MM:SS`. The parser tries both year forms and returns `nothing` — never a sentinel date — when neither parses.

## Strictness

The data section is validated, not best-effort:

- A row that does not parse as two numbers throws an `ArgumentError` naming the file and the offending line (corruption should be loud, not silently dropped).
- When the header declares `NPOINTS` and that many rows have been read, any further non-blank lines are treated as footer metadata — some exports omit the blank line that normally separates data from footer.
- Header `FIRSTX` and `NPOINTS` are cross-checked against the parsed data (with a one-grid-step tolerance for `FIRSTX`, since headers round it).

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
