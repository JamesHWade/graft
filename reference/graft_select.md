# Capture and verify an exact dependency selection

Save the roots and their complete verified dependency set as one
immutable selection. The selection records references to artifacts; it
does not grant approval or access.

## Usage

``` r
graft_select(store, roots, max_artifacts = 1000L, max_metadata_bytes = 1024^2)
```

## Arguments

- store:

  A store returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- roots:

  One
  [ArtifactRef](https://jameshwade.github.io/graft/reference/ArtifactRef.md)
  or a list of them.

- max_artifacts:

  Maximum dependency references to verify.

- max_metadata_bytes:

  Maximum encoded selection metadata bytes.

## Value

A verified
[ArtifactSelection](https://jameshwade.github.io/graft/reference/ArtifactSelection.md).
