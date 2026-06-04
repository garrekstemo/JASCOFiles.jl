# `.jws` / `.jrs` Binary Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read JASCO binary spectra (`.jws` = SPECMAN, `.jrs` = SPECIRM) for FTIR and UV-Vis directly into a `JASCOSpectrum`, via the existing `JASCOSpectrum(path)` entry point.

**Architecture:** A new `src/binary.jl` decodes the fixed-offset SPECMAN/SPECIRM header and trailing little-endian `Float32` data block. The public `JASCOSpectrum(path; ...)` constructor in `src/parser.jl` becomes a thin extension dispatcher: `.jws`/`.jrs` → `_read_jws`, everything else → the existing CSV body (renamed `_read_jasco_csv`). The binary path produces the same 9-field struct, so all predicates, labels, transforms, and the Makie/Tables extensions work unchanged. Datatype and x-units are decoded from the instrument model; y-units from the `0xA4` y-mode code. Invalid input throws `ArgumentError` (fail-fast, like the CSV path).

**Tech Stack:** Julia (system default via juliaup), `Dates` + `StringEncodings` stdlib/deps (already present — no new deps), `Test`/`Aqua` test suite (`test/runtests.jl`).

**Spec:** `docs/superpowers/specs/2026-06-04-jws-binary-reader-design.md`

---

## File Structure

- **Create** `src/binary.jl` — offset/decode constants, low-level field readers (`read_le`, `read_cstr`), instrument→datatype helper, and `_read_jws`. One responsibility: turn a binary JASCO file into a `JASCOSpectrum`.
- **Modify** `src/JASCOFiles.jl` — add `include("binary.jl")`.
- **Modify** `src/parser.jl` — split the public constructor into an extension dispatcher + the existing CSV body renamed `_read_jasco_csv`.
- **Modify** `test/runtests.jl` — add binary-reader testsets and a `make_jws` synthetic-fixture helper.
- **Create** `test/data/ftir_test.jws`, `uvvis_abs.jws`, `uvvis_trans.jws`, `uvvis_abs.jrs`, `uvvis_abs.txt` — real fixtures (copied from the sample files).
- **Modify** `README.md`, `docs/src/guide/file-formats.md`, `CLAUDE.md` — docs.
- **Modify** `Project.toml` — version bump.

Test command (run from repo root) throughout:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

---

### Task 1: Binary reader (`src/binary.jl`) + FTIR decode test

**Files:**
- Create: `src/binary.jl`
- Modify: `src/JASCOFiles.jl:24` (add include)
- Create: `test/data/ftir_test.jws`
- Test: `test/runtests.jl` (new testset)

- [ ] **Step 1: Copy the FTIR fixture**

```bash
cp ~/Downloads/FTIR/zif-62-Zn.jws test/data/ftir_test.jws
```

- [ ] **Step 2: Write the failing test**

Append to `test/runtests.jl` (before the final line if there is trailing content; otherwise at end). It calls the internal `_read_jws` directly — the public dispatcher is wired in Task 2.

```julia
@testset "binary _read_jws (FTIR absorbance)" begin
    s = JASCOFiles._read_jws(joinpath(data_dir, "ftir_test.jws"))
    @test s.spectrometer == "FT/IR-4600typeA"
    @test s.datatype == "INFRARED SPECTRUM"
    @test s.xunits == "1/CM"
    @test s.yunits == "ABSORBANCE"
    @test length(s) == 12447
    @test round(s.x[1], digits=4) == 999.9101
    @test round(s.x[end], digits=3) == 7000.335
    @test round(s.y[1], sigdigits=3) ≈ 0.0188
    @test s.metadata["Serial Number"] == "E137161786"
    @test s.metadata["NPOINTS"] == 12447
    @test startswith(s.metadata["Format"], "SPECMAN")
    @test s.date == DateTime(2026, 6, 4, 4, 54, 3)
    @test isftir(s)
end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL — `UndefVarError: _read_jws not defined` (binary.jl does not exist yet).

- [ ] **Step 4: Create `src/binary.jl`**

```julia
# Native reader for JASCO binary spectra. Two on-disk formats share one
# container (magic "L~S ", version "R2.0.0"):
#   .jws  format id "SPECMAN"  - written by the desktop Spectra Manager software
#   .jrs  format id "SPECIRM"  - written by the spectrometer's onboard firmware
# Both have an identical fixed-offset header and a trailing little-endian
# Float32 data block, so one reader serves both. Reverse-engineered and
# validated against FT/IR-4600 and V-730 files; see
# docs/superpowers/specs/2026-06-04-jws-binary-reader-design.md.

