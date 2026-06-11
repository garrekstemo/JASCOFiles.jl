using Test
using JASCOFiles
using Dates
using Aqua
using StringEncodings
using Makie
using Tables

data_dir = joinpath(@__DIR__, "data")
spectrum_file = joinpath(data_dir, "ftir_test.csv")

# 1-based byte range for a string field at 0-based offset `off`.
OFFW(off, s) = (off+1):(off+length(s))

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

function write_jws(bytes)
    path = tempname() * ".jws"
    write(path, bytes)
    return path
end

# Write an ASCII CSV fixture to a temp file (ASCII is valid SHIFT-JIS).
function write_csv(content; ext=".csv")
    path = tempname() * ext
    write(path, content)
    return path
end

@testset "Code quality (Aqua.jl)" begin
    Aqua.test_all(JASCOFiles; deps_compat=(check_extras=false, ignore=[:Dates],))
end

@testset "read JASCO FTIR csv file" begin
    s = JASCOSpectrum(spectrum_file)

    # Check first and last X values (Wavenumbers)
    @test s.x[1] == 999.9101
    @test round(s.x[end], sigdigits=8) == 7000.335

    # Check first Y value (Absorbance)
    @test round(s.y[1], sigdigits=3) ≈ 0.573

    @test length(s.x) == 12447
    @test length(s.y) == 12447

    # Test Metadata Extraction
    @test s.metadata["XUNITS"] == "1/CM"
    @test s.metadata["YUNITS"] == "ABSORBANCE"
    @test s.datatype == "INFRARED SPECTRUM"

    @test s.date == DateTime(2023, 1, 11, 16, 49, 31)
end

@testset "strict data rows (2.0)" begin
    # Unparseable rows inside the data section are corruption, not noise:
    # the parser throws instead of silently dropping them (1.x behavior).
    @test_throws "unparseable data row" JASCOSpectrum(joinpath(data_dir, "ftir_malformed.csv"))
    @test_throws "unparseable data row" JASCOSpectrum(joinpath(data_dir, "raman_malformed.csv"))

    # NPOINTS-complete data followed by an unmarked footer (no blank line):
    # once the declared point count is reached, non-data lines flip the
    # parser to footer mode instead of throwing.
    p = write_csv("TITLE,Flip\nNPOINTS,2\nXYDATA\n1,0.5\n2,0.6\n[Section]\nOperator,Bob\n")
    s = JASCOSpectrum(p)
    @test length(s.x) == 2
    @test s.metadata["Operator"] == "Bob"

    # Header FIRSTX must agree with the first parsed x value.
    pbad = write_csv("TITLE,F\nFIRSTX,500\nDELTAX,1\nXYDATA\n1000,0.1\n1001,0.2\n")
    @test_throws "FIRSTX" JASCOSpectrum(pbad)
end

@testset "honest metadata defaults (2.0)" begin
    # Missing header fields stay empty instead of fabricating
    # "Unknown"/"cm-1"/"Abs" placeholders.
    p = write_csv("TITLE,Bare\nXYDATA\n1,1\n2,2\n")
    s = JASCOSpectrum(p)
    @test s.title == "Bare"
    @test s.spectrometer == ""
    @test s.datatype == ""
    @test s.xunits == ""
    @test s.yunits == ""
    @test s.date === nothing
end

@testset "read JASCO Raman csv file" begin
    raman_file = joinpath(data_dir, "raman_test.csv")
    s = JASCOSpectrum(raman_file)

    # Check data type
    @test s.datatype == "RAMAN SPECTRUM"

    # Check units (Raman uses intensity, not absorbance)
    @test s.yunits == "INTENSITY"
    @test s.xunits == "1/CM"

    # Check first and last X values (Raman shift)
    @test s.x[1] == 545.8049
    @test round(s.x[end], sigdigits=8) == 1597.9994

    # Check first Y value (intensity)
    @test s.y[1] == 199

    @test length(s.x) == 1024
    @test length(s.y) == 1024

    @test s.date == DateTime(2024, 11, 5, 15, 23, 6)
