# Native `.jws` binary reading

**Date:** 2026-06-04
**Status:** Approved for planning

## Problem

JASCOFiles.jl reads only the CSV files exported from JASCO's Spectra Manager
software. The README states plainly: *"It does not read .jws files directly —
export raw data to CSV from the JASCO software."* That export step is manual,
lossy (it drops to the displayed precision and a fixed metadata subset), and
easy to forget. Users with a folder of raw `.jws` instrument files cannot load
them without round-tripping every one through the Windows GUI.

The `.jws` format is undocumented and proprietary, but it was reverse-engineered
against three FT/IR-4600 absorbance files and validated to byte-level
correctness (point count is triple-redundant in the container; the wavenumber
grid and the recovered spectra match the instrument's known export grid and
known ZIF-62 band positions). Adding a native reader removes the manual export
step for the common case.

## Decision

Teach the existing `JASCOSpectrum(path)` entry point to read `.jws` files
directly, returning the **same `JASCOSpectrum` struct** the CSV path returns.
Everything downstream of the struct — `isftir`/`israman`/`isuvvis`, `xlabel`/
`ylabel`, the Makie and Tables extensions, the transmittance/absorbance
transforms — then works unchanged, because all of it dispatches on the struct,
not on the source format.

Scope this first pass to **FTIR absorbance** files, the only variant we have
samples for. Other variants (Raman/UV-Vis `.jws`, %transmittance / single-beam
/ interferogram y-modes, multi-trace files) are detected and **rejected with a
clear error** rather than guessed at — matching the package's existing
fail-fast philosophy (see `2026-05-29-jascospectrum-validation-design.md`) and
its "send a sample for an unsupported file" model.

## The `.jws` format (SPECMAN R2.0.0)

Little-endian. Fixed-offset header, fixed-width null-terminated string fields,
then a contiguous `Float32` data block that runs to EOF. Fields the reader uses:

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| `0x00` | char[4] | magic `"L~S "` | `4C 7E 53 20` |
| `0x08` | str16 | format id `"SPECMAN"` | |
| `0x20` | str16 | format version `"R2.0.0"` | |
| `0x84` | Int32 | NPOINTS | |
| `0x88` | Float64 | FIRSTX (cm-1) | low-wavenumber end |
| `0x90` | Float64 | LASTX (cm-1) | high-wavenumber end |
| `0x98` | Float64 | DELTAX (cm-1) | 0.482117 on the FT/IR-4600 |
| `0xA0` | bytes[8] | axis-descriptor tag | constant; part of the format signature |
| `0xC0` | Int64 | descriptor code | constant (`8`); part of the signature |
| `0xC8` | Int64 | data-block length (bytes) | `== NPOINTS * 4` |
| `0xE8` | Float32[4] | saved plot-view `[xmax,ymax,xmin,ymin]` | display only — **ignored** |
| `0x140` | str32 | instrument model | e.g. `"FT/IR-4600typeA"` |
| `0x160` | str32 | serial number | |
| `0x180` | str64 | title / sample name | |
| `0x1C0` | str64 | comment | |
| `0x2C0` | Int32 | acquisition time (Unix epoch, UTC) | duplicated at `0x2C4` |
| `filesize - len` .. EOF | Float32[NPOINTS] | y-data | increasing wavenumber; `y[1]` at FIRSTX |

Data offset is computed as `filesize - len(0xC8)` (= `0x740` for the sample
files), not hard-coded. The plot-view block at `0xE8` and the duplicate
timestamp at `0x2C4` are read past but not used. Several additional string and
integer fields exist in the header (e.g. extra `str` slots near `0x240`/`0x260`,
an unidentified constant `Int32` at `0x2C8`); they are placeholders/unknowns in
the sample files and are not mapped.

## Design

### Dispatch (no public API change)

`src/parser.jl` currently *is* the CSV reader:
`JASCOSpectrum(path::AbstractString; encoding=enc"SHIFT-JIS", translate=true)`.

Split it:

