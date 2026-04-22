```@meta
CurrentModule = JASCOFiles
```

# Public API

Only exported types and functions are considered part of the public API. Raw header fields not covered by the exposed struct fields are still available through `s.metadata`.

## Index

```@index
Pages = ["public.md"]
```

## Reading files

```@autodocs
Modules = [JASCOFiles]
Pages = ["parser.jl"]
Private = false
```

## Types

```@autodocs
Modules = [JASCOFiles]
Pages = ["types.jl"]
Private = false
```

## Type predicates and Base methods

```@autodocs
Modules = [JASCOFiles]
Pages = ["utils.jl"]
Private = false
```
