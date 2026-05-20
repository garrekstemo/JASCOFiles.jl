module JASCOFilesTablesExt

using JASCOFiles
using Tables

Tables.istable(::Type{<:JASCOSpectrum}) = true
Tables.columnaccess(::Type{<:JASCOSpectrum}) = true
Tables.columns(s::JASCOSpectrum) = (x = s.x, y = s.y)
Tables.schema(::JASCOSpectrum) = Tables.Schema((:x, :y), (Float64, Float64))

end # module
