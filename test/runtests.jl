using Test
using JASCOFiles
using Dates
using Aqua
using StringEncodings
using Makie
using Tables

data_dir = joinpath(@__DIR__, "data")
spectrum_file = joinpath(data_dir, "ftir_test.csv")

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

    @test length(s) == 12447
    @test size(s) == (12447,)

    # Test Metadata Extraction
    @test s.metadata["XUNITS"] == "1/CM"
    @test s.metadata["YUNITS"] == "ABSORBANCE"
    @test s.datatype == "INFRARED SPECTRUM"

    @test s.date == DateTime(2023, 1, 11, 16, 49, 31)
end

@testset "FTIR edge cases" begin
    malformed_file = joinpath(data_dir, "ftir_malformed.csv")
    s = JASCOSpectrum(malformed_file)

    # Test defaults for missing/invalid metadata
    @test s.title == "Malformed Data Test"
    @test s.spectrometer == "Unknown"
    @test s.datatype == "Unknown"  # No DATA TYPE in malformed file
    @test s.xunits == "cm-1" # Default
    @test s.yunits == "Abs"  # Default
    @test s.date == DateTime(2000) # Default failure fallback

    # Test skipping of invalid data lines
    # valid lines: (1000.0, 0.1), (2000.0, 0.2), (4000.0, 0.4)
    # GARBAGE_LINE should be skipped
    # 3000.0,NoteANumber should be skipped (parse error)
    @test length(s.x) == 3
    @test length(s.y) == 3
    @test s.x == [1000.0, 2000.0, 4000.0]
    @test s.y == [0.1, 0.2, 0.4]
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

    @test length(s) == 1024
    @test size(s) == (1024,)

    @test s.date == DateTime(2024, 11, 5, 15, 23, 6)
end

@testset "Raman edge cases" begin
    malformed_file = joinpath(data_dir, "raman_malformed.csv")
    s = JASCOSpectrum(malformed_file)

    @test s.title == "Malformed Raman Test"
    @test s.datatype == "RAMAN SPECTRUM"

    # Test skipping of invalid data lines
    # valid lines: (500.0, 100), (700.0, 150), (800.0, 200)
    # 600.0,NotANumber should be skipped (parse error)
    # GARBAGE_LINE should be skipped
    @test length(s.x) == 3
    @test length(s.y) == 3
    @test s.x == [500.0, 700.0, 800.0]
    @test s.y == [100.0, 150.0, 200.0]
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
    @test length(s) == 1001
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

    # Empty-spectrum path: no "range:" line
    empty_s = JASCOSpectrum("", DateTime(2000), "", "UNKNOWN",
                            "", "", Float64[], Float64[], Dict{String,Any}())
    empty_out = sprint(show, MIME("text/plain"), empty_s)
    @test !occursin("range:", empty_out)
    @test occursin("0 points", empty_out)
end

@testset "error paths" begin
    @test_throws SystemError JASCOSpectrum("this_file_does_not_exist.csv")
    @test JASCOSpectrum <: AbstractJASCOSpectrum
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

@testset "transmittance ↔ absorbance" begin
    s = JASCOSpectrum(joinpath(data_dir, "ftir_test.csv"))  # ABSORBANCE

    # Percent round-trip from absorbance and back
    t = absorbance_to_transmittance(s)
    @test t.yunits == "TRANSMITTANCE"
    @test t.x === s.x
    @test t.metadata === s.metadata
    @test t.title == s.title
    a = transmittance_to_absorbance(t)
    @test a.yunits == "ABS"
    @test a.y ≈ s.y atol=1e-12

    # Fractional round-trip
    tf = absorbance_to_transmittance(s; percent=false)
    @test tf.yunits == "TRANSMITTANCE_FRAC"
    af = transmittance_to_absorbance(tf; percent=false)
    @test af.yunits == "ABS"
    @test af.y ≈ s.y atol=1e-12

    # Known landmark: T=10% → A=1, T=1% → A=2
    landmark = JASCOSpectrum("t", DateTime(2024), "test", "UV/VIS SPECTRUM",
                             "NANOMETERS", "TRANSMITTANCE",
                             [500.0, 600.0], [10.0, 1.0], Dict{String,Any}())
    @test transmittance_to_absorbance(landmark).y ≈ [1.0, 2.0]

    # Fractional landmark: T=0.5 → A ≈ 0.30103
    landmark_frac = JASCOSpectrum("t", DateTime(2024), "test", "UV/VIS SPECTRUM",
                                  "NANOMETERS", "TRANSMITTANCE_FRAC",
                                  [500.0], [0.5], Dict{String,Any}())
    @test transmittance_to_absorbance(landmark_frac; percent=false).y ≈ [-log10(0.5)]
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
    t = absorbance_to_transmittance(ftir)
    @test ylabel(t) == "Transmittance (%)"
    tf = absorbance_to_transmittance(ftir; percent=false)
    @test ylabel(tf) == "Transmittance"

    # Default-fallback file has xunits="cm-1", yunits="Abs"
    malformed = JASCOSpectrum(joinpath(data_dir, "ftir_malformed.csv"))
    @test xlabel(malformed) == "Wavenumber (cm⁻¹)"
    @test ylabel(malformed) == "Absorbance"

    # Unknown units fall back to title-casing the raw value
    weird = JASCOSpectrum("x", DateTime(2000), "spec", "INFRARED SPECTRUM",
                         "kelvin", "candelas", Float64[], Float64[], Dict{String,Any}())
    @test xlabel(weird) == "Kelvin"
    @test ylabel(weird) == "Candelas"
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
    @test length(rows) == length(s)
    @test Tables.getcolumn(rows[1], :x) == s.x[1]
    @test Tables.getcolumn(rows[1], :y) == s.y[1]
end