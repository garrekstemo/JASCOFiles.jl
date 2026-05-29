# JASCOSpectrum Fail-Fast Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `JASCOSpectrum(path)` throw `ArgumentError` on structurally invalid input instead of silently returning an empty spectrum.

**Architecture:** Add a focused validation block at the end of the `JASCOSpectrum` outer constructor in `src/parser.jl`, just before `return JASCOSpectrum(...)`. It runs four checks on the collected parse results (no XYDATA section, x/y length mismatch, zero data points, NPOINTS mismatch), each throwing an `ArgumentError` prefixed with `basename(path)`. New test fixtures cover each throwing case; existing fixtures must still parse.

**Tech Stack:** Julia 1.10+, `Test` stdlib, existing JASCOFiles test suite (`test/runtests.jl`).

**Spec:** `docs/superpowers/specs/2026-05-29-jascospectrum-validation-design.md`

---

## File Structure

- **Modify** `src/parser.jl` — add the validation block before the `return` at the end of the constructor (currently `parser.jl:99`).
- **Create** `test/data/not_a_spectrum.csv` — stray text, no XYDATA (check 1).
- **Create** `test/data/empty_xydata.csv` — header + XYDATA marker, no parseable rows (check 3).
- **Create** `test/data/wrong_npoints.csv` — valid data but wrong NPOINTS header (check 4).
- **Modify** `test/runtests.jl` — add throwing-case assertions to the existing `"error paths"` testset (`runtests.jl:259`).

---

### Task 1: Add test fixtures for the three throwing cases

**Files:**
- Create: `test/data/not_a_spectrum.csv`
- Create: `test/data/empty_xydata.csv`
- Create: `test/data/wrong_npoints.csv`

These are data files, not code, so there is no separate test step — they are consumed by Task 2's tests.

- [ ] **Step 1: Create `test/data/not_a_spectrum.csv`**

Contents (a misplaced copy-paste with no XYDATA marker — mirrors the original bug):

```
This is not a spectrum file, just a stray line of text.
```

- [ ] **Step 2: Create `test/data/empty_xydata.csv`**

Contents (header and XYDATA marker present, but every data row fails to parse, so zero points are collected):

```
TITLE,Empty Data Test
DATA TYPE,INFRARED SPECTRUM
XYDATA
not,numbers
also,garbage
```

- [ ] **Step 3: Create `test/data/wrong_npoints.csv`**

Contents (3 valid data points, but the header declares NPOINTS=512):

```
TITLE,Wrong NPOINTS Test
DATA TYPE,INFRARED SPECTRUM
NPOINTS,512
XYDATA
1000.0,0.1
2000.0,0.2
3000.0,0.3
```

- [ ] **Step 4: Commit**

```bash
git add test/data/not_a_spectrum.csv test/data/empty_xydata.csv test/data/wrong_npoints.csv
git commit -m "test: add fixtures for invalid JASCO spectrum files"
```

---

### Task 2: Add validation block and tests (TDD)

**Files:**
- Modify: `src/parser.jl` (insert validation block before `return JASCOSpectrum(...)`, currently `parser.jl:99`)
- Test: `test/runtests.jl` (extend the `"error paths"` testset at `runtests.jl:259`)

- [ ] **Step 1: Write the failing tests**

In `test/runtests.jl`, replace the existing `"error paths"` testset (currently at `runtests.jl:259`):

```julia
@testset "error paths" begin
    @test_throws SystemError JASCOSpectrum("this_file_does_not_exist.csv")
    @test JASCOSpectrum <: AbstractJASCOSpectrum
end
```

with this expanded version:

