using Test
using JASCOFiles
using Dates

data_dir = joinpath(@__DIR__, "data")
spectrum_file = joinpath(data_dir, "ftir_test.csv")

@testset "read JASCO FTIR csv file" begin
    s = Spectrum(spectrum_file)

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

    @test year(s.date) >= 2000
end

@testset "FTIR edge cases" begin
    malformed_file = joinpath(data_dir, "ftir_malformed.csv")
    s = read_spectrum(malformed_file) # Test alias here

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
    s = Spectrum(raman_file)

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

    @test year(s.date) >= 2000
end

@testset "Raman edge cases" begin
    malformed_file = joinpath(data_dir, "raman_malformed.csv")
    s = Spectrum(malformed_file)

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

@testset "type predicates" begin
    ftir = Spectrum(joinpath(data_dir, "ftir_test.csv"))
    raman = Spectrum(joinpath(data_dir, "raman_test.csv"))

    @test isftir(ftir)
    @test !israman(ftir)
    @test !isuvvis(ftir)

    @test !isftir(raman)
    @test israman(raman)
    @test !isuvvis(raman)
end