- The public `JASCOSpectrum(path; encoding, translate)` becomes a thin
  dispatcher: if `lowercase(splitext(path)[2]) == ".jws"`, call `_read_jws`;
  otherwise call `_read_jasco_csv` (the existing body, renamed, unchanged).
- `encoding` is forwarded to both (the binary string fields are SHIFT-JIS-
  decoded too, so Japanese sample names work). `translate` is meaningful only
  for the CSV footer and is ignored by the binary path.

The struct's auto-generated 9-arg constructor is untouched, and `_read_jws` is a
plain internal function (not a `JASCOSpectrum` method), so no method ambiguity
is introduced and Aqua's ambiguity check stays green.

### Reader (`src/binary.jl`, new)

`_read_jws(path; encoding)`:

1. `read(path)` into a `Vector{UInt8}`.
2. Read the fixed-offset scalars via `reinterpret` and the string fields via a
   `read_cstr(bytes, offset, width, encoding)` helper (null-terminated within a
   fixed width, then `StringEncodings.decode` + strip).
3. Validate (see below).
4. Build `x = FIRSTX .+ DELTAX .* (0:NPOINTS-1)` and
   `y = Float64.(reinterpret(Float32, data_block))`.
5. Return `JASCOSpectrum(title, date, spectrometer, datatype, xunits, yunits,
   x, y, metadata)`.

Offset constants live at the top of `binary.jl` as named values, not magic
numbers in the logic.

### Field mapping

| `JASCOSpectrum` field | Source |
|-----------------------|--------|
| `title` | sample (`0x180`); `"Untitled"` if empty |
| `date` | `unix2datetime(epoch @ 0x2C0)`; `DateTime(2000)` if epoch ≤ 0 |
| `spectrometer` | instrument model (`0x140`) |
| `datatype` | `"INFRARED SPECTRUM"` |
| `xunits` | `"1/CM"` |
| `yunits` | `"ABSORBANCE"` |
| `x` | generated grid (Float64) |
| `y` | Float32 block widened to Float64 |
| `metadata` | see below |

`metadata` mirrors the CSV header keys so code keying on metadata works for both
sources: `"TITLE"`, `"DATA TYPE"`, `"SPECTROMETER/DATA SYSTEM"`, `"XUNITS"`,
`"YUNITS"`, `"FIRSTX"`, `"LASTX"`, `"DELTAX"`, `"NPOINTS"`, plus `"Serial
Number"` (matching the footer English alias), `"Comment"`, and `"Format"`
(`"SPECMAN R2.0.0"`). Numeric values (`FIRSTX`/`LASTX`/`DELTAX`/`NPOINTS`) are
stored as their native `Float64`/`Int` types; the CSV path stores them as
strings. This is the one intentional metadata difference between sources and is
documented.

### Validation (fail-fast; each message prefixed with `basename(path)`)

In order, first failure throws `ArgumentError`:

1. **Too small** — file shorter than the fixed header → not a `.jws` file.
2. **Bad magic** — bytes `0x00..0x03 != "L~S "` →
   `"<file>: not a JASCO .jws file (missing 'L~S ' signature)"`.
3. **Unrecognized container** — format id `!= "SPECMAN"` or version `!= "R2.0.0"`,
   or the constant axis-descriptor signature (`0xA0` tag, `0xC0` code) differs
   from the known value →
   `"<file>: unrecognized .jws variant (SPECMAN <ver>); please share this file"`.
   This is what a structurally different y-mode/instrument would trip.
4. **Unsupported instrument** — instrument model does not start with `"FT/IR"` →
   `"<file>: unsupported .jws instrument '<model>'; only FTIR is supported — please share this file"`.
   This is the datatype gate.
5. **Bad point count** — `NPOINTS ≤ 0`, or `len(0xC8) != NPOINTS*4`, or the
   data block would start inside the fixed header (`filesize - len < 0x300`,
   i.e. `len` exceeds the file body) → throw with the specific mismatch.