const JWS_MAGIC = b"L~S "
const JWS_VERSION = "R2.0.0"
const JWS_IDS = ("SPECMAN", "SPECIRM")
const JWS_HEADER_MIN = 0x300   # all fixed-offset fields live below this byte

# Byte offsets (0-based) into the fixed header.
const OFF_FILEID     = 0x08
const OFF_VERSION    = 0x20
const OFF_NPOINTS    = 0x84
const OFF_FIRSTX     = 0x88
const OFF_LASTX      = 0x90
const OFF_DELTAX     = 0x98
const OFF_XUNIT      = 0xA0   # +1=01 +2=00 +3=10 +4=y-mode +5..+7=00 (0-based 0xA1..0xA7)
const OFF_YMODE      = 0xA4
const OFF_DATALEN    = 0xC8
const OFF_INSTRUMENT = 0x140
const OFF_SERIAL     = 0x160
const OFF_TITLE      = 0x180
const OFF_COMMENT    = 0x1C0
const OFF_EPOCH      = 0x2C0

# y-mode code (byte at OFF_YMODE) -> JASCO YUNITS string.
const YMODE_YUNITS = Dict{UInt8,String}(
    0x00 => "TRANSMITTANCE",
    0x02 => "REFLECTANCE",
    0x03 => "ABSORBANCE",
    0x09 => "INTENSITY",   # single-beam, reference channel
    0x0a => "INTENSITY",   # single-beam, sample channel
)
const YMODE_CHANNEL = Dict{UInt8,String}(0x09 => "Reference", 0x0a => "Sample")

# Read a little-endian scalar of type T at 0-based byte offset `off`.
function read_le(::Type{T}, b::Vector{UInt8}, off::Integer) where {T}
    return ltoh(reinterpret(T, b[off+1:off+sizeof(T)])[1])
end

# Read a fixed-width, null-terminated string field decoded with `encoding`.
function read_cstr(b::Vector{UInt8}, off::Integer, width::Integer, encoding)
    i = off + 1
    stop = i
    limit = min(off + width, length(b))
    while stop <= limit && b[stop] != 0x00
        stop += 1
    end
    return strip(decode(b[i:stop-1], encoding))
end

# Instrument model -> (datatype, xunits, expected x-unit code). Throws on an
# unsupported instrument family. UV-Vis datatype is left blank to match the
# V-series text export (isuvvis infers from NANOMETERS + range).
function _instrument_kind(instrument::AbstractString, fname::AbstractString)
    if startswith(instrument, "FT/IR")
        return ("INFRARED SPECTRUM", "1/CM", 0x00)
    elseif startswith(instrument, "V-")
        return ("", "NANOMETERS", 0x03)
    else
        throw(ArgumentError("$fname: unsupported instrument '$instrument'; only FTIR and UV-Vis are supported — please share this file"))
    end
end

