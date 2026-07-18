# Ingest one concrete record class

`kg_write()` is a convenience wrapper around the atomic
[`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md)
contract.

## Usage

``` r
kg_write(store, batch, class, records, mode = "upsert", validate = "fast")
```

## Arguments

- store:

  An initialized, writable `kg_store`.

- batch:

  A
  [`kg_batch()`](https://jameshwade.github.io/graft/reference/kg_batch.md)
  object.

- class:

  One concrete class name.

- records:

  A data frame for `class`.

- mode, validate:

  Passed to
  [`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md).

## Value

A `kg_ingest_result`.
