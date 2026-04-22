import Base: size, length

Base.length(s::AbstractJASCOSpectrum) = length(s.x)
Base.size(s::AbstractJASCOSpectrum) = (length(s.x),)

"""
    isftir(s::AbstractJASCOSpectrum) -> Bool

Return `true` if the spectrum is an FTIR (infrared) spectrum.
"""
isftir(s::AbstractJASCOSpectrum) = s.datatype == "INFRARED SPECTRUM"

"""
    israman(s::AbstractJASCOSpectrum) -> Bool

Return `true` if the spectrum is a Raman spectrum.
"""
israman(s::AbstractJASCOSpectrum) = s.datatype == "RAMAN SPECTRUM"

"""
    isuvvis(s::AbstractJASCOSpectrum) -> Bool

Return `true` if the spectrum is a UV-Vis (or UV-Vis/NIR) spectrum.

Some JASCO instruments (e.g. the V-730) export files with a blank `DATA TYPE`
field. In that case, the spectrum is classified as UV-Vis when `xunits` is
`"NANOMETERS"` and the wavelength range falls within 100–3500 nm.
"""
function isuvvis(s::AbstractJASCOSpectrum)
    s.datatype == "UV/VIS SPECTRUM" && return true
    isempty(s.datatype) || return false
    s.xunits == "NANOMETERS" || return false
    isempty(s.x) && return false
    xmin, xmax = extrema(s.x)
    return 100 ≤ xmin && xmax ≤ 3500
end
