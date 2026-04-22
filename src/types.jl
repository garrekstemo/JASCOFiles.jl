"""
    AbstractJASCOSpectrum

Abstract type for JASCO spectra.
"""
abstract type AbstractJASCOSpectrum end

"""
    JASCOSpectrum <: AbstractJASCOSpectrum

Represents a single spectrum parsed from a JASCO file.

# Fields
- `title::String`: Title of the measurement.
- `date::DateTime`: Date and time of the measurement.
- `spectrometer::String`: Name of the spectrometer instrument.
- `datatype::String`: Type of spectrum (e.g. "INFRARED SPECTRUM", "RAMAN SPECTRUM").
- `xunits::String`: Units for the x-axis (e.g. "cm-1").
- `yunits::String`: Units for the y-axis (e.g. "Abs").
- `x::Vector{Float64}`: X-axis data points.
- `y::Vector{Float64}`: Y-axis data points.
- `metadata::Dict{String, Any}`: Raw metadata dictionary from the file header.
"""
struct JASCOSpectrum <: AbstractJASCOSpectrum
    title::String
    date::DateTime
    spectrometer::String
    datatype::String
    xunits::String
    yunits::String
    x::Vector{Float64}
    y::Vector{Float64}
    metadata::Dict{String,Any}
end

function Base.show(io::IO, ::MIME"text/plain", s::JASCOSpectrum)
    println(io, "JASCOSpectrum: ", s.datatype)
    println(io, "  title:        ", repr(s.title))
    println(io, "  spectrometer: ", repr(s.spectrometer))
    println(io, "  date:         ", s.date)
    println(io, "  xunits:       ", s.xunits, "  (", length(s.x), " points)")
    println(io, "  yunits:       ", s.yunits)
    if !isempty(s.x)
        println(io, "  range:        ", s.x[1], " → ", s.x[end])
    end
    print(io, "  metadata:     ", length(s.metadata), " keys")
end

function Base.show(io::IO, s::JASCOSpectrum)
    print(io, "JASCOSpectrum(", repr(s.title), ", ", s.datatype, ", ",
          length(s.x), " points)")
end
