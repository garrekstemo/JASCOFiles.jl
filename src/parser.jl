function JASCOSpectrum(path::AbstractString; encoding=enc"SHIFT-JIS", translate::Bool=true)
    raw_metadata = Dict{String,Any}()
    xdata, ydata = Float64[], Float64[]
    is_data_section = false
    in_footer = false
    delim = ','
    delim_detected = false

    # Using the standard StringEncodings block pattern
    open(path, encoding) do f
        for raw_line in eachline(f)
            stripped = strip(raw_line)

            # A blank line after data has started flips us into footer mode;
            # before data starts (or once already in footer), blanks are skipped.
            if isempty(stripped)
                if is_data_section && !in_footer
                    in_footer = true
                end
                continue
            end

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

            if stripped == "XYDATA"
                is_data_section = true
                continue
            end

            parts = split(raw_line, delim)

            if in_footer
                # Section markers like "[測定情報]" and the FTIR/Raman
                # "##### Extended Information" decoration are not stored.
                startswith(stripped, '[') && continue
                stripped == "##### Extended Information" && continue

                length(parts) >= 1 || continue
                key = strip(parts[1])
                isempty(key) && continue
                value = length(parts) >= 2 ? strip(join(parts[2:end], delim)) : ""

                if translate
                    translated_value = get(JAPANESE_VALUE_TRANSLATIONS, value, value)
                    raw_metadata[key] = translated_value
                    if haskey(JAPANESE_KEY_TRANSLATIONS, key)
                        raw_metadata[JAPANESE_KEY_TRANSLATIONS[key]] = translated_value
                    end
                else
                    raw_metadata[key] = value
                end
            elseif is_data_section
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

    # Mapping. Prefer the descriptive header field when non-empty; only fall
    # back to the footer's "機種名" (model name) when the header field is
    # missing or empty.
    header_spec = get(raw_metadata, "SPECTROMETER/DATA SYSTEM", "")
    spec_name = isempty(header_spec) ? get(raw_metadata, "機種名", "Unknown") : header_spec

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

    # Fail fast on structurally invalid input rather than returning an
    # empty/defaulted spectrum. Each message names the file so callers
    # iterating over many files learn which one is bad.
    fname = basename(path)
    if !is_data_section
        throw(ArgumentError("$fname: no XYDATA section found; file does not appear to be a JASCO spectrum"))
    end
    if length(xdata) != length(ydata)
        throw(ArgumentError("$fname: parsed $(length(xdata)) x-values but $(length(ydata)) y-values"))
    end
    if isempty(xdata)
        throw(ArgumentError("$fname: XYDATA section contains no parseable data points"))
    end
    if haskey(raw_metadata, "NPOINTS")
        declared = tryparse(Int, strip(string(raw_metadata["NPOINTS"])))
        if declared !== nothing && declared != length(xdata)
            throw(ArgumentError("$fname: header declares NPOINTS=$declared but found $(length(xdata)) data points"))
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
