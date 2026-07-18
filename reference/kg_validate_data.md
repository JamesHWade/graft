# Validate records without writing them

Preflight validation performs the same normalization, identity, shape,
and reference checks used by
[`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md)
without creating a batch or mutating the store.

## Usage

``` r
kg_validate_data(store, records)
```

## Arguments

- store:

  An initialized `kg_store`.

- records:

  A named list of concrete-class data frames.

## Value

A `kg_validation_report`.
