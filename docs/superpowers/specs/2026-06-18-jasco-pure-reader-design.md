# JASCOFiles 3.0.0 — Pure Reader

**Date:** 2026-06-18
**Status:** Approved (design); ready for implementation plan
**Scope:** JASCOFiles.jl only (OpticalSpectroscopy.jl is already the rightful owner and needs no code change; one CLAUDE.md line is added there)

## Problem

JASCOFiles.jl (a JASCO instrument-file reader; deps: `Dates` + `StringEncodings`)
and OpticalSpectroscopy.jl (the analysis layer; ~12-dep stack) both define four
generically-named verbs as independent generic functions on disjoint types:

- `transmittance_to_absorbance`
- `absorbance_to_transmittance`
- `xlabel`
- `ylabel`

When both packages are loaded together (the lab layer, QPSTools, does
`using JASCOFiles, OpticalSpectroscopy`), the identically-named exports produce
ambiguous bindings in `Main`. The clash is purely at the binding/name level —
the methods dispatch on disjoint argument types (`JASCOSpectrum` vs
`Spectrum`/`AbstractSpectroscopyData`), so there is no method-table ambiguity.

This has been re-litigated repeatedly (the June 10 `percent`-default audit, the
2.0 unit-aware rewrite, the unreleased 3.0 unexport). Each round managed a
*symptom*. The root cause is that **two packages own a second copy of the same
physics**, with already-divergent contracts (NaN policy, unit stamps, and
historically opposite `percent` defaults). As long as both copies exist, the
"what does JASCOFiles export / how do we avoid the clash" question stays alive.

### Decisive findings from the adversarial review

- **Zero downstream consumers** of JASCOFiles' four verbs on a `JASCOSpectrum`.
  QPSTools' `load_spectrum` (`QPSTools.jl/src/io.jl:436-459`) converts
  `JASCOSpectrum → Spectrum` and discards the reader struct; every live T↔A and
  label call in the lab stack resolves to OpticalSpectroscopy, on plain vectors.
  Two independent grep sweeps across QPSTools/QPSLab/QPSDrive found no callers.
- The **only in-tree caller** of the reader's `xlabel`/`ylabel` is JASCOFiles'
  own Makie extension (`ext/JASCOFilesMakieExt.jl:44-47`), which already calls
  them qualified.
- **OpticalSpectroscopy is the rightful owner**: it defines `xlabel`/`ylabel`
  as a core interface contract over `AbstractSpectroscopyData` (alongside
  `xdata`/`ydata`/`zdata`), plus a far larger transform family (Kramers-Kronig,
  Kubelka-Munk, Tauc, Beer-Lambert, SNV, unit conversions, a token-based
  `axis_label` machinery). JASCOFiles' versions are a divergent subset.
- The project's stated layering rule assigns unit conversions and spectral math
  to the analysis layer and gives the reader only instrument-specific I/O.
- **Release state:** v2.0.0 is live/registered (exported all four). The local
  3.0.0 unexport commit (`2d6e506`) is unpushed (`origin/main` is at the 2.0
  merge `d9dd7c0`), untagged, unregistered. So 3.0.0 is ours to redefine — this
  is one clean major bump, not a stacked pile-up.

### Rejected alternatives (from the review)

- **Shared `SpectraBase` package** owning the verb stubs: correct *end-state*
  but premature. A shared stub unifies *dispatch*, not *behavior* (the two
  method bodies key off `String` yunits vs `Symbol` tokens and stay divergent),
  so its headline benefit is false today; it also requires a new General
  registration (~3-business-day AutoMerge) to host verbs with no callers. Defer
  to its real Phase-2 trigger (a genuine third consumer of the shared interface).
- **Rename to `jasco_*`**: enshrines the layering violation in syllables and
  freezes the duplicate physics permanently, with no compiler signal against
  drift.
- **Status quo (keep all four public-but-unexported)**: a non-decision. It
  hides the binding clash but keeps the divergent duplicate and the drift
  hazard, so the churn-driver remains.

## Principle (the durable cure)

The code changes are an application of one invariant, written into both repos'
`CLAUDE.md` so it is never re-litigated:

