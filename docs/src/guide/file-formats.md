```@meta
CurrentModule = JASCOFiles
```

# File formats

[`JASCOSpectrum`](@ref) reads the CSV exports produced by JASCO's FTIR, Raman, and V-series UV-Vis spectrometers.
All three instruments share the same basic layout, but they differ in delimiter, encoding habits, and which header fields they actually populate.
This page documents what the parser expects, what it fills in when a field is missing, and the known limitations of the current implementation.

For usage, see [Quick start](quickstart.md).

## Common structure

Every supported JASCO file follows the same three-part layout:

1. A **header** of delimited `KEY<delim>VALUE` pairs (one per line).
2. A literal `XYDATA` marker on its own line.
3. A **data section** of delimited `x,y` pairs, one per line.

Some instruments also emit a **footer** of free-form metadata after the data block (measurement settings, operator name, etc.).
The parser currently stops capturing metadata after `XYDATA`: any line in the data section that fails to parse as two floats is silently skipped, and footer metadata is **not** recorded. This is a known limitation — see [Footer metadata](#Footer-metadata) below.

## Per-instrument variants

### FTIR

Comma-delimited. `DATA TYPE` is set to `INFRARED SPECTRUM` and `XUNITS` is typically `1/CM`.

```
TITLE,                               # comma
DATA TYPE,INFRARED SPECTRUM          # comma
DATE,23/01/11                        # comma
TIME,16:49:31                        # comma
XUNITS,1/CM                          # comma
YUNITS,ABSORBANCE                    # comma
XYDATA
999.9101,0.572538                    # comma
```

### Raman

Also comma-delimited. `DATA TYPE` is `RAMAN SPECTRUM` and `XUNITS` is typically `1/CM` (Raman shift).

```
TITLE,C1                             # comma
DATA TYPE,RAMAN SPECTRUM             # comma
DATE,24/11/05                        # comma
XUNITS,1/CM                          # comma
YUNITS,INTENSITY                     # comma
XYDATA
545.8049,199                         # comma
```

### UV-Vis (V-series, e.g. V-730)

**Tab-delimited**, and — unlike FTIR and Raman — `DATA TYPE` is emitted **blank**. `XUNITS` is `NANOMETERS`.

```
TITLE<TAB>                           # tab
DATA TYPE<TAB>                       # tab (empty value)
DATE<TAB>26/02/12                    # tab
SPECTROMETER/DATA SYSTEM<TAB>JASCO Corp., V-730, Rev. 1.00
XUNITS<TAB>NANOMETERS                # tab
YUNITS<TAB>ABSORBANCE                # tab
XYDATA
1000<TAB>-0.0983645                  # tab
```

Because `DATA TYPE` is blank, UV-Vis files cannot be recognised by the string `"UV/VIS SPECTRUM"` alone — see [UV-Vis classification](#UV-Vis-classification) below.

## Delimiter auto-detection

The parser inspects the first non-empty line of the file:

- If the line contains a tab, the delimiter is set to `'\t'`.
- Otherwise, if it contains a comma, the delimiter is set to `','`.

Detection runs on the raw line (before stripping) so that header rows with empty values — e.g. `TITLE\t` — still carry the trailing delimiter that identifies the format. The chosen delimiter is then used for every subsequent header and data line.

## Encoding

The default encoding is **SHIFT-JIS**, which is what JASCO instruments emit natively. This is necessary for the Japanese metadata keys that appear in some exports, such as `機種名` ("model name"). Pass any `StringEncodings.Encoding` via the `encoding` keyword to override:

```julia
using StringEncodings
s = JASCOSpectrum("sample.csv"; encoding=enc"UTF-8")
```

## Metadata fields

The header is stored verbatim in `s.metadata::Dict{String,Any}`. A handful of keys are also hoisted into dedicated struct fields:

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

All values are stored as the raw `String` read from the file — the parser does not coerce them to numeric types.

## Missing-field defaults

To keep [`JASCOSpectrum`](@ref) concretely typed, missing header keys fall back to sentinel values rather than `missing`:

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

This means the parser only handles files recorded between **2000-01-01 and 2099-12-31**. Files from earlier instruments, or any future file written after 2099, will fail the internal `DateTime` parse and fall back to `DateTime(2000)`. The fallback is silent — inspect `s.metadata["DATE"]` directly if you need the raw value.

## UV-Vis classification

Because V-series UV-Vis exports leave `DATA TYPE` blank, a simple string compare against `"UV/VIS SPECTRUM"` is not enough. [`isuvvis`](@ref) uses a small heuristic:

1. If `s.datatype == "UV/VIS SPECTRUM"`, return `true` immediately.
2. Otherwise, if `s.datatype` is non-empty, return `false` (it is a different instrument).
3. If `s.datatype` is blank, require `s.xunits == "NANOMETERS"` **and** the full wavelength range to fall within `100 ≤ x ≤ 3500` nm.

The wavelength window is deliberately wider than the visible range so that UV-Vis/NIR extensions are still recognised, but narrow enough to exclude IR data that happens to be expressed in other units. A file with blank `DATA TYPE` and `XUNITS = "1/CM"` will not be classified as UV-Vis.

[`isftir`](@ref) and [`israman`](@ref) are strict string matches against `"INFRARED SPECTRUM"` and `"RAMAN SPECTRUM"` respectively and do not need a heuristic.

## Footer metadata

Many JASCO exports append a second metadata block after the data section:

- Raman files often include acquisition settings like aperture diameter, rejection filter, and resolution grating.
- V-730 UV-Vis files include a Japanese `[測定情報]` ("measurement information") section with sample name, operator, and the instrument serial number.

The parser currently **ignores everything after the `XYDATA` marker except valid `x,y` float pairs**. Any non-numeric line in the data section is silently skipped (via a caught `ArgumentError` on `parse(Float64, ...)`), so footer blocks do not raise errors but they also do not appear in `s.metadata`. If you need a footer value, reopen the file with the same encoding and read it yourself.

## Japanese metadata

SHIFT-JIS decoding is the default because JASCO instruments sometimes emit keys in Japanese. The most common case is `機種名` ("model name"), which some exports use in place of `SPECTROMETER/DATA SYSTEM`. The parser looks up `機種名` first when populating `s.spectrometer`, and only falls back to the English key if the Japanese one is absent.

Other Japanese keys (operator name, sample description, the `[測定情報]` footer block) are preserved verbatim in `s.metadata` when they appear in the header; they are not specially mapped to struct fields.
