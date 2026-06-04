# Native `.jws` binary reading (FTIR + UV-Vis)

**Date:** 2026-06-04
**Status:** Approved for planning (revised after UV-Vis samples arrived)

## Problem

JASCOFiles.jl reads only the CSV files exported from JASCO's Spectra Manager
software. The README states plainly: *"It does not read .jws files directly —
export raw data to CSV from the JASCO software."* That export step is manual,
lossy (it drops to the displayed precision and a fixed metadata subset), and
easy to forget. Users with a folder of raw `.jws` instrument files cannot load
them without round-tripping every one through the Windows GUI.

The `.jws` format is undocumented and proprietary, but it was reverse-engineered
and validated to byte-level correctness against:

- three **FT/IR-4600** absorbance files (point count is triple-redundant in the
  container; the wavenumber grid and recovered spectra match the instrument's
  known export grid and known ZIF-62 band positions), and
- five **V-730** UV-Vis files of the same blank measurement in five y-modes
  (absorbance, %T, %R, single-beam reference, single-beam sample). Diffing the
  same-grid `abs`/`t` pair isolated the **y-mode code**, and the recovered
  y-ranges match each mode (abs ≈ 0, %T/%R ≈ 100, single-beam ≈ 30).

Both instruments use the **same SPECMAN R2.0.0 container**, so one reader serves
both. UV-Vis `.txt` exports of the same files are incoming and will be used as
byte-for-byte ground truth (especially to pin the single-beam `YUNITS` string).

## Decision

Teach the existing `JASCOSpectrum(path)` entry point to read `.jws` files
directly, returning the **same `JASCOSpectrum` struct** the CSV path returns.
Everything downstream of the struct — `isftir`/`israman`/`isuvvis`, `xlabel`/
`ylabel`, the Makie and Tables extensions, the transmittance/absorbance
transforms — then works unchanged, because all of it dispatches on the struct,
not on the source format.

Support **FTIR (FT/IR-series)** and **UV-Vis (V-series)** `.jws`. Decode the
instrument, x-units, and y-mode from the container rather than assuming them.
Anything not recognized — a different instrument family (e.g. Raman NRS), an
unknown y-mode code, or a structurally different container — is **rejected with
a clear, file-naming error** rather than guessed at, matching the package's
fail-fast philosophy (see `2026-05-29-jascospectrum-validation-design.md`) and
its "send a sample for an unsupported file" model.

## The `.jws` format (SPECMAN R2.0.0)

Little-endian. Fixed-offset header, fixed-width null-terminated string fields,
then a contiguous `Float32` data block that runs to EOF. The header is the same
fixed size (data always begins at `0x740`) on both instruments. Fields the
reader uses:

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| `0x00` | char[4] | magic `"L~S "` | `4C 7E 53 20` |
| `0x08` | str16 | format id `"SPECMAN"` | |
| `0x20` | str16 | format version `"R2.0.0"` | |
| `0x84` | Int32 | NPOINTS | |
| `0x88` | Float64 | FIRSTX | cm-1 (FTIR) or nm (UV-Vis) |
| `0x90` | Float64 | LASTX | |
| `0x98` | Float64 | DELTAX | signed: `+` ascending (FTIR), `−` descending (UV-Vis) |
| `0xA0` | UInt8 | **x-unit code** | `0` = cm-1, `3` = nm |
| `0xA1..0xA3` | bytes | structural constant | `01 00 10` |
| `0xA4` | UInt8 | **y-mode code** | see table below |
| `0xA5..0xA7` | bytes | structural constant | `00 00 00` |
| `0xC8` | Int64 | data-block length (bytes) | `== NPOINTS * 4` |
| `0xE0..0xE7` | bytes | descriptor tag (mirror of `0xA0`) | x-unit + y-mode repeated |
| `0xE8` | Float32[4] | saved plot-view `[xmax,ymax,xmin,ymin]` | display only — **ignored** |
| `0x140` | str32 | instrument model | `"FT/IR-4600typeA"`, `"V-730"` |
| `0x160` | str32 | serial number | |
| `0x180` | str64 | title / sample name | |
| `0x1C0` | str64 | comment | |
| `0x2C0` | Int32 | acquisition time (Unix epoch, UTC) | duplicated at `0x2C4` |
| `filesize - len` .. EOF | Float32[NPOINTS] | y-data | order follows DELTAX sign; `y[1]` at FIRSTX |