6. **Grid inconsistency** — `round((LASTX-FIRSTX)/DELTAX) + 1 != NPOINTS` →
   throw. (Holds to <1e-3 on the sample files.)

### y-units assumption

FTIR files are labeled absorbance — the only y-mode we have samples for and can
verify. The format does encode the y-mode somewhere, but it cannot be located
from absorbance-only samples (every constant byte is identical across the three
files). Check 3's signature gate means a file whose data/axis descriptor differs
throws rather than being silently mislabeled. Confirming a y-unit code (to label
%transmittance, single-beam, etc.) requires a contrasting sample file; until
then, non-absorbance FTIR `.jws` is out of scope and expected to trip check 3.

## File structure

```
src/
├── JASCOFiles.jl   # add: include("binary.jl")
├── parser.jl       # split into dispatcher + _read_jasco_csv
├── binary.jl       # NEW: _read_jws, offset constants, read_cstr helper
├── types.jl        # unchanged
├── utils.jl        # unchanged
├── transforms.jl   # unchanged
└── plotting.jl     # unchanged
```

No new dependencies — `read`, `reinterpret`, and `Dates.unix2datetime` are
stdlib; `StringEncodings` is already a dependency.

## Testing

Real fixture: copy `zif-62-Zn.jws` → `test/data/ftir_test.jws` (the clean,
non-saturated sample; ~50 KB; sample name `"test"`, innocuous public-MOF FTIR).

Synthetic fixtures: build minimal valid `.jws` byte vectors **in
`runtests.jl`** and write them to `tempname()` per-test, so the only binary
committed is the one real file. A `make_jws(; npoints, firstx, lastx, ...)`
test helper assembles a valid container; error-path tests mutate it.

New testsets in `test/runtests.jl`:

- **read FTIR jws**: load `ftir_test.jws`; assert `x[1] ≈ 999.9101`,
  `x[end] ≈ 7000.335`, `length == 12447`, `isftir`, `datatype ==
  "INFRARED SPECTRUM"`, `xunits == "1/CM"`, `yunits == "ABSORBANCE"`,
  `spectrometer == "FT/IR-4600typeA"`, `metadata["Serial Number"] ==
  "E137161786"`, `y[1] ≈ 0.0188`, `date == DateTime(2026,6,4,4,54,3)`.
- **parity with CSV-sourced spectra**: the `.jws` FTIR spectrum returns the
  same `isftir`/`xlabel`/`ylabel` as a CSV FTIR spectrum.
- **error paths** (synthetic): bad magic, truncated file, `NPOINTS*4 != len`,
  grid inconsistency, and a non-FTIR instrument string each
  `@test_throws ArgumentError` (asserting the specific message substring, as the
  existing error-path tests do).
- **extension dispatch**: a `.csv` path still routes to the CSV reader
  (regression — all existing CSV testsets must continue to pass unchanged).

Aqua stays green (no new deps, no new exported names, no ambiguities).

## Docs

- **README**: remove the "does not read .jws files directly" sentence; add a
  short "reads `.jws` directly (FTIR)" note and a usage line.
- **`docs/src/guide/file-formats.md`**: add a `.jws` binary section with the
  offset table above.
- **`CLAUDE.md`**: add `binary.jl` to the structure; add a `.jws` row to the
  supported-instruments/formats table.
- **Module docstring** (`src/JASCOFiles.jl`): note that `.jws` (FTIR) is read
  natively.

## Out of scope

- Raman and UV-Vis `.jws` files (rejected by check 4).
- Non-absorbance FTIR y-modes — %transmittance, single-beam, reflectance,
  interferogram (expected to trip check 3 until a sample is available).
- Multi-trace `.jws` (sample + reference, or several measurement kinds in one
  file).
- Writing `.jws` files.
- Decoding the full header (resolution, accumulation, apodization, the unknown
  integer at `0x2C8`, the extra string slots). Only the fields needed for a
  faithful `JASCOSpectrum` are mapped.
- Timezone handling: `date` is UTC (the stored epoch); the CSV path stores local
  time. No TimeZones.jl dependency is added.
