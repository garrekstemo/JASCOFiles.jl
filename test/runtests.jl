using Test
using JASCOFiles
using Dates
using Aqua
using StringEncodings

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