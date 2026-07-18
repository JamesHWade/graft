# List slots in a graft schema

List slots in a graft schema

## Usage

``` r
kg_slots(schema, class = NULL)
```

## Arguments

- schema:

  A `kg_schema` object or manifest path.

- class:

  Optional concrete class name. When supplied, class-induced slot usage
  is returned; otherwise global slot definitions are returned.

## Value

A data frame with one row per slot.
