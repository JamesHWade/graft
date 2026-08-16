# Run a bounded advanced retrieval operation

`graft_query()` is the advanced read-only retrieval surface. It accepts
a named `request` rather than SQL. Supported operations are `"lookup"`,
`"identifiers"`, `"claims"`, `"evidence"`, `"neighbors"`, `"traverse"`,
`"unresolved"`, and `"integrity"`.

## Usage

``` r
graft_query(
  store,
  operation = c("lookup", "identifiers", "claims", "evidence", "neighbors", "traverse",
    "unresolved", "integrity"),
  request = list(),
  limit = 100L
)
```

## Arguments

- store:

  An initialized `GraftStore` or immutable `GraftView`.

- operation:

  One supported operation name.

- request:

  A named list of operation-specific values.

- limit:

  Maximum rows for tabular operations.

## Value

An ordinary bounded data frame or list, depending on the operation.

## Details

Request members are operation-specific: exact identifier lookup accepts
`namespace`, `value`, and optional `class`; identifiers and claims
accept `id`; evidence accepts `statement_id` or `source_id`; graph
operations accept their bounded path and projection arguments;
unresolved mentions accept optional `class` and `source_id`; and
integrity accepts `projections`. Unknown members are rejected. Tabular
results carry `limit`, `truncated`, and `store_schema_digest`
attributes. A `GraftView` pins every operation and does not support
`"integrity"`.