function _read_jws(path::AbstractString; encoding=enc"SHIFT-JIS")
    bytes = read(path)
    fname = basename(path)
    n = length(bytes)

    # 1. minimum size for the fixed header
    n >= JWS_HEADER_MIN ||
        throw(ArgumentError("$fname: file too short ($n bytes) to be a JASCO .jws/.jrs file"))

    # 2. magic
    bytes[1:4] == JWS_MAGIC ||
        throw(ArgumentError("$fname: not a JASCO .jws/.jrs file (missing 'L~S ' signature)"))

    # 3. container id + version + descriptor structural bytes
    fileid = read_cstr(bytes, OFF_FILEID, 16, encoding)
    version = read_cstr(bytes, OFF_VERSION, 16, encoding)
    structural_ok = bytes[OFF_XUNIT+2] == 0x01 && bytes[OFF_XUNIT+3] == 0x00 &&
                    bytes[OFF_XUNIT+4] == 0x10 && bytes[OFF_XUNIT+6] == 0x00 &&
                    bytes[OFF_XUNIT+7] == 0x00 && bytes[OFF_XUNIT+8] == 0x00
    (fileid in JWS_IDS && version == JWS_VERSION && structural_ok) ||
        throw(ArgumentError("$fname: unrecognized binary variant ($fileid $version); please share this file"))

    # 4. instrument family -> datatype / xunits (throws if unsupported)
    instrument = read_cstr(bytes, OFF_INSTRUMENT, 32, encoding)
    datatype, xunits, expected_xunit = _instrument_kind(instrument, fname)

    # 5. x-unit code cross-check
    xunit = bytes[OFF_XUNIT+1]
    xunit == expected_xunit ||
        throw(ArgumentError("$fname: x-unit code 0x$(string(xunit, base=16)) does not match instrument '$instrument'"))

    # 6. y-mode code -> yunits
    ymode = bytes[OFF_YMODE+1]
    haskey(YMODE_YUNITS, ymode) ||
        throw(ArgumentError("$fname: unrecognized y-mode code 0x$(string(ymode, base=16)); please share this file"))
    yunits = YMODE_YUNITS[ymode]

    # 7. point count / data block size
    npoints = Int(read_le(Int32, bytes, OFF_NPOINTS))
    datalen = Int(read_le(Int64, bytes, OFF_DATALEN))
    (npoints > 0 && datalen == npoints * 4 && n - datalen >= JWS_HEADER_MIN) ||
        throw(ArgumentError("$fname: inconsistent point count (NPOINTS=$npoints, data=$datalen bytes, file=$n bytes)"))

    firstx = read_le(Float64, bytes, OFF_FIRSTX)
    lastx  = read_le(Float64, bytes, OFF_LASTX)
    deltax = read_le(Float64, bytes, OFF_DELTAX)

    # 8. grid consistency
    round(Int, (lastx - firstx) / deltax) + 1 == npoints ||
        throw(ArgumentError("$fname: x-grid (FIRSTX=$firstx, LASTX=$lastx, DELTAX=$deltax) inconsistent with NPOINTS=$npoints"))

    doff = n - datalen
    y = Float64.(ltoh.(reinterpret(Float32, bytes[doff+1:n])))
    x = collect(firstx .+ deltax .* (0:npoints-1))

    epoch = read_le(Int32, bytes, OFF_EPOCH)
    date = epoch > 0 ? unix2datetime(epoch) : DateTime(2000)

    serial  = read_cstr(bytes, OFF_SERIAL, 32, encoding)
    title   = read_cstr(bytes, OFF_TITLE, 64, encoding)
    comment = read_cstr(bytes, OFF_COMMENT, 64, encoding)
    isempty(title) && (title = "Untitled")

    metadata = Dict{String,Any}(
        "TITLE" => title,
        "DATA TYPE" => datatype,
        "SPECTROMETER/DATA SYSTEM" => instrument,
        "XUNITS" => xunits,
        "YUNITS" => yunits,
        "FIRSTX" => firstx,
        "LASTX" => lastx,
        "DELTAX" => deltax,
        "NPOINTS" => npoints,
        "Serial Number" => serial,
        "Comment" => comment,
        "Format" => "$fileid $version",
    )
    haskey(YMODE_CHANNEL, ymode) && (metadata["Channel"] = YMODE_CHANNEL[ymode])

    return JASCOSpectrum(title, date, instrument, datatype, xunits, yunits, x, y, metadata)
end
```

- [ ] **Step 5: Wire the include into the module**

In `src/JASCOFiles.jl`, add `include("binary.jl")` immediately after the existing `include("parser.jl")` line (currently `src/JASCOFiles.jl:21`):

```julia
include("parser.jl")
include("binary.jl")
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS — the new `"binary _read_jws (FTIR absorbance)"` testset passes; all pre-existing testsets still pass.

- [ ] **Step 7: Commit**

```bash
git add src/binary.jl src/JASCOFiles.jl test/data/ftir_test.jws test/runtests.jl
git commit -m "feat: add SPECMAN/SPECIRM binary reader (_read_jws)"
```

---

### Task 2: Wire the extension dispatcher

**Files:**
- Modify: `src/parser.jl:1` (split into dispatcher + `_read_jasco_csv`)
- Test: `test/runtests.jl` (new testset)

