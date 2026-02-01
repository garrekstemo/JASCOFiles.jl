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

Return `true` if the spectrum is a UV-Vis spectrum.
"""
isuvvis(s::AbstractJASCOSpectrum) = s.datatype == "UV/VIS SPECTRUM"
