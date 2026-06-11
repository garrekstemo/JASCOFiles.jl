# Legacy JASCO `.jws` (Spectra Manager 1.x, OLE2 container) — verified format specification

**Date:** 2026-06-11
**Status:** Reverse-engineered and corpus-verified; reference decoder in `legacy_decode.jl` (same directory)
**Scope:** The *legacy* binary `.jws` written by Spectra Manager 1.x-era JASCO software
(internal format id `SPCMAN2`), as distinct from the *modern* flat `L~S `/`SPECMAN R2.0.0`
format already implemented in `src/binary.jl` and specified in
`docs/superpowers/specs/2026-06-04-jws-binary-reader-design.md`.

## Verification corpus

`/Users/garrek/Developer/Raw Data/FTIR/` — 391 `.jws` files in date-named folders
(190731 … 230621), all from one FT/IR-4600typeA (serial E137161786, NAIST).

- **385 legacy** files (CFB magic `D0 CF 11 E0 A1 B1 1A E1`) — all 385 decode cleanly.
- **6 modern** files (`L~S ` magic) interleaved in the same folders
  (190925, 210225, 210518 ×2, 210525 ×2). The two formats coexist in time;
  **a reader must dispatch on the first 8 bytes, not on era or extension**.
- **184** legacy files have a same-basename CSV/text export used as ground truth
  (see "Ground-truth cross-check" below).

Confidence vocabulary used throughout:
- **verified** — checked programmatically across the corpus and/or against paired CSV exports;
- **corroborated** — agrees with prior art (below) but only partially exercised locally;
- **observed** — consistent in the corpus but semantics not independently confirmed;
- **unknown** — bytes accounted for, meaning not established.

### Prior art

Field layout of `DataInfo` and the channel-code idea corroborated against:

- V. M. Hernández-Rocamora, *jwsProcessor* (`src/jwsprocessor/jwslib.py`),
  https://github.com/vhernandez/jwsProcessor — `DATAINFO_FMT = '<LLLLLLdddLLLLdddd'`.
- J. Tran, *jws2txt* (`jws2txt/helpers/helpers.py`), https://github.com/jzftran/jws2txt —
  channel count at word 3, channel-descriptor words 9–12, channel-major `Y-Data`,
  CD-instrument channel codes (`0x10000103` = wavelength/nm, `3` = absorbance).
- odoluca, *jasco_jws_reader* (`jwslib.py`), https://github.com/odoluca/jasco_jws_reader.

Every claim below was re-verified against the local corpus; prior art was used only to
name fields this corpus cannot discriminate (e.g. multi-channel layout).

---

## 1. Container: OLE2 / CFB compound document

Standard [MS-CFB]. Everything little-endian. Requirements that actually bite:

| Item | Value / rule | Corpus |
|---|---|---|
| Magic (offset 0) | `D0 CF 11 E0 A1 B1 1A E1` | 385/385 |
| Sector size | `1 << UInt16@0x1E` — **both 512 (v3) and 4096 (v4) occur** | 274 × 512 B, 111 × 4096 B |
| Sector position | sector *n* starts at byte `(n+1) × sector_size` (the 512-byte header is padded to a full sector in v4 files) | verified — hard-coding `512 +` breaks all 111 v4 files |
| Mini-sector size | `1 << UInt16@0x20` = 64 | 385/385 |
| Mini-stream cutoff | `UInt32@0x38` = 4096 | 385/385 |
| Directory start | `UInt32@0x30`; FAT chain of 128-byte entries | |
| Mini-FAT | first sector `UInt32@0x3C`, count `UInt32@0x40` | |
| DIFAT | 109 entries at `0x4C`, then chained DIFAT sectors (`0x44`/`0x48`) | corpus never needs chained DIFAT, implement anyway |

