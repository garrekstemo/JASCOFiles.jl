using JASCOFiles
using Documenter

DocMeta.setdocmeta!(JASCOFiles, :DocTestSetup, :(using JASCOFiles); recursive=true)

makedocs(;
    modules=[JASCOFiles],
    authors="Garrek Stemo <8449000+garrekstemo@users.noreply.github.com>",
    repo="https://github.com/garrekstemo/JASCOFiles.jl/blob/{commit}{path}#{line}",
    sitename="JASCOFiles.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://garrekstemo.github.io/JASCOFiles.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/garrekstemo/JASCOFiles.jl",
    devbranch="main",
)
