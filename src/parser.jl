function Spectrum(path::String; encoding=enc"SHIFT-JIS")
    raw_metadata = Dict{String,Any}()
    xdata, ydata = Float64[], Float64[]
    is_data_section = false

    # Using the standard StringEncodings block pattern
    open(path, encoding) do f
        for line in eachline(f)
            line = strip(line)
            if isempty(line)
                continue
            end

            if line == "XYDATA"
                is_data_section = true
                continue
            end

            if is_data_section
                parts = split(line, ",")
                if length(parts) >= 2
                    try
                        x_val = parse(Float64, parts[1])
                        y_val = parse(Float64, parts[2])
                        push!(xdata, x_val)
                        push!(ydata, y_val)
                    catch
                    end # Skip lines that aren't numeric
                end
            else
                parts = split(line, ",")
                if length(parts) >= 2
                    raw_metadata[strip(parts[1])] = strip(parts[2])
                end
            end
        end
    end

    # Mapping
    spec_name = get(raw_metadata, "機種名", get(raw_metadata, "SPECTROMETER/DATA SYSTEM", "Unknown"))

    dt = DateTime(2000)
    if haskey(raw_metadata, "DATE") && haskey(raw_metadata, "TIME")
        try
            d_str = raw_metadata["DATE"]
            t_str = raw_metadata["TIME"]
            # JASCO often uses yy/mm/dd; this prepends '20' for the century
            dt = DateTime("20" * d_str * "T" * t_str, dateformat"yy/mm/ddTHH:MM:SS")
        catch
        end
    end

    return Spectrum(
        get(raw_metadata, "TITLE", "Untitled"),
        dt,
        spec_name,
        get(raw_metadata, "XUNITS", "cm-1"),
        get(raw_metadata, "YUNITS", "Abs"),
        xdata,
        ydata,
        raw_metadata
    )
end

# Alias for convenience
"""
    read_spectrum(path::String; kwargs...)

Convenience alias for `Spectrum(path; kwargs...)`. Reads a JASCO spectrum file.
"""
read_spectrum(path; kwargs...) = Spectrum(path; kwargs...)
