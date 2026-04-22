using JASCOFiles
using Documenter

DocMeta.setdocmeta!(JASCOFiles, :DocTestSetup, :(using JASCOFiles); recursive=true)

makedocs(;
    modules=[JASCOFiles],
    authors="Garrek Stemo <8449000+garrekstemo@users.noreply.github.com>",
    repo=Remotes.GitHub("garrekstemo", "JASCOFiles.jl"),
    sitename="JASCOFiles.jl",
    checkdocs=:exports,
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://garrekstemo.github.io/JASCOFiles.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Introduction" => "index.md",
        "Guide" => Any[
            "Quick start" => "guide/quickstart.md",
            "File formats" => "guide/file-formats.md",
        ],
        "Library" => "lib/public.md",
    ],
)

deploydocs(;
    repo="github.com/garrekstemo/JASCOFiles.jl",
    devbranch="main",
)
