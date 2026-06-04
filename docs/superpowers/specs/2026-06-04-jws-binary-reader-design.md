# Native `.jws` / `.jrs` binary reading (FTIR + UV-Vis)

**Date:** 2026-06-04
**Status:** Approved for planning (revised after UV-Vis + `.jrs` + `.txt` samples)

## Problem

JASCOFiles.jl reads only the CSV/text files exported from JASCO's Spectra
Manager software. The README states plainly: *"It does not read .jws files
directly — export raw data to CSV from the JASCO software."* That export step is
manual, lossy (it drops to the displayed precision and a fixed metadata subset),
and easy to forget. Users with a folder of raw instrument files cannot load them
without round-tripping every one through the Windows GUI.

The format is undocumented and proprietary, but it was reverse-engineered and
validated to byte-level correctness against real files of both instruments:

- three **FT/IR-4600** files (absorbance ×3 + transmittance): point count is
  triple-redundant in the container; the wavenumber grid and recovered spectra
  match the instrument's known export grid and known ZIF-62 band positions.
- five **V-730** UV-Vis files of one blank measurement in five y-modes
  (absorbance, %T, %R, single-beam reference, single-beam sample), each in
  **two on-disk formats** (`.jws` and `.jrs`), plus the `.txt` exports as
  ground truth.

Every recovered value matches the `.txt` headers to displayed precision (e.g.
UV abs FIRSTY −6.38777e-5, %T 100.032, single-beam 30.6151).

## `.jws` vs `.jrs` (same data, different writer)

Both share the `L~S ` magic and an identical field layout; for one measurement
they differ in only the header provenance fields, and the **float32 data block
is byte-identical**:

| Field | `.jws` | `.jrs` |
|-------|--------|--------|
| format id (`0x08`) | `SPECMAN` | `SPECIRM` |
| architecture (`0x30`) | `i80x86` | `MCF5328` |
| compiler (`0x40`) | `MSVC 1.0` | `CodeWarrior` |

`.jws` is written by the desktop **Spectra Manager** software (Intel x86, MSVC);
`.jrs` is written by the spectrometer's **onboard firmware** (Freescale ColdFire
MCF5328, CodeWarrior). `.jrs` is the file straight off the instrument; `.jws` is
the same spectrum after a PC save. Both extensions are supported by one reader.

## Decision

Teach the existing `JASCOSpectrum(path)` entry point to read `.jws` and `.jrs`
files directly, returning the **same `JASCOSpectrum` struct** the CSV path
returns. Everything downstream — `isftir`/`israman`/`isuvvis`, `xlabel`/
`ylabel`, the Makie and Tables extensions, the transforms — then works unchanged,
because it all dispatches on the struct, not on the source format.

Support **FTIR (FT/IR-series)** and **UV-Vis (V-series)** instruments. Decode the
instrument, x-units, and y-mode from the container rather than assuming them.
Anything unrecognized — a different instrument family (e.g. Raman NRS), an
unknown y-mode code, or a structurally different container — is **rejected with a
clear, file-naming error** rather than guessed at, matching the package's
fail-fast philosophy (see `2026-05-29-jascospectrum-validation-design.md`).

## The container (SPECMAN / SPECIRM, version R2.0.0)

