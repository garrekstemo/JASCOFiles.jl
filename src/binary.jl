# Native reader for JASCO binary spectra. Two on-disk formats share one
# container (magic "L~S ", version "R2.0.0"):
#   .jws  format id "SPECMAN"  - written by the desktop Spectra Manager software
#   .jrs  format id "SPECIRM"  - written by the spectrometer's onboard firmware
# Both have an identical fixed-offset header and a trailing little-endian
# Float32 data block, so one reader serves both. Reverse-engineered and
# validated against FT/IR-4600 and V-730 files; see
# docs/superpowers/specs/2026-06-04-jws-binary-reader-design.md.

const JWS_MAGIC = b"L~S "
const JWS_VERSION = "R2.0.0"
const JWS_IDS = ("SPECMAN", "SPECIRM")
const JWS_DATA_OFFSET = 0x740  # fixed header size; the Float32 data block
#                                starts here in every known SPECMAN/SPECIRM
#                                R2.0.0 file (verified across FT/IR-4600 and
#                                V-730 corpora, 2019–2026)

# Byte offsets (0-based) into the fixed header.
const OFF_FILEID     = 0x08
const OFF_VERSION    = 0x20
const OFF_NPOINTS    = 0x84
const OFF_FIRSTX     = 0x88
const OFF_LASTX      = 0x90
const OFF_DELTAX     = 0x98
const OFF_XUNIT      = 0xA0   # descriptor tag at 0-based 0xA0..0xA7:
#                               0xA0 x-unit code; 0xA1..0xA3 = 01 00 10;
#                               0xA4 y-mode code; 0xA5..0xA7 = 00 00 00
const OFF_YMODE      = 0xA4
const OFF_DATALEN    = 0xC8
const OFF_INSTRUMENT = 0x140
const OFF_SERIAL     = 0x160
const OFF_TITLE      = 0x180
const OFF_COMMENT    = 0x1C0
const OFF_EPOCH      = 0x2C0

# y-mode code (byte at OFF_YMODE) -> JASCO YUNITS string.
const YMODE_YUNITS = Dict{UInt8,String}(
    0x00 => "TRANSMITTANCE",
    0x02 => "REFLECTANCE",
    0x03 => "ABSORBANCE",
    0x08 => "INTENSITY",   # single-beam, FTIR background channel
    0x09 => "INTENSITY",   # single-beam, reference channel
    0x0a => "INTENSITY",   # single-beam, sample channel
)
const YMODE_CHANNEL = Dict{UInt8,String}(
    0x08 => "Background", 0x09 => "Reference", 0x0a => "Sample")

# Read a little-endian scalar of type T at 0-based byte offset `off`.
function read_le(::Type{T}, b::Vector{UInt8}, off::Integer) where {T}
    return ltoh(reinterpret(T, b[off+1:off+sizeof(T)])[1])
end

# Read a fixed-width, null-terminated string field decoded with `encoding`.
function read_cstr(b::Vector{UInt8}, off::Integer, width::Integer, encoding)
    i = off + 1
    stop = i
    limit = min(off + width, length(b))
    while stop <= limit && b[stop] != 0x00
        stop += 1
    end
    return strip(decode(b[i:stop-1], encoding))
end

# Instrument model -> (datatype, xunits, expected x-unit code). Throws on an
# unsupported instrument family. UV-Vis datatype is left blank to match the
# V-series text export (isuvvis infers from NANOMETERS + range).
function _instrument_kind(instrument::AbstractString, fname::AbstractString)
    if startswith(instrument, "FT/IR")
        return ("INFRARED SPECTRUM", "1/CM", 0x00)
    elseif startswith(instrument, "V-")
        return ("", "NANOMETERS", 0x03)
    else
        throw(ArgumentError("$fname: unsupported instrument '$instrument'; only FTIR and UV-Vis are supported — please share this file"))
    end
end

