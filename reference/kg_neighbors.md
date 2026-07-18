# Retrieve a bounded graph neighborhood

`kg_neighbors()` performs deterministic breadth-first expansion for one
or two hops. It only follows generated graph projections and always
collects a bounded result.

## Usage

``` r
kg_neighbors(
  store,
  id,
  predicate = NULL,
  direction = c("both", "out", "in"),
  hops = 1,
  projection = c("semantic", "provenance", "combined"),
  max_nodes = 500,
  max_edges = 2000
)
```

## Arguments

- store:

  An initialized `kg_store`.

- id:

  One projected graph node identifier.

- predicate:

  Optional exact predicate restriction applied at every hop.

- direction:

  One of `"both"`, `"out"`, or `"in"`.

- hops:

  One or two hops.

- projection:

  One of `"semantic"`, `"provenance"`, or `"combined"`.

- max_nodes:

  Maximum collected nodes, up to 500.

- max_edges:

  Maximum collected edges, up to 2,000.

## Value

A collected `kg_subgraph` with nodes, edges, request metadata, limits,
truncation state, and the store structural digest.
