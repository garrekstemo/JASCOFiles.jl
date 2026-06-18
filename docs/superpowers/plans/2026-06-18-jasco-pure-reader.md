# JASCOFiles 3.0.0 Pure-Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make JASCOFiles a pure reader for its 3.0.0 release by removing the four collision verbs (`transmittance_to_absorbance`, `absorbance_to_transmittance`, `xlabel`, `ylabel`) from its public API; the analysis layer (OpticalSpectroscopy) keeps ownership.

**Architecture:** Delete `src/transforms.jl`; move the axis-label logic into the Makie extension as private `_xlabel`/`_ylabel` (its only consumer); update tests to assert reader-level facts and to test labels via the loaded extension; refresh docs; write the "reader owns no transforms/labels" invariant into both repos' `CLAUDE.md`. The work happens on branch `pure-reader-3.0`, rebased onto the live v2.0.0 release so the unpushed band-aid commit (`2d6e506`) is dropped and history is one clean 3.0.0.

**Tech Stack:** Julia 1.10+ package; `Test` + `Aqua` test suite; Documenter docs; Makie package extension; git.

**Spec:** `docs/superpowers/specs/2026-06-18-jasco-pure-reader-design.md`

**Baseline note:** The true starting point is the live **v2.0.0** release (`origin/main` = `d9dd7c0`), where all four verbs are **exported** and called **bare** in tests/docs. The local `2d6e506` "unexport" commit is a band-aid that this plan discards (Task 1). Do not assume the band-aid's qualified/unexported state — work from v2.0.0.

---

### Task 1: Drop the band-aid commit, keeping the doc commits, to reach a clean v2.0.0 baseline

**Files:** git history only (branch `pure-reader-3.0`).

The branch currently sits on top of the unpushed band-aid `2d6e506` (the
"unexport" commit). We excise just that commit and replay the two doc commits
(spec + this plan) directly onto the v2.0.0 release `d9dd7c0`. The doc commits
only add files under `docs/superpowers/`, so the replay is conflict-free and
the working tree lands on the true v2.0.0 source (four verbs **exported**;
`src/transforms.jl` and `src/plotting.jl` present; `Project.toml` = `2.0.0`).

- [ ] **Step 1: Confirm where you are**

Run:
```bash
cd ~/Developer/JASCOFiles.jl
git branch --show-current          # expect: pure-reader-3.0
git log --oneline -4               # expect: <plan> -> <spec> -> 2d6e506 (band-aid) -> d9dd7c0
git rev-parse origin/main          # expect: d9dd7c0... (the v2.0.0 release)
git status --short                 # expect: clean
```

- [ ] **Step 2: Rebase the doc commits off the band-aid onto v2.0.0**

Run:
```bash
git rebase --onto d9dd7c0 2d6e506
```
Expected: the spec and plan commits replay cleanly onto `d9dd7c0`; the band-aid
`2d6e506` is dropped. No conflicts (the replayed commits touch only
`docs/superpowers/` files). If git reports "up to date" or a conflict, STOP and
recheck the SHAs (`2d6e506` = band-aid, `d9dd7c0` = `origin/main`).

- [ ] **Step 3: Verify clean baseline**

Run:
```bash
git log --oneline -3               # expect: <plan> -> <spec> -> d9dd7c0 (no 2d6e506)
grep -c "export xlabel, ylabel" src/JASCOFiles.jl    # expect: 1 (still exported at 2.0)
grep '^version' Project.toml        # expect: version = "2.0.0"
ls src/transforms.jl src/plotting.jl docs/superpowers/specs/2026-06-18-jasco-pure-reader-design.md   # all exist
```
No commit needed — the rebase rewrote the branch in place. (`main` still points
at the band-aid `2d6e506`; that is reconciled at finalization, Task 8 Step 5.)

---

### Task 2: Pre-flight — confirm zero external callers of the four verbs

**Files:** none (verification only).

- [ ] **Step 1: Sweep the whole ecosystem**

Run:
```bash
rg -n "JASCOFiles\.(transmittance_to_absorbance|absorbance_to_transmittance|xlabel|ylabel)" ~/Developer
rg -n "using JASCOFiles:[^\\n]*\b(transmittance_to_absorbance|absorbance_to_transmittance|xlabel|ylabel)\b" ~/Developer
```
Expected: **no hits outside `~/Developer/JASCOFiles.jl` itself.** (The review already confirmed this; this is a guard against drift since the review.)

