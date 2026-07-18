# Access the graph node projection

`kg_nodes()` returns the generated, manifest-driven node projection. It
is lazy and never collects implicitly.

## Usage

``` r
kg_nodes(store)
```

## Arguments

- store:

  An initialized `kg_store`.

## Value

A lazy dbplyr table with node identifiers, classes, labels, roles,
statement shapes, type URIs, and creation times.
