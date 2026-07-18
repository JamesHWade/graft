# Access a graph edge projection

`kg_edges()` returns semantic edges, provenance edges, or their
normalized union. Semantic edges are only direct edge records and
entity-valued semantic statements. Narrative statements and literal
objects are never semantic edges. The result is lazy and never collects
implicitly.

## Usage

``` r
kg_edges(store, projection = c("semantic", "provenance", "combined"))
```

## Arguments

- store:

  An initialized `kg_store`.

- projection:

  One of `"semantic"`, `"provenance"`, or `"combined"`.

## Value

A lazy dbplyr table. The combined projection adds `edge_class` and
`created_at` columns to provenance rows to match the semantic schema.
