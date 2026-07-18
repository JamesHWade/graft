# Compile a LinkML schema into a graft manifest

`kg_compile_schema()` is the only public graft operation that requires
Python. It uses `linkml_runtime.SchemaView` to resolve the complete
import closure and writes a canonical JSON manifest. Loading the result
with
[`kg_schema()`](https://jameshwade.github.io/graft/reference/kg_schema.md)
does not require Python.

## Usage

``` r
kg_compile_schema(schema, output = NULL)
```

## Arguments

- schema:

  Path to a root LinkML YAML schema.

- output:

  Output path for the compiled `.graft.json` manifest. If `NULL`, the
  path is derived from `schema`.

## Value

A
[`kg_schema()`](https://jameshwade.github.io/graft/reference/kg_schema.md)
object loaded from the compiled manifest.