Little-endian. Fixed-offset header, fixed-width null-terminated string fields,
then a contiguous `Float32` data block running to EOF. The header is a fixed size
(data begins at `0x740`) on both instruments and both formats. Fields used:

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| `0x00` | char[4] | magic `"L~S "` | `4C 7E 53 20` |
| `0x08` | str16 | format id | `"SPECMAN"` (.jws) or `"SPECIRM"` (.jrs) |
| `0x20` | str16 | container version | `"R2.0.0"` |
| `0x84` | Int32 | NPOINTS | |
| `0x88` | Float64 | FIRSTX | cm-1 (FTIR) or nm (UV-Vis) |
| `0x90` | Float64 | LASTX | |
| `0x98` | Float64 | DELTAX | signed: `+` ascending (FTIR), `−` descending (UV-Vis) |
| `0xA0` | UInt8 | **x-unit code** | `0` = cm-1, `3` = nm |
| `0xA1..0xA3` | bytes | structural constant | `01 00 10` |
| `0xA4` | UInt8 | **y-mode code** | see table |
| `0xA5..0xA7` | bytes | structural constant | `00 00 00` |
| `0xC8` | Int64 | data-block length (bytes) | `== NPOINTS * 4` |
| `0xE8` | Float32[4] | saved plot-view `[xmax,ymax,xmin,ymin]` | display only — **ignored** |
| `0x140` | str32 | instrument model | `"FT/IR-4600typeA"`, `"V-730"` |
| `0x160` | str32 | serial number | |
| `0x180` | str64 | title / sample name | |
| `0x1C0` | str64 | comment | |
| `0x2C0` | Int32 | acquisition time (Unix epoch, UTC) | duplicated at `0x2C4` |
| `filesize - len` .. EOF | Float32[NPOINTS] | y-data | order follows DELTAX sign; `y[1]` at FIRSTX |

Data offset is computed as `filesize - len(0xC8)` (= `0x740` on every sample),
not hard-coded. The plot-view block, the duplicate timestamp, the architecture/
compiler provenance strings, and several placeholder fields are read past but
unused.

### y-mode code (`0xA4`) → `YUNITS`

Verified against the five V-730 modes, the FTIR transmittance file, and JASCO's
CSV/txt `YUNITS` vocabulary:

| `0xA4` | `YUNITS` | Meaning | Verified on |
|--------|----------|---------|-------------|
| `0x03` | `ABSORBANCE` | absorbance | FTIR abs, UV abs |
| `0x00` | `TRANSMITTANCE` | %T | FTIR `t.jws`, UV t |
| `0x02` | `REFLECTANCE` | %R | UV r |
| `0x09` | `INTENSITY` | single-beam, reference channel | UV ref |
| `0x0a` | `INTENSITY` | single-beam, sample channel | UV sample |
| other | — | — | **throw** (unknown code) |

Codes `0x09`/`0x0a` both map to `YUNITS = "INTENSITY"` (confirmed against the
`.txt`); the channel is recorded in `metadata["Channel"] = "Reference"`/
`"Sample"`.

### instrument model (`0x140`) → `datatype` + `xunits`

`datatype` is set to what JASCO's **CSV/txt export of the same file contains**,
so a `.jws`/`.jrs` and a CSV/txt of one measurement yield identical structs:

| Model prefix | `datatype` | `xunits` | expected `0xA0` |
|--------------|-----------|----------|-----------------|
| `FT/IR` | `"INFRARED SPECTRUM"` | `"1/CM"` | `0` |
| `V-` | `""` (V-730 export omits DATA TYPE; `isuvvis` infers) | `"NANOMETERS"` | `3` |
| anything else | — | — | **throw** (unsupported instrument) |

For UV-Vis the binary still *knows* it is a V-series instrument (used to set
`xunits` and as the `isuvvis` signal via `NANOMETERS` + range), but leaves
`datatype` blank to match the V-730 text export exactly. The `0xA0` x-unit code
is cross-checked against the expected value (mismatch → throw).

## Design

### Dispatch (no public API change)

`src/parser.jl` currently *is* the CSV reader:
`JASCOSpectrum(path::AbstractString; encoding=enc"SHIFT-JIS", translate=true)`.

Split it:

- The public `JASCOSpectrum(path; encoding, translate)` becomes a thin
  dispatcher: if the lower-cased extension is `.jws` or `.jrs`, call `_read_jws`;
  otherwise call `_read_jasco_csv` (the existing body, renamed, unchanged).
- `encoding` is forwarded to both (binary string fields are SHIFT-JIS-decoded
  too, so Japanese sample names work). `translate` applies only to the CSV
  footer and is ignored by the binary path.

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
4. Validate (below).
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
| `datatype` | instrument family (FTIR → IR; V-series → blank) |
| `xunits` | instrument family (FTIR → `1/CM`; V-series → `NANOMETERS`) |
| `yunits` | `0xA4` y-mode code |
| `x` | generated grid (Float64) |
| `y` | Float32 block widened to Float64 |
| `metadata` | CSV-mirroring keys (below) |

