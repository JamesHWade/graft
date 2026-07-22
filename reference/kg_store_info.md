# Inspect a graft store

Inspect a graft store

## Usage

``` r
kg_store_info(store)
```

## Arguments

- store:

  A `kg_store` object.

## Value

A named list describing the connection, initialization state, observed
and required store formats, active schema fingerprints, and
revision-history coverage. `store_format_version` is `NA` when no store
metadata can be observed, including before initialization and after
close.
