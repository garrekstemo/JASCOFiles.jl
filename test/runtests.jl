using Test
using JASCOFiles
using Dates

data_dir = joinpath(@__DIR__, "data")
spectrum_file = joinpath(data_dir, "testdata.csv")

@testset "read JASCO FTIR csv file" begin
    # 1. Test the Constructor
    s = Spectrum(spectrum_file)

    # Check first and last X values (Wavenumbers)
    @test s.x[1] == 999.9101
    @test round(s.x[end], sigdigits=8) == 7000.335

    # Check first Y value (Absorbance)
    @test round(s.y[1], sigdigits=3) ≈ 0.573

    @test length(s) == 12447
    @test size(s) == (12447,)

    # 4. Test Metadata Extraction
    @test s.metadata["XUNITS"] == "1/CM"
    @test s.metadata["YUNITS"] == "ABSORBANCE"

    @test year(s.date) >= 2000
end

@testset "Edge Cases and Error Handling" begin
    malformed_file = joinpath(data_dir, "malformed.csv")
    s = read_spectrum(malformed_file) # Test alias here

    # Test defaults for missing/invalid metadata
    @test s.title == "Malformed Data Test"
    @test s.spectrometer == "Unknown"
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