function _read_jws(path::AbstractString; encoding=enc"SHIFT-JIS")
    bytes = read(path)
    fname = basename(path)
    n = length(bytes)

    # 1. minimum size for the fixed header
    n >= JWS_DATA_OFFSET ||
        throw(ArgumentError("$fname: file too short ($n bytes) to be a JASCO .jws/.jrs file"))

    # 2. magic
    bytes[1:4] == JWS_MAGIC ||
        throw(ArgumentError("$fname: not a JASCO .jws/.jrs file (missing 'L~S ' signature)"))

    # 3. container id + version + descriptor structural bytes
    fileid = read_cstr(bytes, OFF_FILEID, 16, encoding)
    version = read_cstr(bytes, OFF_VERSION, 16, encoding)
    structural_ok = bytes[OFF_XUNIT+2] == 0x01 && bytes[OFF_XUNIT+3] == 0x00 &&
                    bytes[OFF_XUNIT+4] == 0x10 && bytes[OFF_XUNIT+6] == 0x00 &&
                    bytes[OFF_XUNIT+7] == 0x00 && bytes[OFF_XUNIT+8] == 0x00
    (fileid in JWS_IDS && version == JWS_VERSION && structural_ok) ||
        throw(ArgumentError("$fname: unrecognized binary variant ($fileid $version); please share this file"))

    # 4. instrument family -> datatype / xunits (throws if unsupported)
    instrument = read_cstr(bytes, OFF_INSTRUMENT, 32, encoding)
    datatype, xunits, expected_xunit = _instrument_kind(instrument, fname)

    # 5. x-unit code cross-check
    xunit = bytes[OFF_XUNIT+1]
    xunit == expected_xunit ||
        throw(ArgumentError("$fname: x-unit code 0x$(string(xunit, base=16)) does not match instrument '$instrument'"))

    # 6. y-mode code -> yunits
    ymode = bytes[OFF_YMODE+1]
    haskey(YMODE_YUNITS, ymode) ||
        throw(ArgumentError("$fname: unrecognized y-mode code 0x$(string(ymode, base=16)); please share this file"))
    yunits = YMODE_YUNITS[ymode]

    # 7. point count / data block size / data offset
    npoints = Int(read_le(Int32, bytes, OFF_NPOINTS))
    datalen = Int(read_le(Int64, bytes, OFF_DATALEN))
    (npoints > 0 && datalen == npoints * 4) ||
        throw(ArgumentError("$fname: inconsistent point count (NPOINTS=$npoints, data=$datalen bytes, file=$n bytes)"))
    # The data block is tail-anchored; in every known R2.0.0 file it begins
    # exactly at the end of the fixed header. Any other offset means an
    # unknown variant (e.g. appended blocks) — refuse rather than decode
    # garbage.
    doff = n - datalen
    doff == JWS_DATA_OFFSET ||
        throw(ArgumentError("$fname: unexpected data layout (data block at byte $doff, expected $(Int(JWS_DATA_OFFSET))); please share this file"))

    firstx = read_le(Float64, bytes, OFF_FIRSTX)
    deltax = read_le(Float64, bytes, OFF_DELTAX)

    # 8. DELTAX must be usable. The x-axis is reconstructed from
    # FIRSTX + DELTAX*(0:npoints-1); the stored LASTX field (OFF_LASTX) is
    # informational and is NOT a hard check — real files can store a LASTX that
    # disagrees with the actual grid (e.g. a truncated V-730 reflectance scan
    # that records the configured end but only a few acquired points). Using
    # `isfinite(deltax) && deltax != 0` keeps a corrupt step from producing a
    # NaN/Inf grid.
    (isfinite(deltax) && deltax != 0) ||
        throw(ArgumentError("$fname: invalid DELTAX=$deltax"))

    y = Float64.(ltoh.(reinterpret(Float32, bytes[doff+1:n])))
    x = collect(firstx .+ deltax .* (0:npoints-1))

    epoch = read_le(Int32, bytes, OFF_EPOCH)   # Unix epoch, UTC (Int32 field -> year-2038 ceiling)
    date = epoch > 0 ? unix2datetime(epoch) : nothing

    serial  = read_cstr(bytes, OFF_SERIAL, 32, encoding)
    title   = read_cstr(bytes, OFF_TITLE, 64, encoding)
    comment = read_cstr(bytes, OFF_COMMENT, 64, encoding)
    isempty(title) && (title = "Untitled")

    metadata = Dict{String,Any}(
        "TITLE" => title,
        "DATA TYPE" => datatype,
        "SPECTROMETER/DATA SYSTEM" => instrument,
        "XUNITS" => xunits,
        "YUNITS" => yunits,
        "FIRSTX" => firstx,
        "LASTX" => last(x),
        "DELTAX" => deltax,
        "NPOINTS" => npoints,
        "Serial Number" => serial,
        "Comment" => comment,
        "Format" => "$fileid $version",
    )
    haskey(YMODE_CHANNEL, ymode) && (metadata["Channel"] = YMODE_CHANNEL[ymode])

    return JASCOSpectrum(title, date, instrument, datatype, xunits, yunits, x, y, metadata)
end