`metadata` mirrors the CSV header keys so code keying on metadata works for both
sources: `"TITLE"`, `"DATA TYPE"`, `"SPECTROMETER/DATA SYSTEM"`, `"XUNITS"`,
`"YUNITS"`, `"FIRSTX"`, `"LASTX"`, `"DELTAX"`, `"NPOINTS"`, plus `"Serial
Number"`, `"Comment"`, `"Format"` (`"SPECMAN R2.0.0"` / `"SPECIRM R2.0.0"`), and
`"Channel"` for single-beam. Numeric values (`FIRSTX`/`LASTX`/`DELTAX`/
`NPOINTS`) are stored as native `Float64`/`Int` (the CSV path stores strings) —
the one intentional, documented metadata difference between sources.

### Validation (fail-fast; each message prefixed with `basename(path)`)

In order, first failure throws `ArgumentError`:

1. **Too small** — file shorter than the fixed header → not a binary JASCO file.
2. **Bad magic** — `0x00..0x03 != "L~S "` →
   `"<file>: not a JASCO .jws/.jrs file (missing 'L~S ' signature)"`.
3. **Unrecognized container** — format id not in {`SPECMAN`, `SPECIRM`},
   version `!= "R2.0.0"`, or descriptor structural bytes (`0xA1..0xA3 != 01 00
   10`, `0xA5..0xA7 != 00 00 00`) differ →
   `"<file>: unrecognized binary variant (<id> <ver>); please share this file"`.
4. **Unsupported instrument** — model is not `FT/IR…` or `V-…` →
   `"<file>: unsupported instrument '<model>'; only FTIR and UV-Vis are supported — please share this file"`.
5. **x-unit mismatch** — `0xA0` disagrees with the instrument family's expected
   x-unit → throw.
6. **Unknown y-mode** — `0xA4` not in the table →
   `"<file>: unrecognized y-mode code 0x<NN>; please share this file"`.
7. **Bad point count** — `NPOINTS ≤ 0`, `len(0xC8) != NPOINTS*4`, or
   `filesize - len < 0x300` (block would overlap the header) → throw.
8. **Invalid DELTAX** — `DELTAX` zero or non-finite → throw `"…: invalid DELTAX=<v>"`.
   The x-axis is reconstructed from `FIRSTX + DELTAX·(0:NPOINTS−1)`; the stored
   `LASTX` is **informational and not a hard check** — real files (e.g. a
   truncated V-730 reflectance scan) can store a `LASTX` that disagrees with the
   actual grid, so rejecting on it would be a false positive. `metadata["LASTX"]`
   reports the computed endpoint (`last(x)`), which always matches the data.

## File structure

```
src/
├── JASCOFiles.jl   # add: include("binary.jl")
├── parser.jl       # split into dispatcher + _read_jasco_csv
├── binary.jl       # NEW: _read_jws, offset constants, decode tables, read_cstr
├── types.jl        # unchanged
├── utils.jl        # unchanged
├── transforms.jl   # unchanged
└── plotting.jl     # unchanged (REFLECTANCE/INTENSITY/SB fall back to
                    #            title-cased labels; explicit cases out of scope)
```

No new dependencies — `read`, `reinterpret`, `Dates.unix2datetime` are stdlib;
`StringEncodings` is already a dependency.

## Testing

Real fixtures committed to `test/data/` (all blank/baseline `"test"` scans,
innocuous for the public repo):

- `ftir_test.jws` — copy of `zif-62-Zn.jws` (~50 KB, FT/IR-4600, absorbance).
- `uvvis_abs.jws` — copy of `abs.jws` (~2 KB, V-730, absorbance).
- `uvvis_trans.jws` — copy of `t.jws` (~2 KB, V-730, %T; non-absorbance mode +
  descending grid).
- `uvvis_abs.jrs` — copy of `abs.jrs` (~2 KB; SPECIRM container).

