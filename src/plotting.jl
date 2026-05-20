"""
    xlabel(s::AbstractJASCOSpectrum) -> String

Return a human-readable x-axis label for `s`.

Examples:
- FTIR with `1/CM`      → `"Wavenumber (cm⁻¹)"`
- Raman with `1/CM`     → `"Raman shift (cm⁻¹)"`
- UV-Vis with `NANOMETERS` → `"Wavelength (nm)"`

Units that aren't recognised fall back to a title-cased form of `s.xunits`.
"""
function xlabel(s::AbstractJASCOSpectrum)
    u = uppercase(s.xunits)
    if u in ("1/CM", "CM-1")
        israman(s) && return "Raman shift (cm⁻¹)"
        return "Wavenumber (cm⁻¹)"
    elseif u in ("NANOMETERS", "NM")
        return "Wavelength (nm)"
    else
        return titlecase(s.xunits)
    end
end

"""
    ylabel(s::AbstractJASCOSpectrum) -> String

Return a human-readable y-axis label for `s`.

Examples:
- `ABSORBANCE` / `Abs`  → `"Absorbance"`
- `INTENSITY`           → `"Intensity"`
- `TRANSMITTANCE`       → `"Transmittance (%)"`
- `TRANSMITTANCE_FRAC`  → `"Transmittance"`

Units that aren't recognised fall back to a title-cased form of `s.yunits`.
"""
function ylabel(s::AbstractJASCOSpectrum)
    u = uppercase(s.yunits)
    if u in ("ABSORBANCE", "ABS")
        return "Absorbance"
    elseif u == "INTENSITY"
        return "Intensity"
    elseif u == "TRANSMITTANCE"
        return "Transmittance (%)"
    elseif u == "TRANSMITTANCE_FRAC"
        return "Transmittance"
    else
        return titlecase(s.yunits)
    end
end