> The reader emits raw data plus format-native unit strings (`xunits`/`yunits`).
> It owns **no transforms and no axis labels**. All unit conversions and
> presentation belong to the analysis layer (OpticalSpectroscopy).

## Design

### 1. Core module: remove transforms and labels

- Delete `src/transforms.jl` (`transmittance_to_absorbance`,
  `absorbance_to_transmittance`).
- Delete `src/plotting.jl` from the core module (its logic moves — see §2).
- `src/JASCOFiles.jl`: drop the `include("transforms.jl")` and
  `include("plotting.jl")` lines and the unexport-rationale comment block
  (current lines 35-40). The export list is unchanged and now matches the
  public API exactly:

  ```julia
  export AbstractJASCOSpectrum, JASCOSpectrum
  export isftir, israman, isuvvis
  ```

The core module's includes become: `types.jl`, `translations.jl`, `parser.jl`,
`binary.jl`, `legacy.jl`, `utils.jl`.

### 2. Axis labels move into the Makie extension (decision: option B)

The label logic has one real consumer — the `plot(s)` recipe. Move it there.

- In `ext/JASCOFilesMakieExt.jl`, add private helpers `_xlabel(s)` / `_ylabel(s)`
  carrying the exact logic currently in `src/plotting.jl` (the `1/CM` →
  "Wavenumber (cm⁻¹)" / Raman-shift switch; the `NANOMETERS` → "Wavelength (nm)"
  case; the `ABSORBANCE`/`INTENSITY`/`TRANSMITTANCE`/`TRANSMITTANCE_FRAC` y-cases;
  the `titlecase` fallback). They call `israman(s)` (exported) and read
  `s.xunits`/`s.yunits`.
- Update `Makie.plot`'s `default_axis` to use `_xlabel(s)`/`_ylabel(s)` instead
  of `JASCOFiles.xlabel(s)`/`JASCOFiles.ylabel(s)`. `isftir(s)` is exported, so
  it can stay as-is or be unqualified.
- Update the `plot` docstring (its "Axis defaults" lines reference `xlabel(s)` /
  `ylabel(s)`).

Result: the core reader is 100% transform/label-free; labels exist only where
they are used, and only when a Makie backend is loaded (the only time they are
wanted).

### 3. Tests (`test/runtests.jl`)

- Remove the `using JASCOFiles: transmittance_to_absorbance,
  absorbance_to_transmittance, xlabel, ylabel` import (lines 5-6).
- Delete testset **"transmittance ↔ absorbance (unit-aware, 2.0)"** (324-373).
- Delete testset **"conversion guards (2.0)"** (375-390).
- Fold the **"axis labels"** testset (392-422) into the **"Makie extension"**
  testset as `ax.xlabel[]` / `ax.ylabel[]` assertions, covering: FTIR
  ("Wavenumber (cm⁻¹)" / "Absorbance"), Raman ("Raman shift (cm⁻¹)" /
  "Intensity"), UV-Vis ("Wavelength (nm)"), %T and fractional transmittance
  y-labels, an unknown-units title-case fallback, and the empty-units → empty
  label case. Build synthetic spectra where needed and assert through `plot(s)`.
- **"binary vs .txt ground truth"** (563-564): replace
  `xlabel(bin) == xlabel(txt)` / `ylabel(...)` with reader-level unit parity:
  `bin.xunits == txt.xunits`, `bin.yunits == txt.yunits` (and `datatype` if
  useful).
- **Legacy .jws** (716-718): replace the `transmittance_to_absorbance(t)`
  assertion with the reader-level fact it was really checking —
  `@test t.yunits == "TRANSMITTANCE"`.
- The existing "Makie extension" testset's label assertions (439-440, 453)
  continue to pass unchanged, since labels still resolve through `plot(s)`.
- Aqua's `test_all` remains green (pure deletion; one fewer
  unexported-public-name oddity).

### 4. Docs

- **`README.md`**: remove the T↔A block from "Convenience features" (lines
  60-67); keep the copy-constructor (69-70) and metadata-alias (72-76) examples.
