"""
    transmittance_to_absorbance(spec::JASCOSpectrum; percent=true)

Convert a `JASCOSpectrum` from transmittance to absorbance using `A = -log10(T)`.

JASCO instruments record percent transmittance (0–100) by default. Set
`percent=false` if the y-data is already fractional transmittance (0–1).

Returns a new `JASCOSpectrum` with the y-axis converted to absorbance and
`yunits` set to `"ABS"`.

!!! warning "Default differs from OpticalSpectroscopy.jl"
    JASCOFiles defaults to `percent=true` (JASCO %T convention) — the
    OPPOSITE of `OpticalSpectroscopy.transmittance_to_absorbance`, which
    defaults to `percent=false` (fractional transmittance). Relying on the
    implicit default emits a one-time warning, and the default will flip to
    `percent=false` in JASCOFiles 2.0. Always pass `percent` explicitly.
"""
function transmittance_to_absorbance(spec::JASCOSpectrum; percent::Union{Bool,Nothing}=nothing)
    if percent === nothing
        @warn "transmittance_to_absorbance(::JASCOSpectrum) called without an explicit " *
              "`percent` keyword. JASCOFiles currently defaults to percent=true (JASCO %T " *
              "convention) — the OPPOSITE of OpticalSpectroscopy.jl, which defaults to " *
              "percent=false. The implicit default will flip to percent=false in " *
              "JASCOFiles 2.0; pass `percent` explicitly to silence this warning." maxlog=1
        percent = true
    end
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

!!! warning "Default differs from OpticalSpectroscopy.jl"
    JASCOFiles defaults to `percent=true` (JASCO %T convention) — the
    OPPOSITE of `OpticalSpectroscopy.absorbance_to_transmittance`, which
    defaults to `percent=false` (fractional transmittance). Relying on the
    implicit default emits a one-time warning, and the default will flip to
    `percent=false` in JASCOFiles 2.0. Always pass `percent` explicitly.
"""
function absorbance_to_transmittance(spec::JASCOSpectrum; percent::Union{Bool,Nothing}=nothing)
    if percent === nothing
        @warn "absorbance_to_transmittance(::JASCOSpectrum) called without an explicit " *
              "`percent` keyword. JASCOFiles currently defaults to percent=true (JASCO %T " *
              "convention) — the OPPOSITE of OpticalSpectroscopy.jl, which defaults to " *
              "percent=false. The implicit default will flip to percent=false in " *
              "JASCOFiles 2.0; pass `percent` explicitly to silence this warning." maxlog=1
        percent = true
    end
    T_frac = 10 .^ (-spec.y)
    new_y = percent ? T_frac .* 100 : T_frac
    yunits = percent ? "TRANSMITTANCE" : "TRANSMITTANCE_FRAC"
    return JASCOSpectrum(spec.title, spec.date, spec.spectrometer, spec.datatype,
                         spec.xunits, yunits, spec.x, new_y, spec.metadata)
end
