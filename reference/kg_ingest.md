# Atomically ingest one or more record classes

All supplied classes, generated multivalue tables, identifiers, origins,
observations, and batch metadata commit in one DuckDB transaction. A
failure in any class rolls back the entire batch.

## Usage

``` r
kg_ingest(store, batch, records, mode = "upsert", validate = "fast")
```

## Arguments

- store:

  An initialized, writable `kg_store`.

- batch:

  A
  [`kg_batch()`](https://jameshwade.github.io/graft/reference/kg_batch.md)
  object.

- records:

  A named list of concrete-class data frames. Multivalued fields must be
  list-columns. `.graft_origin_key` is reserved for producer-side
  identity.

- mode:

  Ingestion mode. Milestone 1 supports `"upsert"`.

- validate:

  Validation level. Milestone 1 supports `"fast"`.

## Value

A `kg_ingest_result`. A committed producer/idempotency replay returns
the original result with `replay = TRUE` and signals
`graft_batch_replay`.
