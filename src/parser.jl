function JASCOSpectrum(path::AbstractString; encoding=enc"SHIFT-JIS")
    raw_metadata = Dict{String,Any}()
    xdata, ydata = Float64[], Float64[]
    is_data_section = false
    delim = ','
    delim_detected = false

    # Using the standard StringEncodings block pattern
    open(path, encoding) do f
        for raw_line in eachline(f)
            isempty(strip(raw_line)) && continue

            # JASCO FTIR/Raman files use commas; V-series UV-Vis uses tabs.
            # Detect on the raw line so trailing delimiters (e.g. empty-value
            # header rows like "TITLE\t") aren't lost to stripping.
            if !delim_detected
                if occursin('\t', raw_line)
                    delim = '\t'
                    delim_detected = true
                elseif occursin(',', raw_line)
                    delim = ','
                    delim_detected = true
                end
            end

            if strip(raw_line) == "XYDATA"
                is_data_section = true
                continue
            end

            parts = split(raw_line, delim)
            if is_data_section
                if length(parts) >= 2
                    try
                        x_val = parse(Float64, strip(parts[1]))
                        y_val = parse(Float64, strip(parts[2]))
                        push!(xdata, x_val)
                        push!(ydata, y_val)
                    catch e
                        e isa ArgumentError || rethrow()
                    end
                end
            else
                if length(parts) >= 2
                    raw_metadata[strip(parts[1])] = strip(join(parts[2:end], delim))
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

    return JASCOSpectrum(
        get(raw_metadata, "TITLE", "Untitled"),
        dt,
        spec_name,
        get(raw_metadata, "DATA TYPE", "Unknown"),
        get(raw_metadata, "XUNITS", "cm-1"),
        get(raw_metadata, "YUNITS", "Abs"),
        xdata,
        ydata,
        raw_metadata
    )
end
