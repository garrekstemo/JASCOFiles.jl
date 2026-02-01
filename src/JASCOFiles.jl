module JASCOFiles

using Dates
using StringEncodings

include("types.jl")
include("parser.jl")
include("utils.jl")

export AbstractJASCOSpectrum, JASCOSpectrum, read_spectrum
export isftir, israman, isuvvis

end # module