Data offset is computed as `filesize - len(0xC8)` (= `0x740` on every sample
file), not hard-coded. The plot-view block at `0xE8`, the duplicate timestamp at
`0x2C4`, and several placeholder string/integer fields are read past but unused.

### y-mode code (`0xA4`) → `YUNITS`

Verified against the five V-730 modes and JASCO's CSV `YUNITS` vocabulary
(`ABSORBANCE` / `TRANSMITTANCE` / `REFLECTANCE` / `SB` / `INTENSITY`):

| `0xA4` | `YUNITS` | Meaning | Confidence |
|--------|----------|---------|------------|
| `0x03` | `ABSORBANCE` | absorbance | verified (y ≈ 0; matches FTIR + UV abs) |
| `0x00` | `TRANSMITTANCE` | %T | verified (y ≈ 100) |
| `0x02` | `REFLECTANCE` | %R | verified (y ≈ 100) |
| `0x09` | `SB` | single-beam, reference channel | provisional — confirm string vs `.txt` |
| `0x0a` | `SB` | single-beam, sample channel | provisional — confirm string vs `.txt` |
| other | — | — | **throw** (unknown code) |

Codes `0x09`/`0x0a` get `yunits = "SB"` with the channel recorded in metadata
(`metadata["Channel"] = "Reference"`/`"Sample"`); the exact `YUNITS` string is
confirmed against the incoming `.txt` before merge.

### instrument model (`0x140`) → `datatype` + `xunits`

| Model prefix | `datatype` | `xunits` | expected `0xA0` |
|--------------|-----------|----------|-----------------|
| `FT/IR` | `"INFRARED SPECTRUM"` | `"1/CM"` | `0` |
| `V-` | `"UV/VIS SPECTRUM"` | `"NANOMETERS"` | `3` |
| anything else | — | — | **throw** (unsupported instrument) |

`datatype` and `xunits` come from the instrument family; the `0xA0` x-unit code
is cross-checked against the expected value as defense-in-depth (mismatch →
throw). Setting `datatype = "UV/VIS SPECTRUM"` makes `isuvvis` return `true`
directly (the CSV V-730 path leaves `DATA TYPE` blank and infers it; the binary
path is explicit — a documented, harmless difference).

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
plain internal function (not a `JASCOSpectrum` method), so no method ambiguity is
introduced and Aqua's ambiguity check stays green.

### Reader (`src/binary.jl`, new)

`_read_jws(path; encoding)`:

1. `read(path)` into a `Vector{UInt8}`.
2. Read fixed-offset scalars via `reinterpret`; read string fields via a
   `read_cstr(bytes, offset, width, encoding)` helper (null-terminated within a
   fixed width, then `StringEncodings.decode` + strip).
3. Decode `datatype`/`xunits` from the instrument model and `yunits` from the
   `0xA4` code (tables above).
4. Validate (see below).
5. Build `x = FIRSTX .+ DELTAX .* (0:NPOINTS-1)` (handles ascending FTIR and
   descending UV-Vis from the DELTAX sign) and
   `y = Float64.(reinterpret(Float32, data_block))`.
6. Return `JASCOSpectrum(title, date, spectrometer, datatype, xunits, yunits,
   x, y, metadata)`.

Offset constants and the two decode tables live at the top of `binary.jl` as
named values, not magic numbers in the logic.

### Field mapping

