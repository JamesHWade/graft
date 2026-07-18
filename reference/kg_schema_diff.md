# Compare two compiled graft schemas

The structural digest determines compatibility. The returned report also
identifies class, slot, enum, table, and generated-relation changes so a
mismatch is useful to an interactive user or pipeline.

## Usage

``` r
kg_schema_diff(old_schema, new_schema)
```

## Arguments

- old_schema:

  A `kg_schema` object or manifest path.

- new_schema:

  A `kg_schema` object or manifest path.

## Value

A `kg_schema_diff` object.