- [ ] **Step 1: Write the failing test**

Append to `test/runtests.jl`:

```julia
@testset "binary dispatch via JASCOSpectrum(path)" begin
    # Public entry point routes .jws to the binary reader.
    s = JASCOSpectrum(joinpath(data_dir, "ftir_test.jws"))
    @test isftir(s)
    @test length(s) == 12447
    @test s.datatype == "INFRARED SPECTRUM"

    # Non-binary extensions still route to the CSV reader (regression).
    csv = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))
    @test isftir(csv)
    @test csv.metadata["XUNITS"] == "1/CM"
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL in `"binary dispatch via JASCOSpectrum(path)"` — `JASCOSpectrum("…ftir_test.jws")` currently routes to the CSV body, which throws `ArgumentError` ("no XYDATA section found") on binary input.

- [ ] **Step 3: Split the constructor into a dispatcher + `_read_jasco_csv`**

In `src/parser.jl`, replace the first line (currently `src/parser.jl:1`):

```julia
function JASCOSpectrum(path::AbstractString; encoding=enc"SHIFT-JIS", translate::Bool=true)
```

with the dispatcher followed by the renamed CSV body:

```julia
function JASCOSpectrum(path::AbstractString; encoding=enc"SHIFT-JIS", translate::Bool=true)
    ext = lowercase(splitext(path)[2])
    if ext == ".jws" || ext == ".jrs"
        return _read_jws(path; encoding=encoding)
    end
    return _read_jasco_csv(path; encoding=encoding, translate=translate)
end

function _read_jasco_csv(path::AbstractString; encoding=enc"SHIFT-JIS", translate::Bool=true)
```

The rest of the existing function body (from `raw_metadata = Dict…` through its closing `end`) is unchanged — it now belongs to `_read_jasco_csv`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS — both new assertions pass, and every existing CSV/Raman/UV-Vis/footer/error-path testset still passes (they all call `JASCOSpectrum` on `.csv` paths, which route to `_read_jasco_csv`).

- [ ] **Step 5: Commit**

```bash
git add src/parser.jl test/runtests.jl
git commit -m "feat: route .jws/.jrs to the binary reader from JASCOSpectrum(path)"
```

---

### Task 3: UV-Vis read tests (absorbance + %T)

**Files:**
- Create: `test/data/uvvis_abs.jws`, `test/data/uvvis_trans.jws`
- Test: `test/runtests.jl` (new testset)

These exercise the V-series instrument branch (blank datatype, `NANOMETERS`, descending grid) and a non-absorbance y-mode. The Task 1 implementation already covers them via the decode tables; the tests confirm that coverage.

- [ ] **Step 1: Copy the UV-Vis fixtures**

```bash
cp ~/Downloads/uvvis/abs.jws test/data/uvvis_abs.jws
cp ~/Downloads/uvvis/t.jws   test/data/uvvis_trans.jws
```

- [ ] **Step 2: Write the test**

Append to `test/runtests.jl`:

```julia
@testset "binary UV-Vis (V-730)" begin
    a = JASCOSpectrum(joinpath(data_dir, "uvvis_abs.jws"))
    @test a.spectrometer == "V-730"
    @test a.datatype == ""              # V-series export omits DATA TYPE
    @test a.xunits == "NANOMETERS"
    @test a.yunits == "ABSORBANCE"
    @test isuvvis(a)                    # inferred from NANOMETERS + range
    @test !isftir(a)
    @test length(a) == 61
    @test a.x[1] == 700.0
    @test a.x[end] == 400.0             # descending grid (DELTAX < 0)
    @test round(a.y[1], sigdigits=4) ≈ -6.388e-5

    t = JASCOSpectrum(joinpath(data_dir, "uvvis_trans.jws"))
    @test t.yunits == "TRANSMITTANCE"
    @test isuvvis(t)
    @test all(>(90), t.y)               # blank-cell %T sits near 100
end
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS. If `a.datatype`/`yunits`/grid assertions fail, the failure names the wrong value — fix the corresponding decode-table entry or `_instrument_kind` branch in `src/binary.jl`.

- [ ] **Step 4: Commit**

```bash
git add test/data/uvvis_abs.jws test/data/uvvis_trans.jws test/runtests.jl
git commit -m "test: UV-Vis (V-730) .jws absorbance and transmittance"
```

