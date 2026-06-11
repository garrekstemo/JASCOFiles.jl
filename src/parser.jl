function JASCOSpectrum(path::AbstractString; encoding=enc"SHIFT-JIS", translate::Bool=true)
    ext = lowercase(splitext(path)[2])
    if ext == ".jws" || ext == ".jrs"
        # Two unrelated on-disk formats share the .jws extension: the legacy
        # Spectra Manager 1.x OLE2 container and the modern "L~S " flat
        # binary. Dispatch on the magic bytes, not the extension.
        magic = open(io -> read(io, 8), path)
        if magic == CFB_MAGIC
            return _read_legacy_jws(path)
        end
        return _read_jws(path; encoding=encoding)
    end
    return _read_jasco_csv(path; encoding=encoding, translate=translate)
end

# Parse JASCO's DATE + TIME header strings into a DateTime, or nothing.
# Exports usually write two-digit years (yy/mm/dd); some variants write
# four-digit years. The year sanity gate rejects accidental matches from
# the greedy yyyy field (e.g. "20" * "2024/11/05" parsing as year 202024).
function _parse_jasco_datetime(d_str::AbstractString, t_str::AbstractString)
    fmt = dateformat"yyyy/mm/ddTHH:MM:SS"
    for cand in ("20" * d_str, d_str)
        dt = tryparse(DateTime, cand * "T" * t_str, fmt)
        dt !== nothing && 1980 <= Dates.year(dt) <= 2100 && return dt
    end
    return nothing
end

function _read_jasco_csv(path::AbstractString; encoding=enc"SHIFT-JIS", translate::Bool=true)
    raw_metadata = Dict{String,Any}()
    xdata, ydata = Float64[], Float64[]
    is_data_section = false
    in_footer = false
    delim = ','
    delim_detected = false
    npoints_declared = nothing
    fname = basename(path)

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

            # Some exports omit the blank line between data and footer: once
            # the declared point count is reached, remaining lines are footer.
            if is_data_section && !in_footer && npoints_declared !== nothing &&
                    length(xdata) == npoints_declared
                in_footer = true
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
                # Data rows must be two parseable numbers. Anything else is
                # corruption: fail loudly rather than silently dropping rows.
                x_val = length(parts) >= 2 ? tryparse(Float64, strip(parts[1])) : nothing
                y_val = length(parts) >= 2 ? tryparse(Float64, strip(parts[2])) : nothing
                if x_val === nothing || y_val === nothing
                    throw(ArgumentError("$fname: unparseable data row: $(repr(String(stripped)))"))
                end
                push!(xdata, x_val)
                push!(ydata, y_val)
            else
                if length(parts) >= 2
                    key = strip(parts[1])
                    value = strip(join(parts[2:end], delim))
                    raw_metadata[key] = value
                    if key == "NPOINTS"
                        npoints_declared = tryparse(Int, value)
                    end
                end
            end
        end
    end

    # Mapping. Prefer the descriptive header field when non-empty; only fall
    # back to the footer's "機種名" (model name) when the header field is
    # missing or empty.
    header_spec = get(raw_metadata, "SPECTROMETER/DATA SYSTEM", "")
    spec_name = isempty(header_spec) ? get(raw_metadata, "機種名", "") : header_spec

    dt = nothing
    if haskey(raw_metadata, "DATE") && haskey(raw_metadata, "TIME")
        dt = _parse_jasco_datetime(string(raw_metadata["DATE"]),
                                   string(raw_metadata["TIME"]))
    end

    # Fail fast on structurally invalid input rather than returning an
    # empty/defaulted spectrum. Each message names the file so callers
    # iterating over many files learn which one is bad.
    if !is_data_section
        throw(ArgumentError("$fname: no XYDATA section found; file does not appear to be a JASCO spectrum"))
    end
    # Defensive: cannot occur today (x and y are pushed as a pair above),
    # but guards against future parser changes that add partial-push paths.
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
    if haskey(raw_metadata, "FIRSTX")
        declared_x = tryparse(Float64, strip(string(raw_metadata["FIRSTX"])))
        if declared_x !== nothing
            # Tolerance: one grid step (headers round FIRSTX), with a relative
            # floor for stepless files.
            step = tryparse(Float64, strip(string(get(raw_metadata, "DELTAX", ""))))
            tol = max(step === nothing ? 0.0 : abs(step),
                      1e-6 * abs(declared_x), 1e-9)
            if abs(declared_x - xdata[1]) > tol
                throw(ArgumentError("$fname: header declares FIRSTX=$declared_x but data starts at $(xdata[1])"))
            end
        end
    end

    return JASCOSpectrum(
        get(raw_metadata, "TITLE", "Untitled"),
        dt,
        spec_name,
        get(raw_metadata, "DATA TYPE", ""),
        get(raw_metadata, "XUNITS", ""),
        get(raw_metadata, "YUNITS", ""),
        xdata,
        ydata,
        raw_metadata
    )
end
