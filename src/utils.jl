import Base: size, length

Base.length(s::AbstractJASCOSpectrum) = length(s.x)
Base.size(s::AbstractJASCOSpectrum) = (length(s.x),)
