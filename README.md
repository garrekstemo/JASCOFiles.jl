# JASCOFiles.jl

[![CI](https://github.com/garrekstemo/JASCOFiles.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/garrekstemo/JASCOFiles.jl/actions/workflows/CI.yml)
[![docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://garrekstemo.github.io/JASCOFiles.jl/dev/)


JASCOFiles.jl reads text files from a JASCO 4600 FT-IR 
(Fourier Transform Infrared Spectrometer). It does not read the .jws files.
Instead the user must export raw data to a .csv or other text file format.
JASCOFiles.jl parses the file and stores metadata and xy data in a Julia type called `Spectrum`.

## Installation

To install JASCOFiles.jl, use the Julia package manager:
```
julia> using Pkg
julia> Pkg.add(url="https://github.com/garrekstemo/JASCOFiles.jl")
```

## Usage

``
Spectrum(filepath; encoding = enc"SHIFT-JIS")
``