end

@testset "read JASCO UV-Vis csv file" begin
    uvvis_file = joinpath(data_dir, "uvvis_test.csv")
    s = JASCOSpectrum(uvvis_file)

    # V-730 exports use tab delimiters and leave DATA TYPE blank
    @test s.datatype == ""
    @test s.xunits == "NANOMETERS"
    @test s.yunits == "ABSORBANCE"
    @test s.spectrometer == "JASCO Corp., V-730, Rev. 1.00"

    # 1001 points from 1000 nm down to 500 nm in 0.5 nm steps
    @test length(s.x) == 1001
    @test s.x[1] == 1000.0
    @test s.x[end] == 500.0
    @test s.y[1] == -0.0983645
    @test s.y[end] == -0.0549044

    @test s.date == DateTime(2026, 2, 12, 12, 23, 0)
end

@testset "footer metadata (FTIR)" begin
    s = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))

    # Original Japanese keys preserved
    @test s.metadata["積算回数"] == "16"
    @test s.metadata["検出器"] == "TGS"
    @test s.metadata["会社"] == "Test Lab"

    # English alias keys added
    @test s.metadata["Accumulation"] == "16"
    @test s.metadata["Detector"] == "TGS"
    @test s.metadata["Company"] == "Test Lab"

    # Value translation
    @test s.metadata["光源"] == "Standard light source"
    @test s.metadata["Light source"] == "Standard light source"
    @test s.metadata["データタイプ"] == "Linear data array"
    @test s.metadata["Data array type"] == "Linear data array"

    # Header still intact
    @test s.metadata["DATA TYPE"] == "INFRARED SPECTRUM"

    # Section markers and decorations are dropped, not stored
    @test !haskey(s.metadata, "[測定情報]")
    @test !haskey(s.metadata, "[コメント情報]")
    @test !haskey(s.metadata, "[データ情報]")
    @test !haskey(s.metadata, "##### Extended Information")
end

@testset "footer metadata (Raman, English fixture)" begin
    s = JASCOSpectrum(joinpath(data_dir, "raman_test.csv"))

    @test s.metadata["Laser wavelength"] == "532.05 nm"
    @test s.metadata["Accumulation"] == "2"
    @test s.metadata["CCD temperature"] == "-69.0 C"
    @test s.metadata["Company"] == "Test Lab"
end

@testset "footer metadata (Japanese Raman, NRS-5100)" begin
    s = JASCOSpectrum(joinpath(data_dir, "raman_japanese_test.csv"))

    # SPECTROMETER/DATA SYSTEM is blank in the header; spectrometer comes from
    # the 機種名 footer key.
    @test s.datatype == "RAMAN SPECTRUM"
    @test s.spectrometer == "NRS-5100"

    # Raman-specific keys translated to JASCO's English UI terms
    @test s.metadata["励起波長"] == "532.05 nm"
    @test s.metadata["Laser wavelength"] == "532.05 nm"

    @test s.metadata["レーザー強度"] == "0.7 mW"
    @test s.metadata["Laser power"] == "0.7 mW"

    @test s.metadata["対物レンズ"] == "MPLFLN 100 x"
    @test s.metadata["Objective lens"] == "MPLFLN 100 x"

    @test s.metadata["CCD温度"] == "-69.0 C"
    @test s.metadata["CCD temperature"] == "-69.0 C"

    @test s.metadata["ビニング上限"] == "90"
    @test s.metadata["Binning Upper"] == "90"

    # Updated key aliases (used to be Measurer/Affiliation)
    @test s.metadata["測定者"] == "Test User"
    @test s.metadata["User"] == "Test User"

    # Value translations
    @test s.metadata["分光器"] == "Single"          # シングル → Single
    @test s.metadata["Monochromator"] == "Single"

    @test s.metadata["データタイプ"] == "Non-linear data array"
    @test s.metadata["Data array type"] == "Non-linear data array"
end