| `JASCOSpectrum` field | Source |
|-----------------------|--------|
| `title` | sample (`0x180`); `"Untitled"` if empty |
| `date` | `unix2datetime(epoch @ 0x2C0)`; `DateTime(2000)` if epoch ≤ 0 |
| `spectrometer` | instrument model (`0x140`) |
| `datatype` | decoded from instrument family |
| `xunits` | decoded from instrument family |
| `yunits` | decoded from `0xA4` y-mode code |
| `x` | generated grid (Float64) |
| `y` | Float32 block widened to Float64 |
| `metadata` | CSV-mirroring keys (below) |

`metadata` mirrors the CSV header keys so code keying on metadata works for both
sources: `"TITLE"`, `"DATA TYPE"`, `"SPECTROMETER/DATA SYSTEM"`, `"XUNITS"`,
`"YUNITS"`, `"FIRSTX"`, `"LASTX"`, `"DELTAX"`, `"NPOINTS"`, plus `"Serial
Number"`, `"Comment"`, `"Format"` (`"SPECMAN R2.0.0"`), and `"Channel"` for
single-beam. Numeric values (`FIRSTX`/`LASTX`/`DELTAX`/`NPOINTS`) are stored as
native `Float64`/`Int` (the CSV path stores strings) — the one intentional,
documented metadata difference between sources.

### Validation (fail-fast; each message prefixed with `basename(path)`)

In order, first failure throws `ArgumentError`:

1. **Too small** — file shorter than the fixed header → not a `.jws` file.
2. **Bad magic** — `0x00..0x03 != "L~S "` →
   `"<file>: not a JASCO .jws file (missing 'L~S ' signature)"`.
3. **Unrecognized container** — format id `!= "SPECMAN"`, version `!= "R2.0.0"`,
   or the descriptor structural bytes (`0xA1..0xA3 != 01 00 10`, `0xA5..0xA7 !=
   00 00 00`) differ →
   `"<file>: unrecognized .jws variant (SPECMAN <ver>); please share this file"`.
4. **Unsupported instrument** — model is not `FT/IR…` or `V-…` →
   `"<file>: unsupported .jws instrument '<model>'; only FTIR and UV-Vis are supported — please share this file"`.
5. **x-unit mismatch** — `0xA0` code disagrees with the instrument family's
   expected x-unit → throw (corrupt or misidentified).
6. **Unknown y-mode** — `0xA4` not in the table →
   `"<file>: unrecognized .jws y-mode code 0x<NN>; please share this file"`.
7. **Bad point count** — `NPOINTS ≤ 0`, `len(0xC8) != NPOINTS*4`, or
   `filesize - len < 0x300` (block would overlap the header) → throw with the
   specific mismatch.
8. **Grid inconsistency** — `round((LASTX-FIRSTX)/DELTAX) + 1 != NPOINTS` → throw.

## File structure

```
src/
├── JASCOFiles.jl   # add: include("binary.jl")
├── parser.jl       # split into dispatcher + _read_jasco_csv
├── binary.jl       # NEW: _read_jws, offset constants, decode tables, read_cstr
├── types.jl        # unchanged
├── utils.jl        # unchanged
├── transforms.jl   # unchanged
└── plotting.jl     # unchanged (REFLECTANCE/SB fall back to title-case labels;
                    #            adding explicit cases is optional, out of scope)
```

No new dependencies — `read`, `reinterpret`, `Dates.unix2datetime` are stdlib;
`StringEncodings` is already a dependency.

## Testing

Real fixtures committed to `test/data/` (all are blank/baseline `"test"` scans,
innocuous for the public repo):

- `ftir_test.jws` — copy of `zif-62-Zn.jws` (~50 KB, FT/IR-4600, absorbance).
- `uvvis_abs.jws` — copy of `abs.jws` (~2 KB, V-730, absorbance).
- `uvvis_trans.jws` — copy of `t.jws` (~2 KB, V-730, %T) to exercise a
  non-absorbance y-mode and the descending-wavelength grid.