```julia
@testset "error paths" begin
    @test_throws SystemError JASCOSpectrum("this_file_does_not_exist.csv")
    @test JASCOSpectrum <: AbstractJASCOSpectrum

    # Invalid-input validation: the constructor must throw, not silently
    # return an empty/defaulted spectrum (see 2026-05-29 validation spec).
    @test_throws ArgumentError JASCOSpectrum(joinpath(data_dir, "not_a_spectrum.csv"))
    @test_throws ArgumentError JASCOSpectrum(joinpath(data_dir, "empty_xydata.csv"))
    @test_throws ArgumentError JASCOSpectrum(joinpath(data_dir, "wrong_npoints.csv"))
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: FAIL in the `"error paths"` testset. The three new `@test_throws ArgumentError` lines fail because `JASCOSpectrum` currently returns an empty spectrum instead of throwing (no exception is raised).

- [ ] **Step 3: Add the validation block to `src/parser.jl`**

In `src/parser.jl`, locate the end of the constructor — the date-parsing `try`/`catch` block followed by `return JASCOSpectrum(...)` (currently `parser.jl:88`–`parser.jl:109`). Insert the following block **between** the date block's closing `end` and the `return JASCOSpectrum(` line:

```julia
    # Fail fast on structurally invalid input rather than returning an
    # empty/defaulted spectrum. Each message names the file so callers
    # iterating over many files learn which one is bad.
    fname = basename(path)
    if !is_data_section
        throw(ArgumentError("$fname: no XYDATA section found; file does not appear to be a JASCO spectrum"))
    end
    if length(xdata) != length(ydata)
        throw(ArgumentError("$fname: parsed $(length(xdata)) x-values but $(length(ydata)) y-values"))
    end
    if isempty(xdata)
        throw(ArgumentError("$fname: XYDATA section contains no parseable data points"))
    end
    if haskey(raw_metadata, "NPOINTS")
        declared = tryparse(Int, strip(string(raw_metadata["NPOINTS"])))
        if declared !== nothing && declared != length(xdata)
            throw(ArgumentError("$fname: header declares NPOINTS=$declared but found $(length(xdata)) data points"))
        end
    end
```

The result should read, in order: the date `try`/`catch` block, then this validation block, then `return JASCOSpectrum(...)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: PASS. The three new `@test_throws ArgumentError` assertions pass, AND every pre-existing testset still passes — in particular the `"FTIR edge cases"` (`runtests.jl:37`) and `"read JASCO FTIR csv file"` (`runtests.jl:16`) testsets, which rely on valid and junk-row-but-valid fixtures parsing successfully. The `*_malformed.csv` fixtures have an XYDATA marker, 3 points each, and no NPOINTS, so they pass all four checks.

- [ ] **Step 5: Commit**

```bash
git add src/parser.jl test/runtests.jl
git commit -m "feat: validate parsed spectrum, throw ArgumentError on invalid input

JASCOSpectrum no longer silently returns an empty/defaulted spectrum
when the file is not a real JASCO spectrum. It now throws ArgumentError
for: missing XYDATA section, zero parseable data points, x/y length
mismatch, and a header NPOINTS that disagrees with the parsed count.
Each message names the file so batch loops report which file failed."
```

---

## Self-Review

**Spec coverage:**
- Decision (throw `ArgumentError`, no custom type, no escape hatch) → Task 2 Step 3 uses `ArgumentError`, adds no types. ✓
- Check 1 (no XYDATA) → Task 2 Step 3 `!is_data_section`; fixture `not_a_spectrum.csv` (Task 1); test (Task 2 Step 1). ✓
- Check 2 (x/y length mismatch, defensive) → Task 2 Step 3 length comparison. (No fixture — cannot be triggered through the path parser today; defensive guard only, matching the spec.) ✓
- Check 3 (zero data points) → Task 2 Step 3 `isempty(xdata)`; fixture `empty_xydata.csv`; test. ✓
- Check 4 (NPOINTS mismatch, only when present and integer) → Task 2 Step 3 `haskey` + `tryparse(Int, ...)`; fixture `wrong_npoints.csv`; test. ✓
- Ordering (1, 2, 3, 4) → matches spec. ✓
- `basename(path)` prefix on messages → Task 2 Step 3 `fname = basename(path)`. ✓
- Compatibility (existing fixtures still parse) → Task 2 Step 4 expected-output note; verified during planning (all NPOINTS match parsed counts; no-NPOINTS files have XYDATA + points). ✓
- New fixtures use distinct names (not `*_malformed.csv`) → `not_a_spectrum.csv`, `empty_xydata.csv`, `wrong_npoints.csv`. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases" — every code and command step shows exact content. ✓

**Type consistency:** Variable `fname` defined and used consistently in Task 2 Step 3. `is_data_section`, `xdata`, `ydata`, `raw_metadata` all refer to existing locals in the constructor (`parser.jl:2`–`parser.jl:6`). Fixture filenames in Task 1 exactly match those referenced in Task 2 Step 1. ✓
