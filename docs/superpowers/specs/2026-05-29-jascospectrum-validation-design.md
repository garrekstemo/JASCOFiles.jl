# Fail-fast validation for `JASCOSpectrum`

**Date:** 2026-05-29
**Status:** Approved for planning

## Problem

`JASCOSpectrum(path)` is best-effort and never fails on structurally invalid
input. When a user accidentally replaced a data file's contents with a single
stray line of text, the parser:

1. Never saw the `XYDATA` marker, so `is_data_section` stayed `false` and
   `x`/`y` remained empty.
2. Filled every field with defaults (`"Untitled"`, `"Unknown"`, `"cm-1"`, empty
   vectors) at the `return JASCOSpectrum(...)` call.
3. Returned a valid-looking object with **zero data points** and no error.

The failure surfaced far downstream — inside a fitting loop at `stderror(sol)`,
with an error message unrelated to the real cause (a bad input file). The user
had no indication which file was bad or why.

Root cause: the constructor silently degrades to defaults instead of failing
when the input is not a JASCO spectrum.

## Decision

The constructor must **either return a valid spectrum or throw**. Invalid input
throws immediately at read time, using the built-in `ArgumentError` (idiomatic
Julia for malformed-argument failures — same type `parse` throws). No custom
exception type and no non-throwing escape hatch for now (YAGNI; both are easy to
add later if a batch-loop caller needs to selectively catch and skip).

## Design

### Location

A focused validation block runs once at the end of the `JASCOSpectrum`
constructor in `src/parser.jl`, immediately before `return JASCOSpectrum(...)`.
Parsing stays in the existing `eachline` loop; validation operates on the
collected results. No new files, no new types.

The loop already tracks `is_data_section`, which flips to `true` only when the
literal `XYDATA` line is seen (`parser.jl:36`). That is exactly the signal
needed for check 1 — no extra bookkeeping.

### Checks (in order; first failure throws)

Every message is prefixed with `basename(path)` so a loop over many files
reports *which* file failed and *why*.

1. **No `XYDATA` section** — `!is_data_section`
   → `ArgumentError("<file>: no XYDATA section found; file does not appear to be a JASCO spectrum")`
   This is the most fundamental failure and fires first. It is the exact case
   from the bug report (a file with one stray line and no `XYDATA`).

2. **x/y length mismatch** (defensive) — `length(xdata) != length(ydata)`
   → `ArgumentError("<file>: parsed <nx> x-values but <ny> y-values")`
   Cannot occur today (x and y are pushed as a pair at `parser.jl:68`); included
   to guard future changes to the parsing logic.

3. **Zero data points** — `isempty(xdata)`
   → `ArgumentError("<file>: XYDATA section contains no parseable data points")`
   Catches the case where `XYDATA` appears but no valid x,y rows follow.

4. **`NPOINTS` mismatch** — only when the header has an `NPOINTS` field whose
   value parses as an `Int` via `tryparse(Int, ...)`. If `NPOINTS` is absent or
   non-integer, skip this check silently (some valid files, e.g. the V-series
   UV-Vis variant, behave differently). When present and `n != length(xdata)`:
   → `ArgumentError("<file>: header declares NPOINTS=<n> but found <m> data points")`

### What does NOT change

- Silently skipping individual unparseable data rows (`parser.jl:70`) stays as
  is — some files legitimately carry trailing junk, and checks 1–3 already catch
  the "not a spectrum" case.
- Default fallbacks for descriptive fields (`title`, `datatype`, etc.) stay —
  they only apply once the file has been confirmed to contain real data.

## Compatibility note (important)

The existing `test/data/ftir_malformed.csv` and `raman_malformed.csv` fixtures
**do** contain an `XYDATA` marker and valid data rows (with a couple of junk
rows that get skipped). The current tests at `runtests.jl:38`, `:84`, and `:334`
expect these to parse successfully. The new checks must NOT break them:

- Both have `XYDATA` → check 1 passes.
- Both yield 3 valid points → checks 2 and 3 pass.
- Neither declares `NPOINTS` → check 4 is skipped.

So "malformed" in the existing suite means "valid spectrum with junk rows," not
"not a spectrum." New throwing-case fixtures therefore need **distinct names**.

## Testing

New fixtures in `test/data/`:

- `not_a_spectrum.csv` — a file with only a stray line of text, no `XYDATA`
  (mirrors the bug). Asserts check 1 throws `ArgumentError`.
- `empty_xydata.csv` — header + `XYDATA` marker followed by no parseable rows
  (blank or all-junk body). Asserts check 3 throws `ArgumentError`.
- `wrong_npoints.csv` — valid data but a deliberately incorrect `NPOINTS` header.
  Asserts check 4 throws `ArgumentError`.

New tests in `test/runtests.jl`:

- `@test_throws ArgumentError JASCOSpectrum(<each new fixture>)`.
- Regression: all existing valid fixtures (`ftir_test.csv`, `raman_test.csv`,
  `uvvis_test.csv`, `japanese_header_test.csv`, `raman_japanese_test.csv`, and
  the two `*_malformed.csv` files) still parse without throwing.

## Out of scope

- Custom exception type (`InvalidJASCOFile`).
- Non-throwing `tryparse(JASCOSpectrum, path)` sibling.
- Validating header/footer metadata semantics beyond `NPOINTS`.