@testset "footer metadata (UV-Vis, tab-delimited, no ##### marker)" begin
    s = JASCOSpectrum(joinpath(data_dir, "uvvis_test.csv"))

    # Value translation: 自動 → Automatic
    @test s.metadata["光源"] == "Automatic"
    @test s.metadata["Light source"] == "Automatic"

    @test s.metadata["測光モード"] == "Abs"
    @test s.metadata["Photometric mode"] == "Abs"
    @test s.metadata["付属品名"] == "USE-753"
    @test s.metadata["Accessory name"] == "USE-753"
end

@testset "footer metadata opt-out (translate=false)" begin
    s = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"); translate=false)

    # Originals preserved, values left raw
    @test s.metadata["光源"] == "標準光源"
    @test s.metadata["積算回数"] == "16"

    # No English aliases added
    @test !haskey(s.metadata, "Accumulation")
    @test !haskey(s.metadata, "Light source")
end

@testset "type predicates" begin
    ftir = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))
    raman = JASCOSpectrum(joinpath(data_dir, "raman_test.csv"))
    uvvis = JASCOSpectrum(joinpath(data_dir, "uvvis_test.csv"))

    @test isftir(ftir)
    @test !israman(ftir)
    @test !isuvvis(ftir)

    @test !isftir(raman)
    @test israman(raman)
    @test !isuvvis(raman)

    @test !isftir(uvvis)
    @test !israman(uvvis)
    @test isuvvis(uvvis)
end

@testset "show methods" begin
    ftir = JASCOSpectrum(spectrum_file)

    mime_out = sprint(show, MIME("text/plain"), ftir)
    @test occursin("JASCOSpectrum: INFRARED SPECTRUM", mime_out)
    @test occursin("12447 points", mime_out)
    @test occursin("range:", mime_out)
    @test occursin("metadata:", mime_out)

    compact_out = sprint(show, ftir)
    @test occursin("JASCOSpectrum(", compact_out)
    @test occursin("INFRARED SPECTRUM", compact_out)
    @test !occursin('\n', compact_out)

    # Empty-spectrum path: no "range:" line; unknown date prints as such
    empty_s = JASCOSpectrum(x=Float64[], y=Float64[], datatype="UNKNOWN")
    empty_out = sprint(show, MIME("text/plain"), empty_s)
    @test !occursin("range:", empty_out)
    @test occursin("0 points", empty_out)
    @test occursin("unknown", empty_out)   # date === nothing
end

@testset "error paths" begin
    @test_throws SystemError JASCOSpectrum("this_file_does_not_exist.csv")
    @test JASCOSpectrum <: AbstractJASCOSpectrum

    # Invalid-input validation: the constructor must throw, not silently
    # return an empty/defaulted spectrum (see 2026-05-29 validation spec).
    @test_throws "no XYDATA section" JASCOSpectrum(joinpath(data_dir, "not_a_spectrum.csv"))
    @test_throws "NPOINTS=512 but found 3" JASCOSpectrum(joinpath(data_dir, "wrong_npoints.csv"))

    # Junk rows after XYDATA are an unparseable-row error (2.0 strictness)…
    @test_throws "unparseable data row" JASCOSpectrum(joinpath(data_dir, "empty_xydata.csv"))
    # …while an XYDATA section with no rows at all is an empty-data error.
    @test_throws "no parseable data points" JASCOSpectrum(write_csv("TITLE,E\nXYDATA\n"))
end

@testset "Japanese SHIFT-JIS header" begin
    s = JASCOSpectrum(joinpath(data_dir, "japanese_header_test.csv"))
    # 機種名 is JASCO's Japanese key for spectrometer/model name; parser uses it
    # as the fallback when SPECTROMETER/DATA SYSTEM is absent (see parser.jl).
    @test s.spectrometer == "JASCO FT/IR-4700"
    @test s.title == "Japanese Header Test"
    @test haskey(s.metadata, "機種名")
end

@testset "encoding kwarg" begin
    default_call = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))
    explicit_call = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"); encoding=enc"SHIFT-JIS")
    @test default_call.title == explicit_call.title
    @test default_call.x == explicit_call.x
end

