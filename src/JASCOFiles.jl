module JASCOFiles

using Dates
using StringEncodings

include("types.jl")
include("parser.jl")
include("utils.jl")

export AbstractJASCOSpectrum, Spectrum, read_spectrum

end # module