- **`docs/src/index.md`** (136-141): remove the `JASCOFiles.xlabel(s)` /
  `ylabel(s)` "for full control" paragraph and its code block. Point standalone
  users to `s.x`/`s.y` directly, and to OpticalSpectroscopy for conversions and
  formatted labels. The `plot(s)` Makie section (121-134) stays — it still works.
- **`docs/src/lib/public.md`**: delete the "## Transmittance ↔ absorbance
  conversions" section (39-45) and the "## Plotting helpers" section (47-55);
  remove the `[xlabel](@ref)` / `[ylabel](@ref)` cross-references in the
  "Plotting with Makie" section (71-72), rewording to "axis defaults are derived
  from the spectrum's units." Line 7 ("Only exported types and functions are
  considered part of the public API") becomes **true again** and needs no edit —
  the contradiction the review flagged disappears because nothing public is left
  unexported.

### 5. CLAUDE.md (cross-package invariant)

- **`JASCOFiles.jl/CLAUDE.md`**: update the Package Structure tree (no
  `transforms.jl`, no `plotting.jl`; note label helpers live in the Makie
  extension); remove `transmittance_to_absorbance`, `absorbance_to_transmittance`,
  `xlabel`, `ylabel` from the Public API list; add the Principle statement above.
- **`OpticalSpectroscopy.jl/CLAUDE.md`**: add the reciprocal line —
  OpticalSpectroscopy owns all unit conversions and axis labels; file-reader
  packages emit raw data plus format-native unit strings only. This is the
  cross-package invariant that ends the churn.
- (Optional) the user's global `~/.claude/CLAUDE.md` ecosystem notes can gain
  the same one-liner; not required for the release.

### 6. Release mechanics

- Replace the unpushed local commit `2d6e506`: reset to `origin/main`
  (`d9dd7c0`) and make one clean commit implementing this spec. Project.toml
  stays at **`3.0.0`** — a correct major bump from the live v2.0.0, since
  removing exported API is breaking.
- Add a short **`NEWS.md`** (no changelog exists today) documenting 3.0.0 with a
  migration note:
  > **3.0.0** — JASCOFiles is now a pure reader. `transmittance_to_absorbance`,
  > `absorbance_to_transmittance`, `xlabel`, and `ylabel` are removed. Use
  > OpticalSpectroscopy on a `Spectrum` for conversions and labels, or
  > `-log10.(s.y ./ 100)` for a quick standalone %T→A.
- Do not post the JuliaRegistrator trigger as part of this work — registration
  is a separate, explicitly-approved step after merge to `main`.

## Pre-flight check

Before deleting, re-run one sweep to re-confirm zero external callers (the
review already found none):

```
rg -n "JASCOFiles\.(transmittance_to_absorbance|absorbance_to_transmittance|xlabel|ylabel)" ~/Developer
rg -n "using JASCOFiles:.*\b(transmittance_to_absorbance|absorbance_to_transmittance|xlabel|ylabel)\b" ~/Developer
```

If either returns a hit outside JASCOFiles itself, pause and reassess that call
site before proceeding.

## Out of scope (deliberately deferred)

- Building `SpectraBase`/`SpectraCore`. Revisit only when a genuine third
  consumer needs the shared spectrum interface (the roadmap's Phase-2 trigger).
- Any change to OpticalSpectroscopy's code or its transform/label API.
- Renaming or re-exporting the four verbs anywhere.

## Acceptance criteria

- `using JASCOFiles, OpticalSpectroscopy` produces no ambiguous-binding warning
  for the four names (they no longer exist in JASCOFiles).
- `Pkg.test()` passes, including Aqua.
- The `plot(s)` Makie recipe still fills axis labels, title, and `xreversed`
  exactly as before (verified via `ax.xlabel[]` etc.).
- JASCOFiles' public surface is exactly its export list; `docs/src/lib/public.md`
  is internally consistent.
- Both `CLAUDE.md` files state the reader-owns-no-transforms/labels invariant.
- Project.toml is `3.0.0`; `NEWS.md` documents the breaking change and migration.
