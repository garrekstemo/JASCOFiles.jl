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
- `date::Union{DateTime, Nothing}`: Date and time of the measurement, or
  `nothing` when the file carries no parseable timestamp.
- `spectrometer::String`: Name of the spectrometer instrument (`""` if absent).
- `datatype::String`: Type of spectrum (e.g. "INFRARED SPECTRUM", "RAMAN SPECTRUM").
- `xunits::String`: Units for the x-axis (e.g. "1/CM").
- `yunits::String`: Units for the y-axis (e.g. "ABSORBANCE", "TRANSMITTANCE").
- `x::Vector{Float64}`: X-axis data points.
- `y::Vector{Float64}`: Y-axis data points.
- `metadata::Dict{String, Any}`: Raw metadata dictionary from the file header.

# Constructors

    JASCOSpectrum(path; encoding=enc"SHIFT-JIS", translate=true)
    JASCOSpectrum(; x, y, title="Untitled", date=nothing, spectrometer="",
                  datatype="", xunits="", yunits="", metadata=Dict{String,Any}())
    JASCOSpectrum(s::JASCOSpectrum; fields...)

The path constructor parses a JASCO file (CSV/text export or native binary).
The keyword constructor builds a spectrum directly; only `x` and `y` are
required. The copy constructor returns a copy of `s` with any subset of
fields replaced, sharing the rest:

    a = JASCOSpectrum(s; yunits="ABSORBANCE", y=-log10.(s.y ./ 100))

`x` and `y` must have equal length.
"""
struct JASCOSpectrum <: AbstractJASCOSpectrum
    title::String
    date::Union{DateTime, Nothing}
    spectrometer::String
    datatype::String
    xunits::String
    yunits::String
    x::Vector{Float64}
    y::Vector{Float64}
    metadata::Dict{String,Any}

    function JASCOSpectrum(title, date, spectrometer, datatype, xunits, yunits,
                           x, y, metadata)
        length(x) == length(y) || throw(ArgumentError(
            "x and y must have the same length (got $(length(x)) and $(length(y)))"))
        return new(title, date, spectrometer, datatype, xunits, yunits,
                   x, y, metadata)
    end
end

function JASCOSpectrum(; x, y, title="Untitled", date=nothing, spectrometer="",
                       datatype="", xunits="", yunits="",
                       metadata=Dict{String,Any}())
    return JASCOSpectrum(title, date, spectrometer, datatype, xunits, yunits,
                         x, y, metadata)
end

function JASCOSpectrum(s::JASCOSpectrum; title=s.title, date=s.date,
                       spectrometer=s.spectrometer, datatype=s.datatype,
                       xunits=s.xunits, yunits=s.yunits, x=s.x, y=s.y,
                       metadata=s.metadata)
    return JASCOSpectrum(title, date, spectrometer, datatype, xunits, yunits,
                         x, y, metadata)
end

function Base.show(io::IO, ::MIME"text/plain", s::JASCOSpectrum)
    println(io, "JASCOSpectrum: ", s.datatype)
    println(io, "  title:        ", repr(s.title))
    println(io, "  spectrometer: ", repr(s.spectrometer))
    println(io, "  date:         ", something(s.date, "unknown"))
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