**Mini-stream is mandatory to implement.** Every metadata stream (`DataInfo` 96 B,
`SampleInfo`, `MeasParam`, `Header` 1024 B, …) is smaller than 4096 B and therefore
lives in the mini-stream (the root entry's regular-FAT chain, addressed in 64-byte
mini-sectors via the mini-FAT). Only `Y-Data` (29–242 KB in the corpus) uses the
regular FAT directly.

Directory entries (128 B): UTF-16LE name with byte length `UInt16@+0x40`
(includes null), type `@+0x42` (1 = storage, 2 = stream, 5 = root), left/right/child
`UInt32@+0x44/+0x48/+0x4C` (sibling red-black tree per storage), start sector
`UInt32@+0x74`, size `UInt32@+0x78`. Storage entries carry FILETIME timestamps at
`+0x64`/`+0x6C` (UTC); these match the file's save time and can serve as a fallback
date source.

## 2. Stream inventory

Top-level layout (385/385 unless noted):

| Path | Size (bytes, observed) | Content |
|---|---|---|
| `Header` | 1024 | container signature block (§3) |
| `DataInfo` | 96 | axis/grid descriptor — the heart of the format (§4) |
| `Y-Data` | 4 × nchan × npoints | Float32 ordinate block (§5) |
| `SampleInfo` | 20–212 | sample name, comment, measurement date (§7) |
| `UserInfo` | 76–108 | 15 user string slots; slot 12 = company (§8) |
| `ModuleInfo` | 32–148 | instrument model, serial, module id (§9) |
| `MeasInfo` | 8 | `[UInt32 1][UInt16 0][UInt16 module id]` (§9) |
| `MeasParam` | 12 or 438 | TLV list of acquisition parameters (§10) |
| `BaseInfo` | 117–439 | GUID, original path, save/measure dates, provenance (§11) |
| `Histories` | 8–996 | processing log records (§12) |
| `Results`, `Results/Result-N/{Data,Param,Default}` | small | analysis results (peak find, FWHM…) — 218/385 files have ≥1 `Result-N` (76 one, 139 two, 2 three, 1 four) (§13) |
| `MicroImages/BaseInfo`, `MicroImageShapes/BaseInfo` | 8 | empty placeholders (`[UInt32][UInt32 0]`) in all corpus files |

No `X-Data` stream occurs in the corpus (all files are equidistant —
CSV exports say データタイプ, 等間隔データ). Prior art does not decode an `X-Data`
either; non-equidistant variants are **unknown** and should be rejected if an
`X-Data` stream is ever encountered.

## 3. `Header` stream (1024 B) — container identity

Fixed-offset UTF-16LE strings, zero-padded; identical in all 385 files:

| Offset | Content |
|---|---|
| `0x00` | `"L~"` (UTF-16: `4C 00 7E 00`) |
| `0x04` | `UInt16` 0x0001, `UInt16` 0x8401 (observed, meaning unknown) |
| `0x08` | `"SPCMAN2"` |
| `0x38` | `"R2.00.00"` |
| `0x58` | `"80x86"` |
| `0x78` | `"VC++6.0"` |

This is the direct ancestor of the modern flat header (`"L~S "` + `"SPECMAN"` +
`"R2.0.0"` + `"i80x86"` + `"MSVC 1.0"`). **Gate:** require `"L~"` at 0 and
`"SPCMAN"` within the first 24 non-null bytes.

## 4. `DataInfo` stream (96 B) — verified field table

Matches prior art's `<LLLLLLdddLLLLdddd`. All 385 files are 96 B exactly.

