# Load a compiled graft schema manifest

Loading a manifest is implemented entirely in R and does not initialize
Python or require `linkml_runtime`.

## Usage

``` r
kg_schema(path)
```

## Arguments

- path:

  Path to a compiled `.graft.json` manifest.

## Value

An immutable `kg_schema` S3 object.
