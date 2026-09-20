# Read one exact retained dependency selection

Read one exact retained dependency selection

## Usage

``` r
graft_read_selection(
  store,
  id,
  max_artifacts = 1000L,
  max_metadata_bytes = 1024^2
)
```

## Arguments

- store:

  A store returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- id:

  Exact selection digest.

- max_artifacts:

  Maximum dependency references to verify.

- max_metadata_bytes:

  Maximum encoded selection metadata bytes.

## Value

A verified
[ArtifactSelection](https://jameshwade.github.io/graft/reference/ArtifactSelection.md).