Synthetic fixtures: build minimal valid byte vectors **in `runtests.jl`** (a
`make_jws(; id, instrument, ymode, npoints, firstx, deltax, …)` helper writes to
`tempname()` per test) for error paths, so they need no committed binaries.

New testsets in `test/runtests.jl`:

- **read FTIR jws**: `ftir_test.jws` → `x[1] ≈ 999.9101`, `x[end] ≈ 7000.335`,
  `length == 12447`, `isftir`, `datatype == "INFRARED SPECTRUM"`, `xunits ==
  "1/CM"`, `yunits == "ABSORBANCE"`, `spectrometer == "FT/IR-4600typeA"`,
  `metadata["Serial Number"] == "E137161786"`, `y[1] ≈ 0.0188`, `date ==
  DateTime(2026,6,4,4,54,3)`.
- **read UV-Vis jws (absorbance)**: `uvvis_abs.jws` → `isuvvis`, `datatype ==
  ""`, `xunits == "NANOMETERS"`, `yunits == "ABSORBANCE"`, `spectrometer ==
  "V-730"`, `x[1] == 700.0`, `x[end] == 400.0`, `length == 61`, `y[1] ≈
  -6.388e-5`.
- **read UV-Vis jws (%T)**: `uvvis_trans.jws` → `yunits == "TRANSMITTANCE"`,
  `y ≈ 100`, descending x.
- **`.jrs` parity**: `uvvis_abs.jrs` decodes to the same `x`/`y`/`datatype`/
  `yunits` as `uvvis_abs.jws`; `metadata["Format"]` starts with `"SPECIRM"`.
- **`.txt` ground-truth cross-check**: load `uvvis_abs.jws` and its `.txt`
  export (via the CSV path) and assert the `x`/`y` arrays agree to the text
  precision — byte-for-byte validation of the binary decode.
- **CSV/txt parity**: a `.jws` FTIR/UV-Vis spectrum returns the same
  `isftir`/`isuvvis`/`xlabel`/`ylabel` as the matching CSV/txt spectrum.
- **error paths** (synthetic): bad magic, truncation, `NPOINTS*4 != len`, grid
  inconsistency, unknown y-mode, unsupported instrument — each
  `@test_throws ArgumentError` asserting the specific message substring.
- **extension dispatch**: a `.csv`/`.txt` path still routes to the CSV reader
  (regression — all existing CSV testsets keep passing unchanged).

The `.txt` exports (`abs/t/r/ref/sample.txt`) are available as ground truth; at
least `abs.txt` is committed alongside `uvvis_abs.jws` for the cross-check.

Aqua stays green (no new deps, no new exported names, no ambiguities).

## Docs

- **README**: remove the "does not read .jws files directly" sentence; add a
  "reads `.jws` / `.jrs` directly (FTIR and UV-Vis)" note with a usage line and
  the `.jws`/`.jrs` provenance one-liner.
- **`docs/src/guide/file-formats.md`**: add a binary-format section with the
  offset table and the two decode tables.
- **`CLAUDE.md`**: add `binary.jl` to the structure; add `.jws`/`.jrs` rows to
  the formats table.
- **Module docstring** (`src/JASCOFiles.jl`): note native `.jws`/`.jrs` reading.

## Out of scope

- **Raman `.jws`/`.jrs`** (NRS-series) — rejected by check 4 until a sample
  exists.
- Y-modes beyond Abs/T/R/Intensity and any unknown `0xA4` code — rejected by
  check 6.
- Multi-trace files (sample + reference, or several kinds in one file).
- Writing binary files.
- Decoding the full header (resolution, accumulation, apodization, the unknown
  integer at `0x2C8`, the extra string slots). Only fields needed for a faithful
  `JASCOSpectrum` are mapped.
- Explicit `REFLECTANCE`/`INTENSITY` cases in `ylabel` (title-case fallback
  suffices).
- Timezone handling: `date` is UTC (the stored epoch); the CSV path stores local
  time. No TimeZones.jl dependency is added.
