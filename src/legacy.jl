# Reader for LEGACY JASCO .jws files (Spectra Manager 1.x era). These are
# OLE2/CFB compound documents (magic D0 CF 11 E0, the same container as old
# .doc/.xls) holding named streams; the internal format id is "SPCMAN2".
# Reverse-engineered and validated against a 385-file FT/IR-4600 corpus with
# 184 paired CSV-export ground truths (100% y-value agreement); see
# docs/superpowers/specs/2026-06-11-legacy-jws-ole-reader-design.md.
#
# Layout facts that differ from the modern "L~S " flat format:
#   - Strings are UInt32-length-prefixed UTF-16LE (NOT Shift-JIS); the length
#     includes the 2-byte null terminator.
#   - Dates are OLE Automation doubles (days since 1899-12-30) stored in UTC;
#     36494.0 (= 1999-11-30) is JASCO's "no timestamp" sentinel.
#   - The y-mode code vocabulary is shared with the modern format
#     (YMODE_YUNITS in binary.jl).
#   - JASCO marks invalid points with -floatmin(Float32) (-1.18e-38); real
#     exports print these too, so they pass through unmodified.

const CFB_MAGIC = UInt8[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
const CFB_ENDOFCHAIN = 0xFFFFFFFE
const CFB_FREE_FLOOR = 0xFFFFFFFA   # sector numbers >= this are markers, not sectors

const OLE_EPOCH = DateTime(1899, 12, 30)
const OLE_NULL_DATE = 36494.0       # 1999-11-30: JASCO's "no timestamp" sentinel

# x-axis channel descriptor: [unit code][01 00 10 marker], the same
# unit-code + marker convention as the modern header (binary.jl).
# Unit code 0x00 = FTIR wavenumber (linear grid); 0x01 = Raman shift
# (non-linear CCD axis stored explicitly in an X-Data stream). Both map to
# the datatype/units vocabulary JASCO's own CSV exports use.
const LEGACY_XDESC_MARKER = 0x10000100
const LEGACY_XUNIT_KINDS = Dict{UInt8,String}(
    0x00 => "INFRARED SPECTRUM",
    0x01 => "RAMAN SPECTRUM",
)

# Legacy-only y-mode codes, extending the modern YMODE_YUNITS vocabulary.
const LEGACY_YMODE_EXTRA = Dict{UInt8,String}(
    0x0e => "INTENSITY",   # Raman CCD counts (NRS series; CSV-verified)
)

# FTIR module id in ModuleInfo. The MeasParam tag namespace is per module
# type (Raman NRS files reuse the same tag numbers with different meanings),
# so named tags below apply to FTIR modules only.
const LEGACY_MODULE_FTIR = 0x0009

# MeasParam TLV tags verified against paired FTIR CSV-export footers.
# Unlisted (or non-FTIR) tags are retained under "MeasParam.tag<N>".
const LEGACY_MEASPARAM_TAGS = Dict{Int,String}(
    1  => "Accumulation",
    2  => "Resolution",
    3  => "Aperture",
    4  => "Scan speed",
    6  => "Gain",
    12 => "Measurement date",
    13 => "Range start",
    14 => "Range end",
    21 => "Measured firstx",
    22 => "Measured lastx",
    23 => "Raw data interval",
    32 => "Filter",
    47 => "Light source",
    48 => "Detector",
)

struct CFBEntry
    name::String
    type::UInt8        # 1=storage, 2=stream, 5=root
    left::UInt32
    right::UInt32
    child::UInt32
    start::UInt32
    size::UInt64
end

struct CFBFile
    bytes::Vector{UInt8}
    fname::String
    sector_size::Int       # 512 (v3) or 4096 (v4); both occur in real corpora
    mini_sector_size::Int  # 64
    mini_cutoff::UInt32    # streams smaller than this live in the mini-stream
    fat::Vector{UInt32}
    minifat::Vector{UInt32}
    entries::Vector{CFBEntry}
    ministream::Vector{UInt8}
end

# Bounds-checked sector fetch: sector n starts at byte (n+1)*sector_size.
function _cfb_sector(bytes::Vector{UInt8}, s::Integer, sector_size::Int, fname::String)
    off = (Int(s) + 1) * sector_size
    off + 1 <= length(bytes) ||
        throw(ArgumentError("$fname: truncated or corrupt CFB container (sector $s out of range)"))
    return @view bytes[off+1:min(off + sector_size, length(bytes))]
end

# Follow a FAT chain into a byte vector.
function _cfb_chain(bytes, fat, start, sector_size, fname; maxlen=typemax(Int))
    out = UInt8[]
    s = start
    hops = 0
    while s != CFB_ENDOFCHAIN && s < CFB_FREE_FLOOR
        Int(s) + 1 <= length(fat) ||
            throw(ArgumentError("$fname: truncated or corrupt CFB container (FAT entry $s missing)"))
        append!(out, _cfb_sector(bytes, s, sector_size, fname))
        s = fat[Int(s)+1]
        (hops += 1) > 4_000_000 &&
            throw(ArgumentError("$fname: corrupt CFB container (FAT chain cycle)"))
        length(out) >= maxlen && break
    end
    return out
end

function CFBFile(path::AbstractString)
    bytes = read(path)
    fname = basename(path)
    length(bytes) >= 512 && bytes[1:8] == CFB_MAGIC ||
        throw(ArgumentError("$fname: not an OLE2/CFB file"))
    sector_size = 1 << read_le(UInt16, bytes, 0x1E)
    mini_size = 1 << read_le(UInt16, bytes, 0x20)
    dir_start = read_le(UInt32, bytes, 0x30)
    mini_cutoff = read_le(UInt32, bytes, 0x38)
    minifat_start = read_le(UInt32, bytes, 0x3C)
    num_minifat = read_le(UInt32, bytes, 0x40)
    difat_start = read_le(UInt32, bytes, 0x44)
    num_difat = read_le(UInt32, bytes, 0x48)

    # DIFAT: 109 entries in the header, then chained DIFAT sectors.
    difat = UInt32[]
    for i in 0:108
        v = read_le(UInt32, bytes, 0x4C + 4i)
        v < CFB_FREE_FLOOR && push!(difat, v)
    end
    s = difat_start
    hops = 0
    while s != CFB_ENDOFCHAIN && s < CFB_FREE_FLOOR && hops < num_difat
        sec = _cfb_sector(bytes, s, sector_size, fname)
        for i in 0:(sector_size ÷ 4 - 2)
            v = read_le(UInt32, Vector(sec), 4i)
            v < CFB_FREE_FLOOR && push!(difat, v)
        end
        s = read_le(UInt32, Vector(sec), sector_size - 4)
        hops += 1
    end

    fat = UInt32[]
    for fs in difat
        sec = Vector(_cfb_sector(bytes, fs, sector_size, fname))
        for i in 0:(sector_size ÷ 4 - 1)
            push!(fat, read_le(UInt32, sec, 4i))
        end
    end

    dirbytes = _cfb_chain(bytes, fat, dir_start, sector_size, fname)
    entries = CFBEntry[]
    for e in 0:(length(dirbytes) ÷ 128 - 1)
        raw = dirbytes[e*128+1:e*128+128]
        nlen = read_le(UInt16, raw, 0x40)   # bytes, including the null terminator
        name = nlen >= 2 ? transcode(String, Vector(reinterpret(UInt16, raw[1:nlen-2]))) : ""
        push!(entries, CFBEntry(name, raw[0x42+1],
            read_le(UInt32, raw, 0x44), read_le(UInt32, raw, 0x48), read_le(UInt32, raw, 0x4C),
            read_le(UInt32, raw, 0x74), UInt64(read_le(UInt32, raw, 0x78))))
    end

    minifat = UInt32[]
    if num_minifat > 0 && minifat_start < CFB_FREE_FLOOR
        mfb = _cfb_chain(bytes, fat, minifat_start, sector_size, fname)
        for i in 0:(length(mfb) ÷ 4 - 1)
            push!(minifat, read_le(UInt32, mfb, 4i))
        end
    end

    iroot = findfirst(e -> e.type == 0x05, entries)
    iroot === nothing && throw(ArgumentError("$fname: CFB container has no root entry"))
    root = entries[iroot]
    ministream = root.start < CFB_FREE_FLOOR ?
        _cfb_chain(bytes, fat, root.start, sector_size, fname; maxlen=Int(root.size)) : UInt8[]

    return CFBFile(bytes, fname, sector_size, mini_size, mini_cutoff,
                   fat, minifat, entries, ministream)
end

# Read a stream's bytes. Streams smaller than mini_cutoff live in the
# mini-stream (64-byte mini-sectors addressed by the mini-FAT).
function _cfb_stream(c::CFBFile, e::CFBEntry)
    sz = Int(e.size)
    if e.type == 0x02 && sz < c.mini_cutoff
        out = UInt8[]
        s = e.start
        hops = 0
        while s != CFB_ENDOFCHAIN && s < CFB_FREE_FLOOR
            Int(s) + 1 <= length(c.minifat) ||
                throw(ArgumentError("$(c.fname): truncated or corrupt CFB container (mini-FAT entry $s missing)"))
            off = Int(s) * c.mini_sector_size
            append!(out, @view c.ministream[off+1:min(off + c.mini_sector_size, length(c.ministream))])
            s = c.minifat[Int(s)+1]
            (hops += 1) > 4_000_000 &&
                throw(ArgumentError("$(c.fname): corrupt CFB container (mini-FAT chain cycle)"))
        end
        return out[1:min(sz, length(out))]
    end
    out = _cfb_chain(c.bytes, c.fat, e.start, c.sector_size, c.fname; maxlen=sz)
    return out[1:min(sz, length(out))]
end

# Walk the directory red-black trees into "path/to/stream" => entry. Names
# repeat across storages (e.g. BaseInfo at the root AND under MicroImages),
# so flat name lookup is not sufficient.
function _cfb_tree(c::CFBFile)
    paths = Dict{String,CFBEntry}()
    function walk(idx::UInt32, prefix::String)
        (idx == 0xFFFFFFFF || Int(idx) + 1 > length(c.entries)) && return
        e = c.entries[Int(idx)+1]
        e.type == 0x00 && return
        walk(e.left, prefix)
        p = isempty(prefix) ? e.name : prefix * "/" * e.name
        paths[p] = e
        e.child != 0xFFFFFFFF && walk(e.child, p)
        walk(e.right, prefix)
    end
    root = c.entries[findfirst(e -> e.type == 0x05, c.entries)]
    walk(root.child, "")
    return paths
end

# Length-prefixed UTF-16LE string at 0-based `off`. Length 0 = absent;
# length 2 = empty. Returns (string, next_offset).
function _jasco_string(b, off)
    len = Int(read_le(UInt32, b, off))
    s = ""
    if len >= 2
        u16 = Vector(reinterpret(UInt16, b[off+5:off+4+len]))
        n = length(u16)
        while n > 0 && u16[n] == 0x0000
            n -= 1
        end
        s = transcode(String, u16[1:n])
    end
    return (s, off + 4 + len)
end

# OLE Automation date (days since 1899-12-30, stored UTC) -> DateTime or nothing.
function _ole_date(d::Float64)
    (d == OLE_NULL_DATE || d <= 0.0 || !isfinite(d)) && return nothing
    return OLE_EPOCH + Millisecond(round(Int64, d * 86_400_000))
end

# TLV record list used by MeasParam and the SampleInfo tail:
# [UInt32 tag][UInt16 type][value]; type 2=UInt16, 3=UInt32, 4=Float32,
# 5=Float64, 8=length-prefixed string.
function _jasco_tlv(b, off, nrec, fname)
    recs = Pair{Int,Any}[]
    for _ in 1:nrec
        tag = Int(read_le(UInt32, b, off))
        typ = Int(read_le(UInt16, b, off + 4))
        off += 6
        if typ == 2
            push!(recs, tag => read_le(UInt16, b, off)); off += 2
        elseif typ == 3
            push!(recs, tag => read_le(UInt32, b, off)); off += 4
        elseif typ == 4
            push!(recs, tag => read_le(Float32, b, off)); off += 4
        elseif typ == 5
            push!(recs, tag => read_le(Float64, b, off)); off += 8
        elseif typ == 8
            (s, off) = _jasco_string(b, off)
            push!(recs, tag => s)
        else
            throw(ArgumentError("$fname: unknown TLV value type $typ for tag $tag; please share this file"))
        end
    end
    return recs
end

function _read_legacy_jws(path::AbstractString)
    fname = basename(path)
    c = CFBFile(path)
    tree = _cfb_tree(c)

    for req in ("DataInfo", "Y-Data")
        haskey(tree, req) ||
            throw(ArgumentError("$fname: missing stream '$req'; not a JASCO legacy .jws file"))
    end
    if haskey(tree, "Header")
        h = _cfb_stream(c, tree["Header"])
        sig = String(Char.(filter(!=(0x00), h[1:min(end, 24)])))
        startswith(sig, "L~") && occursin("SPCMAN", sig) ||
            throw(ArgumentError("$fname: unrecognized Header signature '$sig'; please share this file"))
    end

    # DataInfo: the structural core.
    di = _cfb_stream(c, tree["DataInfo"])
    length(di) == 96 ||
        throw(ArgumentError("$fname: DataInfo is $(length(di)) bytes, expected 96"))
    ver = read_le(UInt32, di, 0x00)
    ver == 3 ||
        throw(ArgumentError("$fname: DataInfo version $ver, expected 3; please share this file"))
    nchan = Int(read_le(UInt32, di, 0x0C))
    npoints = Int(read_le(UInt32, di, 0x14))
    firstx = read_le(Float64, di, 0x18)
    lastx = read_le(Float64, di, 0x20)
    deltax = read_le(Float64, di, 0x28)
    xdesc = read_le(UInt32, di, 0x30)
    ycode = read_le(UInt32, di, 0x34)

    npoints > 1 ||
        throw(ArgumentError("$fname: bad point count $npoints"))
    nchan == 1 ||
        throw(ArgumentError("$fname: $nchan data channels; only single-channel files are supported — please share this file"))
    (xdesc & 0xFFFFFF00) == LEGACY_XDESC_MARKER ||
        throw(ArgumentError("$fname: unrecognized x-axis descriptor 0x$(string(xdesc, base=16)); please share this file"))
    xunit_code = UInt8(xdesc & 0xFF)
    haskey(LEGACY_XUNIT_KINDS, xunit_code) ||
        throw(ArgumentError("$fname: unsupported x-unit code 0x$(string(xunit_code, base=16)); please share this file"))
    datatype = LEGACY_XUNIT_KINDS[xunit_code]
    yunits = ycode <= 0xFF && haskey(YMODE_YUNITS, UInt8(ycode)) ? YMODE_YUNITS[UInt8(ycode)] :
             ycode <= 0xFF && haskey(LEGACY_YMODE_EXTRA, UInt8(ycode)) ? LEGACY_YMODE_EXTRA[UInt8(ycode)] :
             throw(ArgumentError("$fname: unrecognized y-mode code 0x$(string(ycode, base=16)); please share this file"))

    yd = _cfb_stream(c, tree["Y-Data"])
    length(yd) == 4 * npoints ||
        throw(ArgumentError("$fname: Y-Data is $(length(yd)) bytes, expected $(4npoints)"))

    if haskey(tree, "X-Data")
        # Non-linear axis (Raman CCD): x values stored explicitly.
        xd = _cfb_stream(c, tree["X-Data"])
        length(xd) == 4 * npoints ||
            throw(ArgumentError("$fname: X-Data is $(length(xd)) bytes, expected $(4npoints)"))
        x = Float64.(ltoh.(reinterpret(Float32, xd)))
        issorted(x) || issorted(x; rev=true) ||
            throw(ArgumentError("$fname: X-Data axis is not monotonic; please share this file"))
        abs(x[1] - firstx) <= max(1e-4 * abs(firstx), 1e-4) ||
            throw(ArgumentError("$fname: X-Data starts at $(x[1]) but header declares FIRSTX=$firstx"))
    else
        # Linear grid reconstructed from FIRSTX + DELTAX. Stored LASTX is
        # rounded to the measured range; the grid is canonical.
        (isfinite(deltax) && deltax != 0) ||
            throw(ArgumentError("$fname: invalid DELTAX=$deltax"))
        xend = firstx + deltax * (npoints - 1)
        abs(xend - lastx) <= abs(deltax) ||
            @warn "$fname: stored LASTX ($lastx) disagrees with the data grid ($xend); using the grid"
        x = collect(firstx .+ deltax .* (0:npoints-1))
    end
    y = Float64.(ltoh.(reinterpret(Float32, yd)))

    # Metadata streams (all optional; absence tolerated).
    metadata = Dict{String,Any}(
        "NPOINTS" => npoints, "FIRSTX" => firstx, "LASTX" => last(x),
        "XUNITS" => "1/CM", "YUNITS" => yunits,
        "Format" => "SPCMAN2 CFB",
    )
    deltax != 0 && (metadata["DELTAX"] = deltax)   # linear grids only
    haskey(YMODE_CHANNEL, UInt8(ycode)) &&
        (metadata["Channel"] = YMODE_CHANNEL[UInt8(ycode)])

    sample_name = ""
    sample_date = nothing
    if haskey(tree, "SampleInfo")
        b = _cfb_stream(c, tree["SampleInfo"])
        (sample_name, off) = _jasco_string(b, 4)
        (comment, off) = _jasco_string(b, off)
        isempty(sample_name) || (metadata["Sample name"] = sample_name)
        isempty(comment) || (metadata["Comment"] = comment)
        nrec = Int(read_le(UInt32, b, off))
        recs = Dict(_jasco_tlv(b, off + 4, nrec, fname))
        if haskey(recs, 1) && recs[1] isa Float64
            sample_date = _ole_date(recs[1])
        end
    end

    if haskey(tree, "UserInfo")
        b = _cfb_stream(c, tree["UserInfo"])
        slots = String[]
        off = 4
        while off + 4 <= length(b)
            (s, off) = _jasco_string(b, off)
            push!(slots, s)
        end
        # 15 slots; slot 12 = company/organization
        length(slots) >= 12 && !isempty(slots[12]) && (metadata["Company"] = slots[12])
    end

    instrument = ""
    module_id = UInt16(0)
    if haskey(tree, "ModuleInfo")
        b = _cfb_stream(c, tree["ModuleInfo"])
        (modname, off) = _jasco_string(b, 4)
        module_id = read_le(UInt16, b, off + 2)
        (model, off2) = _jasco_string(b, off + 4)
        (serial, _) = _jasco_string(b, off2)
        instrument = model
        isempty(model) || (metadata["Model Name"] = model)
        isempty(serial) || (metadata["Serial Number"] = serial)
        isempty(modname) || (metadata["Module name"] = modname)
    end

    base_date = nothing
    if haskey(tree, "BaseInfo")
        b = _cfb_stream(c, tree["BaseInfo"])
        # [UInt32 1][16-byte GUID][UInt8 0][string original path][f64 saved][f64 measured][UInt32 nsources]
        (orig_path, off) = _jasco_string(b, 21)
        isempty(orig_path) || (metadata["Original path"] = orig_path)
        d_saved = _ole_date(read_le(Float64, b, off))
        base_date = _ole_date(read_le(Float64, b, off + 8))
        d_saved !== nothing && (metadata["Creation date"] = d_saved)
        nsources = off + 20 <= length(b) ? Int(read_le(UInt32, b, off + 16)) : 0
        nsources > 0 && (metadata["Derived"] = true)
    end

    # The MeasParam tag namespace is per module type: the named mapping is
    # verified for FTIR only. Other modules (e.g. NRS Raman) keep raw tag
    # numbers rather than risking mislabeled metadata.
    is_ftir_module = module_id == LEGACY_MODULE_FTIR
    meas_date = nothing
    if haskey(tree, "MeasParam")
        b = _cfb_stream(c, tree["MeasParam"])
        if length(b) >= 12 && read_le(UInt32, b, 0) == 1
            nrec = Int(read_le(UInt32, b, 8))
            for (t, v) in _jasco_tlv(b, 12, nrec, fname)
                key = is_ftir_module ? get(LEGACY_MEASPARAM_TAGS, t, "MeasParam.tag$t") :
                                       "MeasParam.tag$t"
                if is_ftir_module && t == 12 && v isa Float64
                    meas_date = _ole_date(v)
                    metadata[key] = something(meas_date, v)
                else
                    metadata[key] = v
                end
            end
        end
    end

    # Measurement date precedence: MeasParam tag 12, then SampleInfo, then
    # BaseInfo. All stored UTC (the modern binary reader's epoch is UTC too;
    # CSV exports carry instrument-local wall time instead).
    date = something(meas_date, sample_date, base_date, Some(nothing))

    title = isempty(sample_name) ? replace(fname, r"\.jws$"i => "") : sample_name

    return JASCOSpectrum(title, date, instrument, datatype,
                         "1/CM", yunits, x, y, metadata)
end