@testset "transmittance ↔ absorbance (unit-aware, 2.0)" begin
    s = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))  # yunits ABSORBANCE

    # absorbance → transmittance requires an explicit output scale
    t = absorbance_to_transmittance(s; percent=true)
    @test t.yunits == "TRANSMITTANCE"
    @test t.x === s.x
    @test t.metadata === s.metadata
    @test t.title == s.title

    # %T → absorbance: scale inferred from yunits; canonical output units
    a = transmittance_to_absorbance(t)
    @test a.yunits == "ABSORBANCE"
    @test a.y ≈ s.y atol=1e-12

    # Fractional round-trip via inference
    tf = absorbance_to_transmittance(s; percent=false)
    @test tf.yunits == "TRANSMITTANCE_FRAC"
    af = transmittance_to_absorbance(tf)
    @test af.yunits == "ABSORBANCE"
    @test af.y ≈ s.y atol=1e-12

    # Landmarks with inferred scale: T=10% → A=1, T=1% → A=2
    landmark = JASCOSpectrum(x=[500.0, 600.0], y=[10.0, 1.0],
                             datatype="UV/VIS SPECTRUM", xunits="NANOMETERS",
                             yunits="TRANSMITTANCE")
    @test transmittance_to_absorbance(landmark).y ≈ [1.0, 2.0]

    landmark_frac = JASCOSpectrum(landmark; x=[500.0], y=[0.5],
                                  yunits="TRANSMITTANCE_FRAC")
    @test transmittance_to_absorbance(landmark_frac).y ≈ [-log10(0.5)]

    # Explicit percent always overrides yunits inference
    @test transmittance_to_absorbance(landmark; percent=false).y ≈ [-1.0, 0.0]

    # Nonpositive transmittance (saturated bands, detector noise) maps to
    # NaN with a warning, rather than crashing on log10
    sat = JASCOSpectrum(x=[1.0, 2.0, 3.0], y=[50.0, 0.0, -0.1],
                        yunits="TRANSMITTANCE")
    asat = @test_logs (:warn, r"nonpositive") transmittance_to_absorbance(sat)
    @test asat.y[1] ≈ -log10(0.5)
    @test isnan(asat.y[2])
    @test isnan(asat.y[3])

    # Binary %T file: inference works straight off the instrument file
    tbin = JASCOSpectrum(joinpath(data_dir, "uvvis_trans.jws"))
    abin = transmittance_to_absorbance(tbin)
    @test abin.yunits == "ABSORBANCE"
    @test abin.y ≈ -log10.(tbin.y ./ 100)
end

@testset "conversion guards (2.0)" begin
    s_abs = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))    # ABSORBANCE
    raman = JASCOSpectrum(joinpath(data_dir, "raman_test.csv"))   # INTENSITY

    # t→a refuses input whose yunits is not a transmittance scale
    # (and no explicit percent was given to override)
    @test_throws ArgumentError transmittance_to_absorbance(s_abs)
    @test_throws ArgumentError transmittance_to_absorbance(raman)

    # a→t has no implicit output scale: percent is a required keyword
    @test_throws UndefKeywordError absorbance_to_transmittance(s_abs)

    # a→t refuses input that is already transmittance
    t = absorbance_to_transmittance(s_abs; percent=true)
    @test_throws ArgumentError absorbance_to_transmittance(t; percent=true)
end