Synthetic fixtures: build minimal valid `.jws` byte vectors **in `runtests.jl`**
(a `make_jws(; instrument, ymode, npoints, firstx, deltax, …)` helper writes to
`tempname()` per test), so error-path inputs need no committed binaries.

New testsets in `test/runtests.jl`:

- **read FTIR jws**: load `ftir_test.jws`; assert `x[1] ≈ 999.9101`,
  `x[end] ≈ 7000.335`, `length == 12447`, `isftir`, `datatype ==
  "INFRARED SPECTRUM"`, `xunits == "1/CM"`, `yunits == "ABSORBANCE"`,
  `spectrometer == "FT/IR-4600typeA"`, `metadata["Serial Number"] ==
  "E137161786"`, `y[1] ≈ 0.0188`, `date == DateTime(2026,6,4,4,54,3)`.
- **read UV-Vis jws (absorbance)**: load `uvvis_abs.jws`; assert `isuvvis`,
  `datatype == "UV/VIS SPECTRUM"`, `xunits == "NANOMETERS"`, `yunits ==
  "ABSORBANCE"`, `spectrometer == "V-730"`, `x[1] == 700.0`, `x[end] == 400.0`,
  `length == 61`.
- **read UV-Vis jws (%T)**: load `uvvis_trans.jws`; assert `yunits ==
  "TRANSMITTANCE"`, `y` values ≈ 100, descending x grid.
- **parity with CSV-sourced spectra**: a `.jws` FTIR/UV-Vis spectrum returns the
  same `isftir`/`isuvvis`/`xlabel`/`ylabel` as the matching CSV spectrum.
- **error paths** (synthetic): bad magic, truncated file, `NPOINTS*4 != len`,
  grid inconsistency, unknown y-mode code, and an unsupported instrument string
  each `@test_throws ArgumentError` (asserting the specific message substring).
- **extension dispatch**: a `.csv`/`.txt` path still routes to the CSV reader
  (regression — all existing CSV testsets must keep passing unchanged).

When the UV-Vis `.txt` exports arrive: confirm the single-beam `YUNITS` string
(codes `0x09`/`0x0a`) and add a byte-for-byte value check of `uvvis_abs.jws`
against its `.txt` export.

Aqua stays green (no new deps, no new exported names, no ambiguities).

## Docs

- **README**: remove the "does not read .jws files directly" sentence; add a
  "reads `.jws` directly (FTIR and UV-Vis)" note with a usage line.
- **`docs/src/guide/file-formats.md`**: add a `.jws` binary section with the
  offset table and the two decode tables.
- **`CLAUDE.md`**: add `binary.jl` to the structure; add `.jws` rows to the
  formats table.
- **Module docstring** (`src/JASCOFiles.jl`): note that `.jws` (FTIR + UV-Vis)
  is read natively.

## Out of scope

- **Raman `.jws`** (NRS-series) — rejected by check 4 until a sample exists.
- Non-absorbance/T/R/SB y-modes and any unknown `0xA4` code — rejected by
  check 6.
- Multi-trace `.jws` (sample + reference, or several kinds in one file).
- Writing `.jws` files.
- Decoding the full header (resolution, accumulation, apodization, the unknown
  integer at `0x2C8`, the extra string slots). Only fields needed for a faithful
  `JASCOSpectrum` are mapped.
- Explicit `REFLECTANCE`/`SB` cases in `ylabel` (title-case fallback suffices).
- Timezone handling: `date` is UTC (the stored epoch); the CSV path stores local
  time. No TimeZones.jl dependency is added.

## Pending ground truth

The single-beam `YUNITS` string for codes `0x09`/`0x0a` is provisional (`"SB"`).
It is confirmed against the incoming UV-Vis `.txt` exports before the branch
merges; if JASCO labels reference/sample single-beam differently, the decode
table and the UV-Vis tests are updated accordingly.
