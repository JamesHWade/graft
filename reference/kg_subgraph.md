# Collect a bounded induced subgraph

`kg_subgraph()` explicitly collects projected nodes and every projected
edge whose endpoints are both in the retained identifier set.

## Usage

``` r
kg_subgraph(
  store,
  ids,
  projection = "combined",
  max_nodes = 500,
  max_edges = 2000
)
```

## Arguments

- store:

  An initialized `kg_store`.

- ids:

  Projected graph node identifiers.

- projection:

  One of `"combined"`, `"semantic"`, or `"provenance"`.

- max_nodes:

  Maximum collected nodes, up to 500.

- max_edges:

  Maximum collected edges, up to 2,000.

## Value

A collected `kg_subgraph` with limit and truncation metadata.