| Offset | Type | Field | Value / meaning | Confidence |
|---|---|---|---|---|
| `0x00` | UInt32 | stream version | 3 in 385/385 | verified constant |
| `0x04` | UInt32 | — | 1 in 385/385; prior art: channel count in `.jwb` interval files | observed |
| `0x08` | UInt32 | — | 0 in 385/385 | observed |
| `0x0C` | UInt32 | **channel count** | 1 in 385/385; per jws2txt, >1 in CD files | verified =1; corroborated as nchan |
| `0x10` | UInt32 | — | 1 in 385/385 | observed |
| `0x14` | UInt32 | **NPOINTS** | equals `sizeof(Y-Data)/4` in 385/385 | **verified** |
| `0x18` | Float64 | **FIRSTX** | e.g. 999.9101…; matches CSV `FIRSTX` | **verified** (CSV) |
| `0x20` | Float64 | **LASTX** | matches CSV `LASTX`; see grid note below | **verified** (CSV) |
| `0x28` | Float64 | **DELTAX** | matches CSV `DELTAX` to all printed digits | **verified** (CSV) |
| `0x30` | UInt32 | **x-axis descriptor** | `0x10000100` in 385/385 (§4.1) | verified constant |
| `0x34` | UInt32 | **y channel-1 descriptor (y-mode code)** | 0 / 3 / 8 (§4.2) | **verified** (CSV + filenames) |
| `0x38` | UInt32 | descriptor slot 3 | == word`@0x30` in 385/385 | observed (see §4.3) |
| `0x3C` | UInt32 | descriptor slot 4 | == word`@0x34` in 385/385 | observed (see §4.3) |
| `0x40` | Float64 | display x-max | saved plot view; may be 0 | observed, ignore |
| `0x48` | Float64 | display y-max | 〃 | observed, ignore |
| `0x50` | Float64 | display x-min | 〃 | observed, ignore |
| `0x58` | Float64 | display y-min | 〃 | observed, ignore |

Same ordering convention `[xmax, ymax, xmin, ymin]` as the modern format's
plot-view block. (Prior art's comment lists xmin/ymin/xmax/ymax — that order is
wrong; the corpus shows max-before-min.)

**Grid note.** `LASTX` is informational: `FIRSTX + DELTAX × (NPOINTS−1)` differs from
the stored `LASTX` by up to 0.0033 cm⁻¹ in the corpus (e.g. two otherwise identical
12447-point files store 7000.3350 vs 7000.3383). Reconstruct the axis from
FIRSTX/DELTAX and treat LASTX as a soft check (tolerance ±|DELTAX|), exactly as the
modern reader does.

### 4.1 x-axis descriptor word

`0x10000100` = bytes `00 01 00 10`: **low byte = x-unit code, upper bytes
`01 00 10` = the same structural marker the modern format stores at `0xA1..0xA3`.**

- code `0x00` = wavenumber, cm⁻¹ (all 385 files; CSV exports all say `XUNITS 1/CM`) — **verified**.
- code `0x03` = nm: not present locally, but jws2txt maps `0x10000103` to
  "WAVELENGTH" for CD spectrometers, and `0x03` = nm in the modern format's
  x-unit byte — **corroborated**.
- jws2txt also maps `0x20000103` to "TIME" (kinetics `.jwb`), suggesting byte 3
  (`0x10` here) is an axis-class marker (0x10 spectral, 0x20 time) — **corroborated, untested**.

There is no other x-unit field in the file. For FTIR corpus files the answer to
"is there an x-unit code?" is **yes**: the low byte of word `0x30` (always 0 = 1/CM here).

### 4.2 y-mode code (word @ `0x34`) → `YUNITS`

Low byte of the channel descriptor. Verified against paired CSV exports
(`YUNITS` header field) and filename semantics:

| Code | `YUNITS` | Corpus count | Evidence | Confidence |
|---|---|---|---|---|
| `0x00` | `TRANSMITTANCE` (%T) | 374 | every paired CSV says `YUNITS,TRANSMITTANCE` / 縦軸 %T | **high (CSV-verified)** |
| `0x03` | `ABSORBANCE` | 4 | all named `Abs_*` / fit; y ∈ [−0.024, 5.0]; same code as modern format and jws2txt | **high** |
| `0x08` | `INTENSITY` (single-beam) | 7 | all named `BG*` / `background*`; positive, intensity-shaped | **medium-high** (filename + shape; no CSV pair exists for these) |
| other | reject / `UNKNOWN` | 0 | modern vocabulary (`0x02` %R, `0x09/0x0A` UV single-beam) likely carries over | — |

