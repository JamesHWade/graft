# Traverse a bounded predicate path

`kg_traverse()` follows a manifest-safe sequence of one or two
predicates. It uses generated joins for each hop and never runs
recursive or unbounded SQL.

## Usage

``` r
kg_traverse(
  store,
  from,
  via,
  direction = "out",
  max_hops = length(via),
  max_nodes = 500,
  max_edges = 2000,
  projection = "combined"
)
```

## Arguments

- store:

  An initialized `kg_store`.

- from:

  One projected graph node identifier.

- via:

  One or two exact predicates in traversal order.

- direction:

  One of `"out"`, `"in"`, or `"both"`.

- max_hops:

  Maximum predicates from `via` to follow, up to two.

- max_nodes:

  Maximum collected nodes, up to 500.

- max_edges:

  Maximum collected edges, up to 2,000.

- projection:

  One of `"combined"`, `"semantic"`, or `"provenance"`.

## Value

A collected `kg_subgraph` with path and limit metadata.