---

### Task 4: `.jrs` (SPECIRM) parity

**Files:**
- Create: `test/data/uvvis_abs.jrs`
- Test: `test/runtests.jl` (new testset)

- [ ] **Step 1: Copy the `.jrs` fixture**

```bash
cp ~/Downloads/uvvis/abs.jrs test/data/uvvis_abs.jrs
```

- [ ] **Step 2: Write the test**

Append to `test/runtests.jl`:

```julia
@testset "binary .jrs (SPECIRM) parity" begin
    jws = JASCOSpectrum(joinpath(data_dir, "uvvis_abs.jws"))
    jrs = JASCOSpectrum(joinpath(data_dir, "uvvis_abs.jrs"))
    # Same measurement in the instrument-firmware format: identical data.
    @test jrs.x == jws.x
    @test jrs.y == jws.y
    @test jrs.datatype == jws.datatype
    @test jrs.xunits == jws.xunits
    @test jrs.yunits == jws.yunits
    @test startswith(jrs.metadata["Format"], "SPECIRM")
    @test isuvvis(jrs)
end
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS. `.jrs` routes through the dispatcher (Task 2) and `JWS_IDS` already includes `"SPECIRM"`.

- [ ] **Step 4: Commit**

```bash
git add test/data/uvvis_abs.jrs test/runtests.jl
git commit -m "test: .jrs (SPECIRM) decodes identically to .jws"
```

---

### Task 5: Fail-fast validation error paths (synthetic fixtures)

**Files:**
- Test: `test/runtests.jl` (add `make_jws` helper + error-path testset)

`make_jws` builds a minimal valid binary file in memory; each test mutates one aspect to trigger one gate. No binary fixtures are committed for these.

- [ ] **Step 1: Add the `make_jws` helper**

Add near the top of `test/runtests.jl`, after the `data_dir` definition (currently `runtests.jl:9`):

```julia
# Build a minimal valid SPECMAN/SPECIRM byte vector for error-path tests.
function make_jws(; id="SPECMAN", instrument="FT/IR-4600typeA",
                    xunit=0x00, ymode=0x03, npoints=4,
                    firstx=1000.0, deltax=1.0)
    n = 0x740 + npoints * 4
    b = zeros(UInt8, n)
    b[1:4] = collect(b"L~S ")
    b[OFFW(0x08, id)] = Vector{UInt8}(id)
    b[OFFW(0x20, "R2.0.0")] = Vector{UInt8}("R2.0.0")
    b[0x84+1:0x84+4] = reinterpret(UInt8, [htol(Int32(npoints))])
    b[0x88+1:0x88+8] = reinterpret(UInt8, [htol(Float64(firstx))])
    b[0x90+1:0x90+8] = reinterpret(UInt8, [htol(Float64(firstx + deltax * (npoints - 1)))])
    b[0x98+1:0x98+8] = reinterpret(UInt8, [htol(Float64(deltax))])
    b[0xA0+1] = xunit
    b[0xA1+1] = 0x01; b[0xA2+1] = 0x00; b[0xA3+1] = 0x10
    b[0xA4+1] = ymode
    b[0xC8+1:0xC8+8] = reinterpret(UInt8, [htol(Int64(npoints * 4))])
    b[OFFW(0x140, instrument)] = Vector{UInt8}(instrument)
    return b
end
OFFW(off, s) = (off+1):(off+length(s))   # 1-based byte range for a string field at 0-based off

function write_jws(bytes)
    path = tempname() * ".jws"
    write(path, bytes)
    return path
