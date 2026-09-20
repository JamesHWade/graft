# Read the chronological decision journal for one stream

Read the chronological decision journal for one stream

## Usage

``` r
graft_history(
  store,
  stream,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2
)
```

## Arguments

- store:

  A store returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- stream:

  A decision stream chosen and controlled by the host application.

- max_decisions:

  Maximum decision records to inspect.

- max_metadata_bytes:

  Maximum aggregate decision metadata bytes.

## Value

A chronological list of
[Decision](https://jameshwade.github.io/graft/reference/Decision.md)
values, oldest first.
