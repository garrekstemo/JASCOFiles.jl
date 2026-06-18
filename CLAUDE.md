# JASCOFiles.jl

Reads JASCO spectrometer files into a `JASCOSpectrum`: CSV/text exports and native binary `.jws`/`.jrs`. Analysis-free reader layer (see ecosystem map in global CLAUDE.md).

## Orientation

Entry point `src/JASCOFiles.jl` (module + `include` order); browse `src/` for the rest. The type lives in `src/types.jl`; parsing/dispatch in `src/parser.jl`; binary readers in `binary.jl` (modern) and `legacy.jl` (OLE). Makie plotting and Tables interop are weakdep **extensions** (`ext/JASCOFilesMakieExt.jl`, `ext/JASCOFilesTablesExt.jl`), backed by `[weakdeps]` Makie + Tables. Format design specs in `docs/superpowers/specs/`.

## Public API split (v3.0.0 unexport refactor)

- **Exported:** `JASCOSpectrum`, `AbstractJASCOSpectrum`, `isftir`, `israman`, `isuvvis`.
- **NOT exported (public, call qualified):** `JASCOFiles.transmittance_to_absorbance`, `absorbance_to_transmittance`, `xlabel`, `ylabel` (in `plotting.jl`). Names are generic and collide with OpticalSpectroscopy, which exports the same verbs — qualifying avoids ambiguous bindings.

`JASCOSpectrum` has three constructor forms (see `src/types.jl`): path parser `JASCOSpectrum(path; encoding=enc"SHIFT-JIS", translate=true)`, keyword form (only `x`, `y` required), and a copy constructor (replace a subset of fields, share the rest).

## Honesty invariants

Fields are never fabricated: `date` is `nothing` when the file has no parseable timestamp; `spectrometer` is `""` when absent.

## Transform unit semantics

- `transmittance_to_absorbance`: scale inferred from `yunits` — `"TRANSMITTANCE"` = %T (0–100), `"TRANSMITTANCE_FRAC"` = 0–1; explicit `percent` overrides (and is required for any other `yunits`). Output `yunits = "ABSORBANCE"`; nonpositive T → `NaN`.
- `absorbance_to_transmittance`: `percent` is a **required** keyword (`true` → %T / `"TRANSMITTANCE"`, `false` → `"TRANSMITTANCE_FRAC"`).

## File format

Text files: header key-values → `XYDATA` marker → x,y data → optional footer (separated by a blank line). Delimiter (comma/tab) auto-detected from the first header line. Footer Japanese keys/values are translated to English via dual-key aliases (e.g. `metadata["積算回数"]` and `metadata["Accumulation"]` both resolve); pass `translate=false` to disable. Tables in `src/translations.jl`. Full field reference in the specs under `docs/superpowers/specs/`.

Default encoding is SHIFT-JIS.

**Binary:** modern `.jws`/`.jrs` use the SPECMAN/SPECIRM flat format; legacy `.jws` (Spectra Manager 1.x) use an OLE2/CFB container. Both share the `.jws` extension and are distinguished by magic-byte dispatch in `parser.jl`.

## Supported instruments

| Instrument | DATA TYPE | Notes |
|------------|-----------|-------|
| FTIR | `INFRARED SPECTRUM` | text + binary |
| Raman | `RAMAN SPECTRUM` | text + legacy binary |
| UV-Vis | `UV/VIS SPECTRUM`, or blank (V-series) | text + binary |

**V-730 quirk:** V-series UV-Vis files use tab separators and leave `DATA TYPE` blank. `isuvvis` infers UV-Vis from `xunits == "NANOMETERS"` and a 100–3500 nm wavelength range when `DATA TYPE` is empty.