end
```

- [ ] **Step 2: Write the error-path tests**

Append to `test/runtests.jl`:

```julia
@testset "binary error paths" begin
    # A baseline make_jws() file is valid and parses.
    @test JASCOSpectrum(write_jws(make_jws())) isa JASCOSpectrum

    # Too small
    @test_throws "too short" JASCOSpectrum(write_jws(make_jws()[1:200]))

    # Bad magic
    bad = make_jws(); bad[1] = 0x00
    @test_throws "missing 'L~S '" JASCOSpectrum(write_jws(bad))

    # Unrecognized container id
    @test_throws "unrecognized binary variant" JASCOSpectrum(write_jws(make_jws(id="FOOBAR")))

    # Unsupported instrument
    @test_throws "unsupported instrument" JASCOSpectrum(write_jws(make_jws(instrument="NRS-5100")))

    # x-unit / instrument mismatch (FTIR but nm code)
    @test_throws "x-unit code" JASCOSpectrum(write_jws(make_jws(xunit=0x03)))

    # Unknown y-mode code
    @test_throws "unrecognized y-mode" JASCOSpectrum(write_jws(make_jws(ymode=0x07)))

    # NPOINTS / data-length mismatch: overwrite NPOINTS so it disagrees with datalen
    badn = make_jws(npoints=4)
    badn[0x84+1:0x84+4] = reinterpret(UInt8, [htol(Int32(9))])
    @test_throws "inconsistent point count" JASCOSpectrum(write_jws(badn))

    # Grid inconsistency: overwrite LASTX so the grid no longer matches NPOINTS
    badg = make_jws(npoints=4, firstx=1000.0, deltax=1.0)
    badg[0x90+1:0x90+8] = reinterpret(UInt8, [htol(Float64(9999.0))])
    @test_throws "inconsistent with NPOINTS" JASCOSpectrum(write_jws(badg))
end
```

- [ ] **Step 3: Run the tests to verify they pass**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS — each `@test_throws` matches the substring of the `ArgumentError` thrown by the corresponding gate in `_read_jws`.

- [ ] **Step 4: Commit**

```bash
git add test/runtests.jl
git commit -m "test: fail-fast validation gates for the binary reader"
```

---

### Task 6: `.txt` ground-truth cross-check + source parity

**Files:**
- Create: `test/data/uvvis_abs.txt`
- Test: `test/runtests.jl` (new testset)

Validates the binary decode against JASCO's own text export of the same file, and confirms a `.jws` and a `.txt` of one measurement yield equivalent structs.

- [ ] **Step 1: Copy the `.txt` export**

```bash
cp ~/Downloads/uvvis/abs.txt test/data/uvvis_abs.txt
```

- [ ] **Step 2: Write the test**

Append to `test/runtests.jl`:

```julia
@testset "binary vs .txt ground truth (UV-Vis abs)" begin
    bin = JASCOSpectrum(joinpath(data_dir, "uvvis_abs.jws"))
    txt = JASCOSpectrum(joinpath(data_dir, "uvvis_abs.txt"))  # routes to CSV/tab reader

    # Same shape and grid.
    @test length(bin) == length(txt)
    @test bin.x ≈ txt.x

    # Values agree to the text export's displayed precision (~6 sig figs).
    @test all(isapprox.(bin.y, txt.y; atol=1e-6, rtol=1e-4))

    # Source parity: the binary reader reproduces the export's units/datatype.
    @test bin.datatype == txt.datatype   # both "" for V-730
    @test bin.xunits == txt.xunits        # NANOMETERS
    @test bin.yunits == txt.yunits        # ABSORBANCE
    @test isuvvis(bin) == isuvvis(txt) == true
    @test xlabel(bin) == xlabel(txt)
    @test ylabel(bin) == ylabel(txt)
end
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS — the binary `x`/`y` match the text export within text precision, and units/labels match.

- [ ] **Step 4: Commit**

```bash
git add test/data/uvvis_abs.txt test/runtests.jl
git commit -m "test: cross-check binary decode against JASCO .txt export"
```

---

### Task 7: Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/src/guide/file-formats.md`
- Modify: `CLAUDE.md`
- Modify: `src/JASCOFiles.jl:1-13` (module docstring)

- [ ] **Step 1: README — drop the "does not read .jws" claim, add binary support**

In `README.md`, replace:

```
JASCOFiles.jl reads CSV files exported from JASCO spectrometers (FTIR, Raman, UV-Vis).
It does not read .jws files directly—export raw data to CSV from the JASCO software.
```

with:

```
JASCOFiles.jl reads JASCO spectrometer files (FTIR, Raman, UV-Vis): the CSV/text
exports from Spectra Manager, and the native binary `.jws` / `.jrs` files
(FTIR and UV-Vis) directly — no manual export step.

`.jws` is written by the desktop Spectra Manager software; `.jrs` is the same
spectrum as written by the spectrometer's onboard firmware. Both decode to the
same `JASCOSpectrum`.
```

