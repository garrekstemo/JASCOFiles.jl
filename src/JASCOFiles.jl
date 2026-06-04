"""
    JASCOFiles

Read JASCO spectrometer files into a concrete [`JASCOSpectrum`](@ref) struct:
the CSV/text exports (FTIR, Raman, UV-Vis; delimiter auto-detected, SHIFT-JIS
by default) and the native binary `.jws` (SPECMAN) and `.jrs` (SPECIRM) files
for FTIR and UV-Vis. `JASCOSpectrum(path)` dispatches on the file extension.

Call [`JASCOSpectrum`](@ref)`(path)` to read a file, then access `.x`, `.y`,
`.xunits`, `.yunits`, `.datatype`, and `.metadata` on the result. Use
[`isftir`](@ref), [`israman`](@ref), or [`isuvvis`](@ref) to dispatch on
instrument type.
"""
module JASCOFiles

using Dates
using StringEncodings

include("types.jl")
include("translations.jl")
include("parser.jl")
include("binary.jl")
include("utils.jl")
include("transforms.jl")
include("plotting.jl")

export AbstractJASCOSpectrum, JASCOSpectrum
export isftir, israman, isuvvis
export transmittance_to_absorbance, absorbance_to_transmittance
export xlabel, ylabel

end # module