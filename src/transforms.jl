"""
    transmittance_to_absorbance(spec::JASCOSpectrum; percent=nothing)

Convert a `JASCOSpectrum` from transmittance to absorbance using `A = -log10(T)`.

The transmittance scale is inferred from `spec.yunits`:

- `"TRANSMITTANCE"` (what JASCO instruments write; %T) → values are 0–100
- `"TRANSMITTANCE_FRAC"` → values are fractional, 0–1

Pass `percent=true`/`percent=false` to override the inference; an explicit
`percent` is required when `yunits` is anything else.

Nonpositive transmittance values (saturated bands, detector noise) have no
absorbance: they map to `NaN`, with a warning reporting how many were
affected.

Returns a new `JASCOSpectrum` with `yunits = "ABSORBANCE"` (the same string
JASCO instruments write), sharing `x` and `metadata` with the input.
"""
function transmittance_to_absorbance(spec::JASCOSpectrum;
                                     percent::Union{Bool,Nothing}=nothing)
    if percent === nothing
        u = uppercase(spec.yunits)
        if u == "TRANSMITTANCE"
            percent = true
        elseif u == "TRANSMITTANCE_FRAC"
            percent = false
        else
            throw(ArgumentError(
                "cannot infer the transmittance scale from yunits = $(repr(spec.yunits)); " *
                "expected \"TRANSMITTANCE\" (percent) or \"TRANSMITTANCE_FRAC\" (fractional). " *
                "If the y-data really is transmittance, pass percent=true (0–100) or " *
                "percent=false (0–1) explicitly."))
        end
    end
    T_frac = percent ? spec.y ./ 100 : spec.y
    nbad = count(t -> t <= 0, T_frac)
    if nbad > 0
        @warn "$(nbad) nonpositive transmittance value(s) mapped to NaN absorbance " *
              "(saturated or noise-dominated points have no defined absorbance)"
    end
    new_y = [t > 0 ? -log10(t) : NaN for t in T_frac]
    return JASCOSpectrum(spec; y=new_y, yunits="ABSORBANCE")
end

"""
    absorbance_to_transmittance(spec::JASCOSpectrum; percent)

Convert a `JASCOSpectrum` from absorbance to transmittance using `T = 10^(-A)`.

`percent` is a required keyword and records the output scale in `yunits`:

- `percent=true` → percent transmittance, 0–100, `yunits = "TRANSMITTANCE"`
  (JASCO's convention)
- `percent=false` → fractional transmittance, 0–1, `yunits = "TRANSMITTANCE_FRAC"`

Throws if the input is already transmittance. Returns a new `JASCOSpectrum`
sharing `x` and `metadata` with the input.
"""
function absorbance_to_transmittance(spec::JASCOSpectrum; percent::Bool)
    u = uppercase(spec.yunits)
    if u == "TRANSMITTANCE" || u == "TRANSMITTANCE_FRAC"
        throw(ArgumentError(
            "spectrum is already transmittance (yunits = $(repr(spec.yunits)))"))
    end
    T_frac = 10 .^ (-spec.y)
    new_y = percent ? T_frac .* 100 : T_frac
    yunits = percent ? "TRANSMITTANCE" : "TRANSMITTANCE_FRAC"
    return JASCOSpectrum(spec; y=new_y, yunits=yunits)
end