@testset "axis labels" begin
    ftir = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))
    raman = JASCOSpectrum(joinpath(data_dir, "raman_test.csv"))
    uvvis = JASCOSpectrum(joinpath(data_dir, "uvvis_test.csv"))

    @test xlabel(ftir) == "Wavenumber (cm⁻¹)"
    @test ylabel(ftir) == "Absorbance"

    @test xlabel(raman) == "Raman shift (cm⁻¹)"
    @test ylabel(raman) == "Intensity"

    @test xlabel(uvvis) == "Wavelength (nm)"
    @test ylabel(uvvis) == "Absorbance"

    # Transmittance variants from the transforms
    t = absorbance_to_transmittance(ftir; percent=true)
    @test ylabel(t) == "Transmittance (%)"
    tf = absorbance_to_transmittance(ftir; percent=false)
    @test ylabel(tf) == "Transmittance"

    # Unknown units fall back to title-casing the raw value
    weird = JASCOSpectrum(x=Float64[], y=Float64[], datatype="INFRARED SPECTRUM",
                          xunits="kelvin", yunits="candelas")
    @test xlabel(weird) == "Kelvin"
    @test ylabel(weird) == "Candelas"

    # Empty units (honest defaults) yield empty labels, not fabricated ones
    bare = JASCOSpectrum(x=[1.0], y=[1.0])
    @test xlabel(bare) == ""
    @test ylabel(bare) == ""
end

@testset "Makie extension" begin
    s = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))

    # convert_arguments trait method enables lines(s), scatter(s), lines!(ax, s)
    @test Makie.convert_arguments(Makie.PointBased(), s) ==
          Makie.convert_arguments(Makie.PointBased(), s.x, s.y)

    # End-to-end: lines(s) and scatter(s) work without going through .x/.y
    fap = Makie.lines(s)
    @test fap isa Makie.FigureAxisPlot

    # plot defaults: labels, title, xreversed for FTIR
    fig, ax, plt = plot(s)
    @test fig isa Makie.Figure
    @test ax isa Makie.Axis
    @test ax.xlabel[] == "Wavenumber (cm⁻¹)"
    @test ax.ylabel[] == "Absorbance"
    @test ax.title[] == s.title
    @test ax.xreversed[] == true

    # User `axis` NamedTuple overrides defaults
    _, ax2, _ = plot(s; axis=(xreversed=false, title="custom"))
    @test ax2.xreversed[] == false
    @test ax2.title[] == "custom"

    # Raman: no x-reversal
    r = JASCOSpectrum(joinpath(data_dir, "raman_test.csv"))
    _, axr, _ = plot(r)
    @test axr.xreversed[] == false
    @test axr.xlabel[] == "Raman shift (cm⁻¹)"
end

@testset "Tables.jl interface" begin
    s = JASCOSpectrum(spectrum_file)

    @test Tables.istable(JASCOSpectrum)
    @test Tables.istable(s)
    @test Tables.columnaccess(JASCOSpectrum)
    @test Tables.columnaccess(s)

    cols = Tables.columns(s)
    @test propertynames(cols) == (:x, :y)
    @test cols.x === s.x
    @test cols.y === s.y

    sch = Tables.schema(s)
    @test sch.names == (:x, :y)
    @test sch.types == (Float64, Float64)

    # Round-trip through Tables.columntable: same data, same column names.
    ct = Tables.columntable(s)
    @test ct.x == s.x
    @test ct.y == s.y

    # Row-access works through the generic Tables fallback over column access.
    rows = collect(Tables.rows(s))
    @test length(rows) == length(s.x)
    @test Tables.getcolumn(rows[1], :x) == s.x[1]
    @test Tables.getcolumn(rows[1], :y) == s.y[1]
end

@testset "binary dispatch via JASCOSpectrum(path)" begin
    # Public entry point routes .jws to the binary reader.
    s = JASCOSpectrum(joinpath(data_dir, "ftir_test.jws"))
    @test isftir(s)
    @test length(s.x) == 12447
    @test s.datatype == "INFRARED SPECTRUM"

    # Non-binary extensions still route to the CSV reader (regression).
    csv = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))
    @test isftir(csv)
    @test csv.metadata["XUNITS"] == "1/CM"
end

@testset "binary _read_jws (FTIR absorbance)" begin
    s = JASCOFiles._read_jws(joinpath(data_dir, "ftir_test.jws"))
    @test s.spectrometer == "FT/IR-4600typeA"
    @test s.datatype == "INFRARED SPECTRUM"
    @test s.xunits == "1/CM"
    @test s.yunits == "ABSORBANCE"
    @test length(s.x) == 12447
    @test round(s.x[1], digits=4) == 999.9101
    @test round(s.x[end], digits=3) == 7000.335
    @test round(s.y[1], sigdigits=3) ≈ 0.0188
    @test s.metadata["Serial Number"] == "E137161786"
    @test s.metadata["NPOINTS"] == 12447
    @test startswith(s.metadata["Format"], "SPECMAN")
    @test s.date == DateTime(2026, 6, 4, 4, 54, 3)
    @test isftir(s)