Add a usage line after the existing `s = JASCOSpectrum("path/to/spectrum.csv")` example:

```julia
# Native binary files work through the same entry point
s = JASCOSpectrum("path/to/spectrum.jws")   # or .jrs
```

- [ ] **Step 2: file-formats.md — add a binary-format section**

In `docs/src/guide/file-formats.md`, after the "Per-instrument variants" section (before "## Encoding", currently `file-formats.md:69`), insert:

````markdown
## Binary files (`.jws` / `.jrs`)

`JASCOSpectrum(path)` also reads JASCO's native binary spectra directly (FTIR and
UV-Vis). Two on-disk formats share one container (`SPECMAN R2.0.0`):

- **`.jws`** — written by the desktop **Spectra Manager** software (header
  stamped `SPECMAN`, `i80x86`, `MSVC`).
- **`.jrs`** — the same spectrum written by the spectrometer's **onboard
  firmware** (`SPECIRM`, `MCF5328`, `CodeWarrior`).

The spectral data is identical between them; only the writer-provenance header
fields differ. Both decode to the same `JASCOSpectrum`.

Little-endian, fixed-offset header, then a trailing `Float32` data block:

| Offset | Type | Field |
|--------|------|-------|
| `0x00` | char[4] | magic `"L~S "` |
| `0x08` | str | format id (`SPECMAN` / `SPECIRM`) |
| `0x84` | Int32 | NPOINTS |
| `0x88`/`0x90`/`0x98` | Float64 | FIRSTX / LASTX / DELTAX (signed) |
| `0xA0` | UInt8 | x-unit code (`0` = cm⁻¹, `3` = nm) |
| `0xA4` | UInt8 | y-mode code (see below) |
| `0xC8` | Int64 | data-block length (= NPOINTS × 4) |
| `0x140` | str | instrument model |
| `0x160` | str | serial number |
| `0x180` | str | title |
| `0x2C0` | Int32 | acquisition time (Unix epoch, UTC) |
| `filesize − len` … EOF | Float32[NPOINTS] | y-data |

`datatype` and `xunits` are decoded from the instrument model (`FT/IR…` →
infrared/`1/CM`; `V-…` → UV-Vis/`NANOMETERS`, with `DATA TYPE` left blank to
match the V-series text export). `yunits` is decoded from the y-mode code:

| `0xA4` | `YUNITS` |
|--------|----------|
| `0x00` | TRANSMITTANCE |
| `0x02` | REFLECTANCE |
| `0x03` | ABSORBANCE |
| `0x09` / `0x0a` | INTENSITY (single-beam reference / sample) |

Unsupported instruments (e.g. Raman NRS) and unknown y-mode codes throw an
`ArgumentError` naming the file. Timestamps decode as UTC (the stored epoch),
unlike the CSV path which records local time.
````

- [ ] **Step 3: CLAUDE.md — structure + formats**

In `CLAUDE.md`, add `binary.jl` to the package-structure block:

```
├── parser.jl        # File parsing logic (CSV/text dispatcher + reader)
├── binary.jl        # Native .jws/.jrs (SPECMAN/SPECIRM) binary reader
```

And add binary rows to the supported-instruments/formats table:

```
| FTIR/UV-Vis | (binary) | .jws / .jrs | Implemented (native) |
```

- [ ] **Step 4: Module docstring**

In `src/JASCOFiles.jl`, update the first docstring paragraph (currently `src/JASCOFiles.jl:4-7`) to mention binary support. Replace:

```julia
Read CSV files exported from JASCO spectrometers (FTIR, Raman, UV-Vis) into a
concrete [`JASCOSpectrum`](@ref) struct. The parser auto-detects the delimiter
(comma for FTIR/Raman, tab for V-series UV-Vis) and decodes SHIFT-JIS metadata
by default.
```

with:

```julia
Read JASCO spectrometer files into a concrete [`JASCOSpectrum`](@ref) struct:
the CSV/text exports (FTIR, Raman, UV-Vis; delimiter auto-detected, SHIFT-JIS
by default) and the native binary `.jws` (SPECMAN) and `.jrs` (SPECIRM) files
for FTIR and UV-Vis. `JASCOSpectrum(path)` dispatches on the file extension.
```