- [ ] **Step 2: Decide**

If both sweeps are clean (only JASCOFiles-internal hits, or none), proceed to Task 3. If a sibling package calls one of these on a `JASCOSpectrum`, **STOP** and report the call site — the spec's "zero consumers" premise would need re-checking before deleting.

---

### Task 3: Move axis labels into the Makie extension; drop `src/plotting.jl`

**Files:**
- Modify: `ext/JASCOFilesMakieExt.jl` (add private `_xlabel`/`_ylabel`, use them in `plot`)
- Modify: `src/JASCOFiles.jl` (remove `include("plotting.jl")` and `export xlabel, ylabel`)
- Delete: `src/plotting.jl`
- Modify: `test/runtests.jl` (rewrite `@testset "axis labels"`; fix label asserts in `@testset "binary vs .txt ground truth (UV-Vis abs)"`)

- [ ] **Step 1: Rewrite the Makie extension (full-file replacement)**

Write `ext/JASCOFilesMakieExt.jl` with exactly:

```julia
module JASCOFilesMakieExt

using JASCOFiles
using Makie

# Enable `lines(s)`, `scatter(s)`, `lines!(ax, s)`, etc. `PointBased` is a
# Makie conversion-trait singleton; matching on the instance covers every
# plot type whose conversion_trait is PointBased() (Lines, Scatter, etc.).
function Makie.convert_arguments(t::Makie.PointBased, s::JASCOSpectrum)
    return Makie.convert_arguments(t, s.x, s.y)
end

# Axis-label helpers for the `plot(s)` recipe. JASCOFiles is a pure reader and
# owns no axis labels; this presentation logic lives with its only consumer.
function _xlabel(s::JASCOSpectrum)
    u = uppercase(s.xunits)
    if u in ("1/CM", "CM-1")
        israman(s) && return "Raman shift (cm⁻¹)"
        return "Wavenumber (cm⁻¹)"
    elseif u in ("NANOMETERS", "NM")
        return "Wavelength (nm)"
    else
        return titlecase(s.xunits)
    end
end

function _ylabel(s::JASCOSpectrum)
    u = uppercase(s.yunits)
    if u in ("ABSORBANCE", "ABS")
        return "Absorbance"
    elseif u == "INTENSITY"
        return "Intensity"
    elseif u == "TRANSMITTANCE"
        return "Transmittance (%)"
    elseif u == "TRANSMITTANCE_FRAC"
        return "Transmittance"
    else
        return titlecase(s.yunits)
    end
end

"""
    plot(s::JASCOSpectrum; axis=NamedTuple(), kwargs...)

Plot a JASCO spectrum with axis labels and orientation chosen from `s`.
Available when Makie is loaded; load a backend (`using CairoMakie` or
`using GLMakie`) first. Returns a `FigureAxisPlot` that destructures into
`(figure, axis, plot)`.

Axis defaults:
- `xlabel`/`ylabel` derived from `s.xunits`/`s.yunits`
- `title`  from `s.title`
- `xreversed = isftir(s)` (standard IR orientation: wavenumber decreases
  left-to-right)

Pass an `axis` NamedTuple to override any of these. Extra keyword arguments
are forwarded to `Makie.lines` (e.g. `color`, `linewidth`).

```julia
using JASCOFiles, CairoMakie

s = JASCOSpectrum("sample.csv")
fig, ax, ln = plot(s)
fig, ax, ln = plot(s; color = :tomato)
fig, ax, ln = plot(s; axis = (xreversed = false,))
```
"""
function Makie.plot(s::JASCOSpectrum;
                    axis::NamedTuple = NamedTuple(),
                    kwargs...)
    default_axis = (
        xlabel    = _xlabel(s),
        ylabel    = _ylabel(s),
        title     = s.title,
        xreversed = isftir(s),
    )
    return Makie.lines(s.x, s.y;
        axis = merge(default_axis, axis),
        kwargs...,
    )
end

end # module
```

- [ ] **Step 2: Remove the plotting include and label exports from the module**