Note the %T data are stored as *percent* (values up to ~100 in normal cells; the
cavity-transmission corpus mostly sits ≪ 1 %, one bad 100 %-line file reaches 5575).

### 4.3 Descriptor slots 3–4

In every (single-channel) corpus file, words `0x38`/`0x3C` repeat words
`0x30`/`0x34` exactly. jws2txt reads all four words `0x30..0x3F` as a flat list of
axis/channel descriptors and de-duplicates, which is consistent with either
"x,y pair per channel-slot" or "x + up to 3 y-channels". With only single-channel
files locally this cannot be discriminated — **a reader should decode channel 1
from word `0x34` and require word `0x38..0x3F` == word `0x30..0x37` for
single-channel files, rejecting anything else until a multi-channel sample exists.**

## 5. `Y-Data` stream

- Raw `Float32` array, **no header**: `sizeof == 4 × nchan × NPOINTS` in 385/385.
- Channel-major when nchan > 1 (per prior art; locally always 1 channel).
- Order follows the x grid (`y[1]` at FIRSTX; FTIR grids ascend).
- Convert to Float64 for use; the x axis is `FIRSTX .+ DELTAX .* (0:NPOINTS-1)`.

### 5.1 Invalid-point sentinel

**306/385 files contain the value `-1.17549435e-38` (= −FLT_MIN, bits `0x80800000`)**
in runs inside the data, where the instrument's %T/Abs computation was invalid
(detector-dead regions, saturated ratio, …). This is *data, not corruption*:
JASCO's own CSV export prints these points literally as `-1.17549E-038`.
Derived (spectra-arithmetic) files can contain small multiples (e.g. −2×FLT_MIN in
the "add A + B" file). A reader should pass them through by default (CSV parity);
an optional cleanup to `NaN` (`|y| < 1e-30`) is a reasonable convenience flag.

## 6. Strings, TLV records, dates (shared primitives)

- **String** = `UInt32` byte length **including** the 2-byte null terminator,
  then UTF-16LE code units. Length 0 = absent; length 2 = present-but-empty.
  Encoding is UTF-16LE throughout the container — **not** Shift-JIS (Japanese
  company names decode as UTF-16; the Shift-JIS in CSV exports is an export artifact).
  (Two streams pad an extra `UInt16 0` after a string — see §9/§12; treat as
  stream-specific, not part of the string primitive.)
- **TLV record** = `[UInt32 tag][UInt16 type][value]` with value types
  `2` = UInt16, `3` = UInt32, `4` = Float32, `5` = Float64, `8` = string (as above).
  Used by `MeasParam` and the `SampleInfo` tail.
- **Date** = OLE Automation date: Float64 days since 1899-12-30, **stored in UTC**.
  Verified: 180/180 paired exports show the CSV's local 測定日時 exactly
  +9 h (JST) from the stored value; CFB directory FILETIMEs (UTC by spec) agree
  with the stored doubles to the second.
  **Null sentinel: exactly `36494.0` (= 1999-11-30)** — occurs in 3 corpus files;
  treat as "no timestamp" (also treat ≤ 0 as missing).

## 7. `SampleInfo` stream

`[UInt32 1][string sample name][string comment][UInt32 nrec][TLV × nrec]`