- [ ] **Step 5: Build the docs to verify they render (optional but recommended)**

Run: `julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'` then `julia --project=docs docs/make.jl`
Expected: docs build without errors. (Skip if the docs environment is not set up; the prose edits are plain Markdown.)

- [ ] **Step 6: Commit**

```bash
git add README.md docs/src/guide/file-formats.md CLAUDE.md src/JASCOFiles.jl
git commit -m "docs: document native .jws/.jrs binary reading"
```

---

### Task 8: Version bump + final verification

**Files:**
- Modify: `Project.toml:5`

- [ ] **Step 1: Bump the version**

In `Project.toml`, change:

```toml
version = "1.1.0"
```

to:

```toml
version = "1.2.0"
```

- [ ] **Step 2: Run the full test suite (including Aqua)**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS — all testsets, including `"Code quality (Aqua.jl)"`. Aqua checks no new dependencies were left undeclared, no method ambiguities were introduced, and no stale compat entries exist. `_read_jws` is internal (not exported), so the export surface is unchanged.

- [ ] **Step 3: Commit**

```bash
git add Project.toml
git commit -m "chore: bump version to 1.2.0"
```

---

## Self-Review

**Spec coverage:**
- Dispatch on `.jws`/`.jrs` extension, same struct → Task 2 (dispatcher), Task 1 (`_read_jws` returns `JASCOSpectrum`). ✓
- SPECMAN + SPECIRM ids accepted → `JWS_IDS` in Task 1; `.jrs` parity Task 4. ✓
- Format table offsets (NPOINTS, FIRSTX/LASTX/DELTAX, x-unit, y-mode, datalen, instrument, serial, title, epoch, data block) → all read in Task 1 `_read_jws`. ✓
- y-mode decode (0x00/0x02/0x03/0x09/0x0a) → `YMODE_YUNITS`/`YMODE_CHANNEL` Task 1; tested Tasks 3 (T), 6 (abs); INTENSITY codes covered by table. ✓
- datatype/xunits from instrument; UV-Vis datatype blank → `_instrument_kind` Task 1; tested Task 3 (`datatype == ""`). ✓
- 8 validation gates → Task 1 `_read_jws` (checks 1–8); each tested in Task 5. ✓
- Metadata mirroring CSV keys + native numeric types + Channel/Format → Task 1 `metadata` dict; tested Task 1 (`NPOINTS`, `Serial Number`, `Format`), Task 4 (`Format`). ✓
- Fixtures (ftir_test.jws, uvvis_abs.jws, uvvis_trans.jws, uvvis_abs.jrs, uvvis_abs.txt) + synthetic → Tasks 1,3,4,6 (real) and Task 5 (`make_jws`). ✓
- `.txt` ground-truth cross-check + source parity → Task 6. ✓
- Extension-dispatch regression (CSV still works) → Task 2 test. ✓
- Docs (README, file-formats.md, CLAUDE.md, docstring) → Task 7. ✓
- No new deps, Aqua green, version bump → Task 8. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases". Every code and command step is complete. ✓

**Type consistency:** `_read_jws(path; encoding)` defined Task 1, called Task 2 with `encoding=` kwarg. ✓ `_read_jasco_csv(path; encoding, translate)` defined Task 2, called by dispatcher with both kwargs. ✓ `read_le`/`read_cstr`/`_instrument_kind` defined and used within Task 1. ✓ `YMODE_YUNITS`/`YMODE_CHANNEL`/`JWS_IDS`/offset consts defined Task 1, used in `_read_jws`. ✓ `make_jws`/`write_jws`/`OFFW` defined Task 5, used in Task 5 tests. ✓ Metadata keys asserted in tests (`"Serial Number"`, `"NPOINTS"`, `"Format"`, `"XUNITS"`) match those written in Task 1's `metadata` dict. ✓ `data_dir` is the existing `runtests.jl:9` binding. ✓

**Note for the implementer:** `make_jws` uses `htol` for host-independent little-endian writes, mirroring `read_le`'s `ltoh`. `OFFW(off, s)` must be defined before `make_jws` uses it, or (since it is a one-liner) Julia resolves it at call time within the same module scope — both are fine in `runtests.jl`.