end

@testset "binary UV-Vis (V-730)" begin
    a = JASCOSpectrum(joinpath(data_dir, "uvvis_abs.jws"))
    @test a.spectrometer == "V-730"
    @test a.datatype == ""              # V-series export omits DATA TYPE
    @test a.xunits == "NANOMETERS"
    @test a.yunits == "ABSORBANCE"
    @test isuvvis(a)                    # inferred from NANOMETERS + range
    @test !isftir(a)
    @test length(a.x) == 61
    @test a.x[1] == 700.0
    @test a.x[end] == 400.0             # descending grid (DELTAX < 0)
    @test round(a.y[1], sigdigits=4) ≈ -6.388e-5

    t = JASCOSpectrum(joinpath(data_dir, "uvvis_trans.jws"))
    @test t.yunits == "TRANSMITTANCE"
    @test isuvvis(t)
    @test all(>(90), t.y)               # blank-cell %T sits near 100
end

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

@testset "binary vs .txt ground truth (UV-Vis abs)" begin
    bin = JASCOSpectrum(joinpath(data_dir, "uvvis_abs.jws"))
    txt = JASCOSpectrum(joinpath(data_dir, "uvvis_abs.txt"))  # routes to CSV/tab reader

    # Same shape and grid.
    @test length(bin.x) == length(txt.x)
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

    # Invalid DELTAX (zero) -> hardened gate 8 guard
    @test_throws "invalid DELTAX" JASCOSpectrum(write_jws(make_jws(deltax=0.0)))

    # NPOINTS / data-length mismatch: overwrite NPOINTS so it disagrees with datalen
    badn = make_jws(npoints=4)
    badn[0x84+1:0x84+4] = reinterpret(UInt8, [htol(Int32(9))])
    @test_throws "inconsistent point count" JASCOSpectrum(write_jws(badn))

    # Trailing appended bytes shift the tail-anchored data block: the reader
    # must refuse rather than silently decode garbage (data starts at 0x740
    # in every known SPECMAN/SPECIRM R2.0.0 file).
    padded = vcat(make_jws(), zeros(UInt8, 64))
    @test_throws "data layout" JASCOSpectrum(write_jws(padded))

    # A stale/mismatched stored LASTX is NOT an error: the x-axis is rebuilt
    # from FIRSTX + DELTAX*(0:n-1), so the file decodes and x[end] is computed
    # (real V-730 reflectance files do this — see uvvis_refl.jws below).
    badg = make_jws(npoints=4, firstx=1000.0, deltax=1.0)
    badg[0x90+1:0x90+8] = reinterpret(UInt8, [htol(Float64(9999.0))])
    sg = JASCOSpectrum(write_jws(badg))
    @test sg.x[end] == 1003.0
    @test sg.metadata["LASTX"] == 1003.0
end

@testset "binary UV-Vis reflectance + single-beam" begin
    # Reflectance: a real V-730 file whose stored LASTX (400) disagrees with its
    # actual 11-point grid (700 -> 650 at -5 nm). Must decode, not throw.
    r = JASCOSpectrum(joinpath(data_dir, "uvvis_refl.jws"))
    @test r.yunits == "REFLECTANCE"
    @test isuvvis(r)
    @test length(r.x) == 11
    @test r.x[1] == 700.0
    @test r.x[end] == 650.0          # computed from FIRSTX + DELTAX*(n-1); stored LASTX (400) is stale
    @test r.metadata["LASTX"] == 650.0

    # Single-beam reference and sample channels both decode as INTENSITY,
    # distinguished by the Channel metadata.
    ref = JASCOSpectrum(joinpath(data_dir, "uvvis_sb_ref.jws"))
    @test ref.yunits == "INTENSITY"
    @test ref.metadata["Channel"] == "Reference"
    @test length(ref.x) == 21
    @test ref.x[1] == 700.0 && ref.x[end] == 600.0

    samp = JASCOSpectrum(joinpath(data_dir, "uvvis_sb_sample.jws"))
    @test samp.yunits == "INTENSITY"
    @test samp.metadata["Channel"] == "Sample"
    @test length(samp.x) == 21
