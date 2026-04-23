"""
    JASCOFiles

Read CSV files exported from JASCO spectrometers (FTIR, Raman, UV-Vis) into a
concrete [`JASCOSpectrum`](@ref) struct. The parser auto-detects the delimiter
(comma for FTIR/Raman, tab for V-series UV-Vis) and decodes SHIFT-JIS metadata
by default.

Call [`JASCOSpectrum`](@ref)`(path)` to read a file, then access `.x`, `.y`,
`.xunits`, `.yunits`, `.datatype`, and `.metadata` on the result. Use
[`isftir`](@ref), [`israman`](@ref), or [`isuvvis`](@ref) to dispatch on
instrument type.
"""
module JASCOFiles

using Dates
using StringEncodings

include("types.jl")
include("parser.jl")
include("utils.jl")
include("transforms.jl")

export AbstractJASCOSpectrum, JASCOSpectrum
export isftir, israman, isuvvis
export transmittance_to_absorbance, absorbance_to_transmittance

end # module