- Corpus: name empty in 385/385 (the GUI's 試料名 was never filled); comment
  non-empty in 3 files; `nrec` = 1 with `tag 1, type 5` = **measurement datetime**
  (equals MeasParam tag 12), or `nrec` = 0 in the 4 CSV-import files.
- CSV-export correspondence: 試料名 (sample name), コメント (comment). **Verified**
  (the 3 comments and all the empties round-trip).

## 8. `UserInfo` stream

`[UInt32 3][string × 15]` — exactly 15 length-prefixed slots in 385/385 files.

- **Slot 12 = company / organization** ("NAIST" in 343 files,
  奈良先端科学技術大学院大学 in 38) — matches CSV footer 会社. **Verified.**
- Slot 1 = `"F305_SmallPC"` (a computer name) in the 4 CSV-import files only — observed.
- All other slots empty corpus-wide. The CSV footer also lists 測定者 (operator)
  and 所属 (department); they are presumably among slots 1–11/13–15 but cannot be
  assigned from this corpus (never filled). **Unknown which slot is which.**

## 9. `ModuleInfo` + `MeasInfo` streams

`ModuleInfo` = `[UInt32 2][string module name][UInt16 0][UInt16 module id]`
`[string model][string serial][trailing zeros]`

| Field | Values | Confidence |
|---|---|---|
| module name | `""` (378) or `"FT/IR-4600"` (7 — exactly the single-beam/background files) | observed |
| module id | `0x0009` = FTIR main unit (381); `0x0FFF` = none (4 CSV-import files) | verified |
| model | `"FT/IR-4600typeA"` (381) or empty (4 imports) — matches CSV 機種名 | **verified** |
| serial | `"E137161786"` (381) or empty — matches CSV シリアル番号 | **verified** |

`MeasInfo` (8 B) = `[UInt32 1][UInt16 0][UInt16 module id]` — same id as ModuleInfo
(9 or 0x0FFF). Verified 385/385.

The reader needs `model` (the instrument string drives `datatype`/`xunits`
decisions in JASCOFiles) and must tolerate the empty-model CSV-import variant.

## 10. `MeasParam` stream — acquisition parameters

`[UInt32 1][UInt32 1][UInt32 nrec][TLV × nrec]`

- `nrec` = 44 with an identical tag sequence in 381/381 instrument-measured files;
  `nrec` = 0 (12-byte stream) in the 4 CSV-import files.
- Tag table (CSV-footer-verified tags shown with their footer key):

| Tag | Type | Meaning | Evidence | Confidence |
|---|---|---|---|---|
| 1 | UInt32 | **Accumulation** (積算回数) | =64 vs CSV 64; distribution 128/64/32/16/… | **verified** |
| 2 | Float32 | **Resolution** cm⁻¹ (分解) | 2.0/4.0/1.0/0.7 ↔ CSV | **verified** |
| 3 | Float32 | **Aperture** mm (アパーチャー) | 5.0 ↔ "Auto (5 mm)"; also 7.1/3.5/2.5/0.5 | **verified** |
| 4 | Float32 | **Scan speed** mm/s (スキャンスピード) | 2.0 ↔ "Auto (2 mm/sec)" | **verified** |
| 5 | UInt32 | — | 0 always | unknown |
| 6 | Float32 | **Gain** (ゲイン) | 128 ↔ "Auto (128)"; not accumulations! | **verified** |
| 7,9 | UInt16 | — | 0 always | unknown |
| 8 | UInt16 | zero-filling? | 1 always; CSV ゼロフィリング "On" always | observed |
| 12 | Float64 | **Measurement datetime** (測定日時, OLE UTC) | +9 h = CSV in 180/180 | **verified** |
| 13 / 14 | Float32 | **Requested range start / end** cm⁻¹ | 1000/6000 etc.; tags 55/56 duplicate them | verified |
| 15 | Float32 | — | 1.0/3.0/4.0/0.3/…/10000.0 | unknown |
| 16 | Float32 | — | −0.05 or 0.0 | unknown |
| 21 / 22 | Float32 | **Measured FIRSTX / LASTX** | ≈ DataInfo doubles (Float32 precision) | verified |
| 23 | Float64 | **Raw (pre-zero-fill) data interval** | = 2 × DELTAX in 381/381 (zero-fill On) | verified relation |
| 32 | UInt32 | **Filter** Hz (フィルタ) | 30000 ↔ "Auto (30000 Hz)" | **verified** |
| 47 | string | **Light source** (光源) | `標準光源` | **verified** |
| 48 | string | **Detector** (検出器) | `TGS` | **verified** |
| 50 | UInt16 | apodization/zero-fill enum pair? | `0x0501` (378), `0x0602` (3 × 2019-era files); CSV always "Cosine"/"On" | observed, **unverified** |
| 51 | UInt16 | ordinate-mode enum? | `0x0602` in all %T files, `0x0603` in all 4 Abs files | observed correlation |
| 24,25,33–45,49,52,55,56 | misc | constants / display range dups | see decoder survey | observed |

Resolution ↔ DELTAX mapping (FT/IR-4600, zero-filling On — **verified, exhaustive**):

| Resolution (tag 2) | DELTAX (cm⁻¹) | files |
|---|---|---|
| 0.7 | 0.120529 | 12 |
| 1.0 | 0.241058 | 3 |
| 2.0 | 0.482117 | 352 |
| 4.0 | 0.964233 | 14 |

(i.e. DELTAX = tag23/2; tag23 = the interferogram-derived point spacing.)

## 11. `BaseInfo` stream

`[UInt32 1][16-byte GUID][UInt8 0][string original save path]`
`[Float64 date saved][Float64 date measured][UInt32 nsources][source records…]`

- Original path: full Windows path of the file when saved
  (`D:\FTIR_EXPERIMENTS\210617\….jws`) — 385/385 non-empty. Useful provenance;
  the folder component matches the lab's date-folder convention.
- date saved ≥ date measured; date saved matches the CSV header `DATE`/`TIME`
  (+9 h) when the CSV was exported in the same session; date measured equals
  MeasParam tag 12 / SampleInfo tag 1. **Verified.**
- `nsources` = 0 in 384/385. The one derived file ("add parallel 2 and
  perpendicular 2") has `nsources` = 1 followed by a source record
  (`[UInt32 1][GUID][UInt8 0][string source path]` — structure observed once);
  treat anything after the trailing count as informational.

## 12. `Histories` stream

`[UInt32 1][UInt32 nrec][records…]` — nrec 0–5 in the corpus (0 in 162 files).
Record ≈ `[UInt32 1][string computer name][UInt16 0][Float64 OLE date][string action]`,
e.g. `"Peak Find : Source=Memory-9, Method=Bottom, Noise Level=0.1, Add=2201.35, 2134.81"`,
`"Import : Source=D:\…\file.csv"` (the CSV-import files), `"FWHM : …"`.

Caveat: the byte gap between the computer-name string and the date is 2 bytes in
some files and 4 in others (writer-version difference; both occur). Parse
tolerantly (scan for a plausible OLE-date double) or skip — the stream is purely
a processing log. **Diagnostic value only:** an `Import :` first record identifies
re-imported files; nrec > 0 identifies post-processed spectra.

## 13. `Results` storages

`Results/Result-N/{Data, Param, Default}` hold analysis-tool outputs (peak-find
tables — pairs of Float64 (height, position in cm⁻¹) matching known DPPA bands;
FWHM results; fit parameters; a GUID + timestamp in `Default`). Present in
218/385 files. **They never affect the main spectrum**: `DataInfo`/`Y-Data`
decode identically with or without them (verified — all 218 decode and
cross-check like the rest). A reader can ignore them, or surface
`length(Result-N)` as metadata.

## 14. Field sources for a `JASCOSpectrum`-style reader

| Target field | Source | Fallbacks |
|---|---|---|
| `x` | `FIRSTX .+ DELTAX .* (0:NPOINTS-1)` (DataInfo) | — |
| `y` | `Y-Data` Float32 → Float64 | — |
| `title` | SampleInfo name | filename stem (corpus titles are all in filenames; CSV exports show empty `TITLE`) |
| `date` | MeasParam tag 12 (UTC) | SampleInfo tag 1; BaseInfo date-measured; `nothing` on sentinel 36494.0 |
| `spectrometer` | ModuleInfo model | `""` for CSV imports |
| `datatype` | `"INFRARED SPECTRUM"` when model starts `FT/IR` (CSV parity) | reject other models until samples exist |
| `xunits` | `"1/CM"` from x-descriptor low byte 0 | reject other codes |
| `yunits` | §4.2 code map | reject unknown codes |
| metadata | §7–§13 (serial, company, comment, accumulation, resolution, aperture, scan speed, gain, filter, source, detector, original path, ranges) | |

## 15. Validation gates (recommended chain, modern-spec style)

In order; first failure throws with `basename(path)` prefix:

1. **CFB magic** — first 8 bytes; else not a legacy `.jws` (try modern reader on `L~S `).
2. **Sector sanity** — sector size ∈ {512, 4096}; root entry exists.
3. **Required streams** — `DataInfo` and `Y-Data` present.
4. **Container identity** — `Header` stream starts `"L~"` and contains `"SPCMAN"`.
5. **DataInfo shape** — 96 bytes; version word == 3; `NPOINTS` > 1; nchan ≥ 1.
6. **x descriptor** — word`@0x30` == `0x10000100` (wavenumber); else unsupported
   axis (could be nm/time variant — "please share this file").
7. **y-mode code** — word`@0x34` low byte ∈ {0x00, 0x03, 0x08}; else throw
   (unknown code).
8. **Channel-slot consistency** — words `@0x38..0x3F` == words `@0x30..0x37`
   (single-channel); else multi-channel variant — reject until a sample exists.
9. **Y-Data size** — `== 4 × nchan × NPOINTS` exactly.
10. **Grid** — `DELTAX` finite and nonzero; `|FIRSTX + DELTAX×(NPOINTS−1) − LASTX| ≤ |DELTAX|`
    (soft; warn only — stored LASTX wobbles by ≤ 0.0033 cm⁻¹ in real files).

## 16. Corpus survey results (decoder `legacy_decode.jl`, 2026-06-11)

- **Decoded: 385/385, zero failures.** 6 modern-format files skipped by magic.
- y-mode codes: `0x00` × 374 (%T), `0x03` × 4 (Abs), `0x08` × 7 (single-beam BG).
- Instruments: `FT/IR-4600typeA` × 381; empty (CSV import) × 4.
- x grids (firstx, lastx, deltax, npoints) — 13 variants, dominated by:
  - (999.9101, 6000.4249, 0.482117, 10373) × 315
  - (499.9551, 7800.1667, 0.482117, 15143) × 27
  - (499.4729, 7800.6488, 0.964233, 7573) × 13
  - (999.9101, 7000.335, 0.482117, 12447) × 12
  - (499.9551, 7800.0461, 0.120529, 60568) × 8
  - plus single-beam grids starting at 0.0 cm⁻¹ (0–7800, ×3) and 6 more small variants;
    npoints ∈ [7573, 60568]; firstx ∈ {0, 499.47, 499.96, 999.91}; lastx ∈ [6000.06, 8000.25].
- Dates: measurement date matches the parent date-folder (±1 day) in **382/385**;
  the other 3 store the 36494.0 sentinel (no timestamp).
- Sentinel −FLT_MIN values present in 306/385 files.
- Variants encountered and handled: 4096-byte sectors (111), CSV re-imports (4),
  derived/computed spectrum with provenance record (1), single-beam ModuleInfo
  with module-name string (7), `Results` storages (218), placeholder dates (3).

### Ground-truth cross-check (184 paired exports)

Method: decode `.jws`, parse the same-basename CSV with JASCOFiles' CSV reader,
compare npoints, x, y, YUNITS, FIRSTX/DELTAX headers, measurement timestamp.

- 1 pair auto-skipped as a **different acquisition** (footer 測定日時 differs from
  the jws by 22 min — the CSV is from a re-measurement; detection by timestamp works).
- 2 "exports" are not JASCO spectrum files (a peak-fit table; a header-less
  `XYDATA`-only dump). The header-less dump was compared manually:
  **10373/10373 y values agree**.
- Of the **183** parseable same-acquisition pairs: **177 fully consistent** under
  strict gates; the remaining 4 (+2 above) differ **only** in the export's printed
  x column (≤ 0.0037 cm⁻¹, JASCO's export accumulates x in single precision;
  FIRSTX/DELTAX headers and all y values agree).
- **y agreement: 100 % of compared points in all 182 numerically compared pairs**
  (tolerance: 6 significant digits, the CSV print precision).
- Timestamps: **180/180** pairs with footer dates sit at exactly +9 h (JST) from
  the stored UTC value.

## 17. Open questions

1. **Multi-channel files** — nchan > 1 never occurs locally; channel-major
   `Y-Data` layout and descriptor-slot semantics are prior-art only (gate 8 rejects).
2. **UserInfo slots** other than 12 (operator/department never filled here).
3. **MeasParam tags** 5, 7, 9, 15, 16, 49, 50, 51 and the constant block —
   semantics unknown/probable only (tag 51 ↔ %T/Abs correlation is suggestive).
4. **x-unit codes** other than 0 (cm⁻¹): nm (3) corroborated via prior art +
   modern-format vocabulary, none local; time-axis files (`.jwb`) untested.
5. **`Header` words at 0x04** (`0x0001`, `0x8401`) — constant, meaning unknown.
6. **Histories record padding** — 2 vs 4 byte gap before the date double;
   writer-version detail, parse tolerantly.
7. **Non-equidistant data** (`X-Data` stream) — never observed; reject if seen.

---

## Addendum (2026-06-11): NRS-5100 Raman variant

A second corpus under `Raw Data/Raman/20241203/` (19 files, NRS-5100, all
with paired CSV exports) extended the format beyond the FTIR survey above:

- **x-axis descriptor** `0x10000101`: low byte `0x01` = Raman shift. The
  marker bytes (`01 00 10`) are unchanged, so the reader validates
  `(xdesc & 0xFFFFFF00) == 0x10000100` and maps the unit code:
  `0x00 → INFRARED SPECTRUM`, `0x01 → RAMAN SPECTRUM` (both `1/CM`).
- **Non-linear axis**: `DELTAX = 0` and an **`X-Data` stream** (Float32,
  exactly `4 × npoints` bytes) carries the explicit CCD wavenumber axis.
  Monotonic in all files; `FIRSTX` equals `x[1]` to Float32 precision.
- **y-mode `0x0e`** = Raman CCD intensity (`INTENSITY`; matches the paired
  CSV exports' `YUNITS`). Not observed in the modern flat format.
- **`ModuleInfo` id `0x1009`** (4105) for the NRS-5100 main unit. The
  MeasParam **tag namespace is per module type**: e.g. tag 1 is the FTIR
  accumulation count (UInt32) but the Raman exposure time (Float32 60.0).
  The named-tag mapping therefore applies only to module id `0x0009`
  (FTIR); other modules keep raw `MeasParam.tag<N>` keys.
- **Date**: Raman files have no MeasParam tag 12 and an empty SampleInfo
  record list; `BaseInfo.d_measured` (UTC) is the source, verified +9 h
  against the paired CSV exports' JST wall-clock `DATE`/`TIME`.

Validation after the extension: **451/451** `.jws`/`.jrs` files under
`Raw Data/` decode (426 legacy FTIR, 19 legacy Raman, 6 modern), all with
real measurement dates. Raman parity vs paired CSV: max |Δx| ≤ 5×10⁻⁵,
max |Δy| ≤ 5×10⁻⁴ (export print precision) at all 1024 points.