end

@testset "binary FTIR single-beam background (y-mode 0x08)" begin
    # Verified against a real FT/IR-4600 background scan (BG_16_4.jws,
    # 2019-09-25): y-mode 0x08 is the single-beam background channel.
    bg = JASCOSpectrum(write_jws(make_jws(ymode=0x08)))
    @test bg.yunits == "INTENSITY"
    @test bg.metadata["Channel"] == "Background"
end

@testset "keyword and copy constructors (2.0)" begin
    s = JASCOSpectrum(x=[1.0, 2.0], y=[0.1, 0.2])
    @test s.title == "Untitled"
    @test s.date === nothing
    @test s.spectrometer == ""
    @test s.datatype == ""
    @test s.xunits == ""
    @test s.yunits == ""
    @test isempty(s.metadata)

    # Copy constructor: override selected fields, share the rest
    s2 = JASCOSpectrum(s; yunits="ABSORBANCE", title="copy")
    @test s2.yunits == "ABSORBANCE"
    @test s2.title == "copy"
    @test s2.x === s.x
    @test s2.y === s.y
    @test s2.date === nothing

    # x/y length mismatch is rejected at construction
    @test_throws ArgumentError JASCOSpectrum(x=[1.0], y=[0.1, 0.2])
end

@testset "honest dates (2.0)" begin
    # Unparseable DATE/TIME → nothing, never a fabricated sentinel
    p = write_csv("TITLE,T\nDATE,InvalidDate\nTIME,InvalidTime\nXYDATA\n1,1\n2,2\n")
    @test JASCOSpectrum(p).date === nothing

    # Missing DATE/TIME → nothing
    p2 = write_csv("TITLE,T\nXYDATA\n1,1\n2,2\n")
    @test JASCOSpectrum(p2).date === nothing

    # Four-digit-year date variant parses
    p4 = write_csv("TITLE,T\nDATE,2024/11/05\nTIME,15:23:06\nXYDATA\n1,1\n2,2\n")
    @test JASCOSpectrum(p4).date == DateTime(2024, 11, 5, 15, 23, 6)

    # Binary: zeroed epoch field → nothing (make_jws leaves the epoch at 0)
    @test JASCOSpectrum(write_jws(make_jws())).date === nothing
end

@testset "legacy .jws (Spectra Manager 1.x, OLE container)" begin
    # %T file, 512-byte-sector CFB (v3). Real FT/IR-4600 measurement.
    t = JASCOSpectrum(joinpath(data_dir, "legacy_trans_512.jws"))
    @test t.yunits == "TRANSMITTANCE"
    @test t.datatype == "INFRARED SPECTRUM"
    @test t.xunits == "1/CM"
    @test t.spectrometer == "FT/IR-4600typeA"
    @test isftir(t)
    @test length(t.x) == 7573
    @test t.x[1] ≈ 499.4729 atol = 1e-3
    @test t.metadata["Format"] == "SPCMAN2 CFB"
    @test t.metadata["Serial Number"] == "E137161786"
    @test t.metadata["Accumulation"] == 16
    @test t.date isa DateTime    # stored UTC; CSV exports carry local time

    # Same format written with 4096-byte sectors (CFB v4)
    v4 = JASCOSpectrum(joinpath(data_dir, "legacy_trans_4096.jws"))
    @test v4.yunits == "TRANSMITTANCE"
    @test length(v4.x) == 7573

    # Absorbance file (y-mode 0x03)
    a = JASCOSpectrum(joinpath(data_dir, "legacy_abs_512.jws"))
    @test a.yunits == "ABSORBANCE"

    # Single-beam background (y-mode 0x08)
    bg = JASCOSpectrum(joinpath(data_dir, "legacy_bg_512.jws"))
    @test bg.yunits == "INTENSITY"
    @test bg.metadata["Channel"] == "Background"
    @test length(bg.x) == 12447

    # Unit-aware conversion works straight off a legacy %T file
    at = transmittance_to_absorbance(t)
    @test at.yunits == "ABSORBANCE"