In `src/JASCOFiles.jl`, delete the line:
```julia
include("plotting.jl")
```
and delete the line:
```julia
export xlabel, ylabel
```
Leave `include("transforms.jl")` and `export transmittance_to_absorbance, absorbance_to_transmittance` in place (removed in Task 4). The export block should now read:
```julia
export AbstractJASCOSpectrum, JASCOSpectrum
export isftir, israman, isuvvis
export transmittance_to_absorbance, absorbance_to_transmittance
```

- [ ] **Step 3: Delete the core plotting file**

Run:
```bash
git rm src/plotting.jl
```

- [ ] **Step 4: Rewrite the `axis labels` testset to use the extension's helpers**

In `test/runtests.jl`, replace the entire `@testset "axis labels" begin ... end` block with:

```julia
@testset "axis labels" begin
    # Label logic lives in the Makie extension (JASCOFiles is a pure reader and
    # owns no axis labels). Reach into the loaded extension to test it directly.
    ext = Base.get_extension(JASCOFiles, :JASCOFilesMakieExt)
    @test ext !== nothing
    _xlabel = ext._xlabel
    _ylabel = ext._ylabel

    ftir = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))
    raman = JASCOSpectrum(joinpath(data_dir, "raman_test.csv"))
    uvvis = JASCOSpectrum(joinpath(data_dir, "uvvis_test.csv"))

    @test _xlabel(ftir) == "Wavenumber (cm⁻¹)"
    @test _ylabel(ftir) == "Absorbance"

    @test _xlabel(raman) == "Raman shift (cm⁻¹)"
    @test _ylabel(raman) == "Intensity"

    @test _xlabel(uvvis) == "Wavelength (nm)"
    @test _ylabel(uvvis) == "Absorbance"

    # Transmittance variants, constructed directly (no transform helper)
    t = JASCOSpectrum(ftir; yunits="TRANSMITTANCE")
    @test _ylabel(t) == "Transmittance (%)"
    tf = JASCOSpectrum(ftir; yunits="TRANSMITTANCE_FRAC")
    @test _ylabel(tf) == "Transmittance"

    # Unknown units fall back to title-casing the raw value
    weird = JASCOSpectrum(x=Float64[], y=Float64[], datatype="INFRARED SPECTRUM",
                          xunits="kelvin", yunits="candelas")
    @test _xlabel(weird) == "Kelvin"
    @test _ylabel(weird) == "Candelas"

    # Empty units (honest defaults) yield empty labels, not fabricated ones
    bare = JASCOSpectrum(x=[1.0], y=[1.0])
    @test _xlabel(bare) == ""
    @test _ylabel(bare) == ""
end
```

- [ ] **Step 5: Fix the label asserts in the binary-vs-text parity testset**

In `test/runtests.jl`, inside `@testset "binary vs .txt ground truth (UV-Vis abs)"`, replace these two lines:
```julia
    @test xlabel(bin) == xlabel(txt)
    @test ylabel(bin) == ylabel(txt)
```
with reader-level unit parity (the labels were a proxy for this):
```julia
    @test bin.xunits == txt.xunits
    @test bin.yunits == txt.yunits
```

- [ ] **Step 6: Run the suite**

