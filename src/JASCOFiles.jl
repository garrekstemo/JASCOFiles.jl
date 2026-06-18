"""
    JASCOFiles

Read JASCO spectrometer files into a concrete [`JASCOSpectrum`](@ref) struct:

- CSV/text exports (FTIR, Raman, UV-Vis; delimiter auto-detected, SHIFT-JIS
  by default)
- modern binary `.jws` (SPECMAN) / `.jrs` (SPECIRM) files (FTIR, UV-Vis)
- legacy binary `.jws` files from Spectra Manager 1.x (OLE2 container;
  FTIR and Raman) — the two binary generations share the extension and are
  distinguished by their magic bytes

Call [`JASCOSpectrum`](@ref)`(path)` to read any of them, then access `.x`,
`.y`, `.xunits`, `.yunits`, `.datatype`, and `.metadata` on the result. Use
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
include("legacy.jl")
include("utils.jl")

export AbstractJASCOSpectrum, JASCOSpectrum
export isftir, israman, isuvvis

end # module