end

@testset "legacy .jws Raman (NRS-5100, non-linear X-Data axis)" begin
    r = JASCOSpectrum(joinpath(data_dir, "legacy_raman.jws"))
    @test israman(r)
    @test r.datatype == "RAMAN SPECTRUM"
    @test r.yunits == "INTENSITY"
    @test r.xunits == "1/CM"
    @test r.spectrometer == "NRS-5100"
    @test length(r.x) == 1024
    @test issorted(r.x)
    @test r.date isa DateTime    # BaseInfo measurement date, UTC

    # The Raman MeasParam tag namespace differs from FTIR: tags stay raw
    # rather than being mislabeled with FTIR names.
    @test !haskey(r.metadata, "Accumulation")
    @test any(startswith("MeasParam.tag"), keys(r.metadata))

    # Ground truth: JASCO's own CSV export of the same measurement
    csv = JASCOSpectrum(joinpath(data_dir, "legacy_raman_pair.csv"))
    @test length(r.x) == length(csv.x)
    @test maximum(abs.(r.x .- csv.x)) < 1e-3      # export prints 4 decimals
    @test all(isapprox.(r.y, csv.y; atol=1e-2, rtol=1e-4))
    @test r.yunits == csv.yunits == "INTENSITY"
    @test r.datatype == csv.datatype == "RAMAN SPECTRUM"
end

@testset "legacy .jws vs CSV export ground truth" begin
    bin = JASCOSpectrum(joinpath(data_dir, "legacy_trans_512.jws"))
    csv = JASCOSpectrum(joinpath(data_dir, "legacy_trans_512_pair.csv"))

    @test length(bin.x) == length(csv.x)
    # The export prints x to 4 decimals and accumulates ~3.7e-3 rounding
    # drift over 7573 points; the binary grid is canonical.
    @test maximum(abs.(bin.x .- csv.x)) < 0.005
    # y values agree to the export's printed precision.
    @test all(isapprox.(bin.y, csv.y; atol=1e-6, rtol=1e-4))

    @test bin.yunits == csv.yunits == "TRANSMITTANCE"
    @test bin.datatype == csv.datatype == "INFRARED SPECTRUM"
    @test isftir(bin) == isftir(csv) == true
end

@testset "legacy .jws error paths" begin
    raw = read(joinpath(data_dir, "legacy_trans_512.jws"))

    # Corrupt magic: neither CFB nor "L~S " → routed to the modern reader,
    # which rejects it.
    bad = copy(raw)
    bad[1] = 0x00
    @test_throws "missing 'L~S '" JASCOSpectrum(write_jws(bad))

    # Truncated container
    @test_throws "truncated or corrupt CFB" JASCOSpectrum(write_jws(raw[1:1024]))

    # Required stream missing: rename "DataInfo" (UTF-16LE) in the directory
    nodata = copy(raw)
    pat = reinterpret(UInt8, Vector{UInt16}(codeunits("DataInfo") .|> UInt16))
    idx = findfirst(i -> nodata[i:i+length(pat)-1] == pat, 1:(length(nodata)-length(pat)+1))
    @test idx !== nothing
    nodata[idx] = UInt8('X')
    @test_throws "missing stream 'DataInfo'" JASCOSpectrum(write_jws(nodata))
end

@testset "Base.length/size removed (2.0)" begin
    # A spectrum is not a collection; use length(s.x). The Tables extension
    # is the supported tabular interface.
    @test !hasmethod(length, Tuple{JASCOSpectrum})
    @test !hasmethod(size, Tuple{JASCOSpectrum})
end
