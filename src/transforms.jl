"""
    transmittance_to_absorbance(spec::JASCOSpectrum; percent=true)

Convert a `JASCOSpectrum` from transmittance to absorbance using `A = -log10(T)`.

JASCO instruments record percent transmittance (0–100) by default. Set
`percent=false` if the y-data is already fractional transmittance (0–1).

Returns a new `JASCOSpectrum` with the y-axis converted to absorbance and
`yunits` set to `"ABS"`.
"""
function transmittance_to_absorbance(spec::JASCOSpectrum; percent::Bool=true)
    T_frac = percent ? spec.y ./ 100 : spec.y
    new_y = -log10.(T_frac)
    return JASCOSpectrum(spec.title, spec.date, spec.spectrometer, spec.datatype,
                         spec.xunits, "ABS", spec.x, new_y, spec.metadata)
end

"""
    absorbance_to_transmittance(spec::JASCOSpectrum; percent=true)

Convert a `JASCOSpectrum` from absorbance to transmittance using `T = 10^(-A)`.

Returns a new `JASCOSpectrum` with the y-axis converted to transmittance.
Defaults to percent transmittance (`percent=true`, `yunits="TRANSMITTANCE"`);
pass `percent=false` for fractional transmittance (`yunits="TRANSMITTANCE_FRAC"`).
"""
function absorbance_to_transmittance(spec::JASCOSpectrum; percent::Bool=true)
    T_frac = 10 .^ (-spec.y)
    new_y = percent ? T_frac .* 100 : T_frac
    yunits = percent ? "TRANSMITTANCE" : "TRANSMITTANCE_FRAC"
    return JASCOSpectrum(spec.title, spec.date, spec.spectrometer, spec.datatype,
                         spec.xunits, yunits, spec.x, new_y, spec.metadata)
end
