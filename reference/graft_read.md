# Read one exact immutable artifact

Read one exact immutable artifact

## Usage

``` r
graft_read(store, ref)
```

## Arguments

- store:

  A store returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- ref:

  An exact
  [ArtifactRef](https://jameshwade.github.io/graft/reference/ArtifactRef.md).

## Value

An [Artifact](https://jameshwade.github.io/graft/reference/Artifact.md)
containing the retained bytes and metadata.