Run:
```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```
Expected: PASS. `xlabel`/`ylabel` no longer exist in JASCOFiles; the `plot(s)` recipe still labels axes (the `Makie extension` testset's `ax.xlabel[]`/`ax.ylabel[]` assertions still pass); the `axis labels` testset now exercises `ext._xlabel`/`ext._ylabel`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: move axis labels into the Makie extension

xlabel/ylabel become private _xlabel/_ylabel in JASCOFilesMakieExt, with
their only consumer (the plot recipe). The core reader no longer owns or
exports axis-label functions. Tests exercise the helpers via the loaded
extension; binary/text parity now asserts unit equality directly.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Remove the transmittance ↔ absorbance transforms

**Files:**
- Modify: `test/runtests.jl` (add guard testset; delete two transform testsets; delete the legacy conversion lines)
- Delete: `src/transforms.jl`
- Modify: `src/JASCOFiles.jl` (remove `include("transforms.jl")` and the transform export)

- [ ] **Step 1: Add the guard testset (test-first)**

In `test/runtests.jl`, add this testset immediately after `@testset "Code quality (Aqua.jl)" begin ... end`:

```julia
@testset "reader owns no transforms or labels (3.0)" begin
    # JASCOFiles is a pure reader: transmittance<->absorbance conversions and
    # axis labels live in the analysis layer (OpticalSpectroscopy), not here.
    # Guard against their reintroduction into the reader's public namespace.
    for name in (:transmittance_to_absorbance, :absorbance_to_transmittance,
                 :xlabel, :ylabel)
        @test !isdefined(JASCOFiles, name)
    end
end
```

- [ ] **Step 2: Run only the guard to see it fail (red)**

Run:
```bash
julia --project=. -e 'using Pkg; Pkg.test()' 2>&1 | grep -A6 "reader owns no transforms"
```
Expected: FAIL — `transmittance_to_absorbance` and `absorbance_to_transmittance` are still defined (the `xlabel`/`ylabel` checks already pass after Task 3). This confirms the guard is real.

- [ ] **Step 3: Delete the two transform testsets**

In `test/runtests.jl`, delete the entire `@testset "transmittance ↔ absorbance (unit-aware, 2.0)" begin ... end` block and the entire `@testset "conversion guards (2.0)" begin ... end` block (they are adjacent). The first begins with `@testset "transmittance ↔ absorbance (unit-aware, 2.0)" begin`; the second ends just before the next testset (`@testset "Makie extension" begin`).

- [ ] **Step 4: Delete the legacy conversion lines**

In `test/runtests.jl`, inside `@testset "legacy .jws (Spectra Manager 1.x, OLE container)"`, delete these three lines (the reader-level fact `t.yunits == "TRANSMITTANCE"` is already asserted earlier in the same testset):
```julia
    # Unit-aware conversion works straight off a legacy %T file
    at = transmittance_to_absorbance(t)
    @test at.yunits == "ABSORBANCE"
```

- [ ] **Step 5: Delete the transforms source and its module wiring**

Run:
```bash
git rm src/transforms.jl
```
Then in `src/JASCOFiles.jl` delete the line:
```julia
include("transforms.jl")
```
and delete the line:
```julia
export transmittance_to_absorbance, absorbance_to_transmittance
```
The export block should now read exactly:
```julia
export AbstractJASCOSpectrum, JASCOSpectrum
export isftir, israman, isuvvis
```

- [ ] **Step 6: Run the suite (green)**

Run:
```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```
Expected: PASS, including the `reader owns no transforms or labels (3.0)` guard and Aqua.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor!: remove T<->A transforms from the reader (3.0)

transmittance_to_absorbance and absorbance_to_transmittance are removed
from JASCOFiles' public API; the analysis layer (OpticalSpectroscopy) owns
unit conversions. A guard test asserts none of the four collision verbs are
defined in the reader.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Bump version to 3.0.0 and add NEWS.md

**Files:**
- Modify: `Project.toml` (`version = "2.0.0"` → `"3.0.0"`)
- Create: `NEWS.md`

- [ ] **Step 1: Bump the version**

In `Project.toml`, change:
```toml
version = "2.0.0"
```
to:
```toml
version = "3.0.0"
```

- [ ] **Step 2: Create `NEWS.md`**

Write `NEWS.md` with exactly:

```markdown
# JASCOFiles.jl release notes

## 3.0.0

**Breaking — JASCOFiles is now a pure reader.**

Removed from the public API:

- `transmittance_to_absorbance`
- `absorbance_to_transmittance`
- `xlabel`
- `ylabel`

The reader emits raw data plus the instrument's native unit strings
(`xunits`/`yunits`); unit conversions and axis labels belong to the analysis
layer. Migrate:

- Conversions and formatted labels: use OpticalSpectroscopy on a `Spectrum`.
- A quick standalone percent-transmittance → absorbance: `-log10.(s.y ./ 100)`.

The built-in Makie `plot(s)` recipe is unchanged — it still fills axis labels,
title, and `xreversed` from the spectrum.
```

- [ ] **Step 3: Commit**

```bash
git add Project.toml NEWS.md
git commit -m "chore: bump to 3.0.0 and add NEWS

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Update README and docs

**Files:**
- Modify: `README.md` (remove the T↔A convenience block)
- Modify: `docs/src/index.md` (rewrite the "full control" paragraph)
- Modify: `docs/src/lib/public.md` (remove transform/plotting autodoc sections + cross-refs)

- [ ] **Step 1: README — remove the T↔A example**

In `README.md`, inside the `## Convenience features` code block, delete these five lines (keep the copy-constructor and metadata-alias examples that follow):
```julia
# Convert between transmittance and absorbance.
# The transmittance scale (percent vs fractional) is inferred from yunits;
# the output scale of absorbance → transmittance is chosen explicitly.
t = absorbance_to_transmittance(s; percent=true)   # yunits → "TRANSMITTANCE" (0–100)
a = transmittance_to_absorbance(t)                 # infers %T; yunits → "ABSORBANCE"
```
Also delete the now-empty leading blank line so the code block starts at the `# Copy a spectrum with selected fields replaced` comment.

- [ ] **Step 2: index.md — rewrite the "full control" paragraph**

In `docs/src/index.md`, replace this paragraph and its code block:
```markdown
For full control, `s.x` and `s.y` are plain vectors, so any plotting package works. `xlabel(s)` and `ylabel(s)` produce nicely formatted labels (e.g. `"Wavenumber (cm⁻¹)"`, `"Transmittance (%)"`) for any library:

```julia
fig, ax, ln = lines(s.x, s.y;
    axis = (xlabel = xlabel(s), ylabel = ylabel(s), title = s.title))
```
```
with:
```markdown
For full control, `s.x` and `s.y` are plain vectors and `s.xunits`/`s.yunits` are the instrument's unit strings, so any plotting package works. JASCOFiles is a pure reader and ships no conversions or axis-label helpers — use [OpticalSpectroscopy.jl](https://github.com/garrekstemo/OpticalSpectroscopy.jl) for transmittance↔absorbance and formatted axis labels:

```julia
fig, ax, ln = lines(s.x, s.y; axis = (title = s.title,))
```
```

- [ ] **Step 3: public.md — remove the transform and plotting-helper sections**

In `docs/src/lib/public.md`, delete these two sections in full:
```markdown
## Transmittance ↔ absorbance conversions

```@autodocs
Modules = [JASCOFiles]
Pages = ["transforms.jl"]
Private = false
```

## Plotting helpers

`xlabel` and `ylabel` produce nicely formatted axis labels (e.g. `"Wavenumber (cm⁻¹)"`, `"Transmittance (%)"`) from a spectrum's units. They work without any plotting backend loaded.

```@autodocs
Modules = [JASCOFiles]
Pages = ["plotting.jl"]
Private = false
```
```

- [ ] **Step 4: public.md — drop the `@ref` cross-references in the Makie section**

In `docs/src/lib/public.md`, replace:
```markdown
Axis defaults are filled from the spectrum:
- `xlabel` from [`xlabel`](@ref)`(s)`
- `ylabel` from [`ylabel`](@ref)`(s)`
- `title` from `s.title`
- `xreversed = isftir(s)` (standard IR orientation: wavenumber decreases left-to-right)
```
with:
```markdown
Axis defaults are filled from the spectrum:
- `xlabel`/`ylabel` derived from `s.xunits`/`s.yunits`
- `title` from `s.title`
- `xreversed = isftir(s)` (standard IR orientation: wavenumber decreases left-to-right)
```
(Leave `docs/src/lib/public.md` line 7 — "Only exported types and functions are considered part of the public API" — unchanged; it is now true again because nothing public is left unexported.)

- [ ] **Step 5: Sanity-check for dangling references**

Run:
```bash
rg -n "transmittance_to_absorbance|absorbance_to_transmittance|\(@ref\)\`?\s*xlabel|xlabel\]\(@ref\)|ylabel\]\(@ref\)" README.md docs/
```
Expected: no matches in `README.md` or `docs/src` (the `plot(s)` Makie sections that remain do not reference the removed functions).

- [ ] **Step 6: Commit**

```bash
git add README.md docs/src/index.md docs/src/lib/public.md
git commit -m "docs: drop reader-side T<->A and axis-label API

Point standalone users at OpticalSpectroscopy for conversions and labels;
remove the transforms/plotting autodoc sections and @ref cross-references.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7a: Write the layering invariant into JASCOFiles' CLAUDE.md

**Files:** Modify `CLAUDE.md` (JASCOFiles repo).

> Note: `CLAUDE.md` was streamlined in commit `e02c836` (carried onto this
> branch by Task 1's rebase). It currently documents the *unexport* (3.0.0)
> state — a `## Public API split (v3.0.0 unexport refactor)` section and a
> `## Transform unit semantics` section. These edits replace that with the
> pure-reader state.

- [ ] **Step 1: Replace the "Public API split" section (drop the unexported verbs)**

In `CLAUDE.md`, replace this section:
```markdown
## Public API split (v3.0.0 unexport refactor)

- **Exported:** `JASCOSpectrum`, `AbstractJASCOSpectrum`, `isftir`, `israman`, `isuvvis`.
- **NOT exported (public, call qualified):** `JASCOFiles.transmittance_to_absorbance`, `absorbance_to_transmittance`, `xlabel`, `ylabel` (in `plotting.jl`). Names are generic and collide with OpticalSpectroscopy, which exports the same verbs — qualifying avoids ambiguous bindings.
```
with:
```markdown
## Public API

- **Exported (the entire public surface):** `JASCOSpectrum`, `AbstractJASCOSpectrum`, `isftir`, `israman`, `isuvvis`.
```
(Leave the `JASCOSpectrum` constructor-forms paragraph that follows unchanged.)

- [ ] **Step 2: Replace the "Transform unit semantics" section with the design invariant**

In `CLAUDE.md`, replace this section:
```markdown
## Transform unit semantics

- `transmittance_to_absorbance`: scale inferred from `yunits` — `"TRANSMITTANCE"` = %T (0–100), `"TRANSMITTANCE_FRAC"` = 0–1; explicit `percent` overrides (and is required for any other `yunits`). Output `yunits = "ABSORBANCE"`; nonpositive T → `NaN`.
- `absorbance_to_transmittance`: `percent` is a **required** keyword (`true` → %T / `"TRANSMITTANCE"`, `false` → `"TRANSMITTANCE_FRAC"`).
```
with:
```markdown
## Design invariant

The reader emits raw data plus the instrument's native unit strings (`xunits`/`yunits`). It owns **no transforms and no axis labels** — unit conversions (e.g. transmittance↔absorbance) and presentation belong to the analysis layer (OpticalSpectroscopy). The Makie `plot(s)` recipe keeps small private axis-label helpers (`_xlabel`/`_ylabel` in `ext/JASCOFilesMakieExt.jl`) for its own use only. Do not re-add these verbs to the reader's public API.
```

- [ ] **Step 3: Verify no stale references remain**

Run:
```bash
grep -n "transmittance_to_absorbance\|absorbance_to_transmittance\|plotting.jl\|NOT exported\|unexport" CLAUDE.md
```
Expected: no matches.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: record the pure-reader invariant in CLAUDE.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7b: Add the reciprocal line to OpticalSpectroscopy's CLAUDE.md (separate repo)

**Files:** Modify `~/Developer/OpticalSpectroscopy.jl/CLAUDE.md` — this is a **different git repository**; branch and commit there, do not touch its `main` directly.

- [ ] **Step 1: Branch in the OpticalSpectroscopy repo**

Run:
```bash
cd ~/Developer/OpticalSpectroscopy.jl
git checkout -b reader-layering-note
```

- [ ] **Step 2: Add the reciprocal sentence to the Scope section**

In `~/Developer/OpticalSpectroscopy.jl/CLAUDE.md`, immediately after the `## Scope` paragraph that begins `In scope:` (around line 7), add a new paragraph:
```markdown
File-reader packages (JASCOFiles, HamamatsuStreakFiles) own no transforms or axis labels — they emit raw data plus the instrument's native unit strings. All unit conversions (including transmittance↔absorbance) and axis labels live here, in the analysis layer.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note that file readers own no transforms/labels (analysis layer does)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
cd ~/Developer/JASCOFiles.jl
```

(Optional, not required for the release: the user's global `~/.claude/CLAUDE.md` ecosystem notes can gain the same one-line invariant.)

---

### Task 8: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Full test suite**

Run:
```bash
cd ~/Developer/JASCOFiles.jl
julia --project=. -e 'using Pkg; Pkg.test()'
```
Expected: PASS, including Aqua and the `reader owns no transforms or labels (3.0)` guard.

- [ ] **Step 2: Confirm the public surface**

Run:
```bash
julia --project=. -e 'using JASCOFiles; for n in (:transmittance_to_absorbance,:absorbance_to_transmittance,:xlabel,:ylabel); @assert !isdefined(JASCOFiles, n) "$n still defined"; end; println("pure reader OK: ", filter(s->s!=:JASCOFiles, names(JASCOFiles)))'
```
Expected: prints `pure reader OK: [:AbstractJASCOSpectrum, :JASCOSpectrum, :isftir, :israman, :isuvvis]` (order may vary) and no assertion error.

- [ ] **Step 3: (Optional) Confirm no clash when loaded with the analysis layer**

Run:
```bash
julia -e 'using Pkg; Pkg.activate(mktempdir()); Pkg.develop([(path="'"$HOME"'/Developer/JASCOFiles.jl"),(path="'"$HOME"'/Developer/OpticalSpectroscopy.jl")]); using JASCOFiles, OpticalSpectroscopy; @assert !isdefined(JASCOFiles,:xlabel); println("no clash: xlabel resolves to ", parentmodule(xlabel))'
```
Expected: no ambiguous-binding warning for `xlabel`/`ylabel`/the transform names; `xlabel` resolves to `OpticalSpectroscopy`. (Heavy/temporary env; skip if OpticalSpectroscopy's deps don't resolve cleanly — Step 2's guard already proves the names are gone from JASCOFiles.)

- [ ] **Step 4: Review the branch history**

Run:
```bash
git log --oneline origin/main..HEAD
```
Expected: a clean sequence on top of `d9dd7c0` (spec → labels → transforms → version/NEWS → docs → CLAUDE.md), with **no `2d6e506` band-aid commit** in the list.

- [ ] **Step 5: Hand off to branch finalization**

Do **not** register or push as part of this plan. Note for finalization (use the `superpowers:finishing-a-development-branch` skill):
- Local `main` still points at the unpushed band-aid `2d6e506`; finalization should move `main` to this clean `pure-reader-3.0` branch (e.g. fast-forward `main` after review) rather than merging the band-aid back in.
- JuliaRegistrator registration of 3.0.0 is a separate, explicitly-approved step performed after merge to `main` (per the user's registration conventions). Versions register sequentially; 2.0.0 is already registered, so 3.0.0 will merge in minutes once triggered.
- The OpticalSpectroscopy `reader-layering-note` branch is an independent doc change to land on its own.

---

## Self-Review

**Spec coverage:**
- Remove `src/transforms.jl` → Task 4. ✓
- Remove `src/plotting.jl`, move labels to ext (option B) → Task 3. ✓
- Module export list reduced to types + predicates → Tasks 3 & 4. ✓
- Tests: delete transform testsets, fold/relocate label tests, fix binary parity + legacy → Tasks 3 & 4. ✓
- Docs: README, index.md, public.md → Task 6. ✓
- `public.md:7` left unchanged (true again) → Task 6 Step 4 note. ✓
- CLAUDE.md both repos + principle → Tasks 7a/7b. ✓
- Replace band-aid `2d6e506`, version 3.0.0, NEWS.md → Tasks 1 & 5. ✓
- Pre-flight zero-callers sweep → Task 2. ✓
- No OpticalSpectroscopy code change (only its CLAUDE.md) → Task 7b. ✓
- Acceptance: no-clash, suite+Aqua green, exact public surface, NEWS/version → Task 8. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to". Every code/edit step shows exact content. ✓

**Type/name consistency:** `_xlabel`/`_ylabel` defined in Task 3 Step 1 and referenced identically in Task 3 Step 4 (`ext._xlabel`/`ext._ylabel`) and the guard (Task 4) checks the four removed names by symbol. Export block edits in Task 3 Step 2 and Task 4 Step 5 are consistent (Task 3 leaves the transform export; Task 4 removes it). ✓
