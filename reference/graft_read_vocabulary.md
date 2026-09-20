# Read a retained vocabulary release

Resolve an exact release selection, verify it against the live artifact
store, and reconstruct every release field from retained bytes. A
supplied
[VocabularyRelease](https://jameshwade.github.io/graft/reference/VocabularyRelease.md)
is treated as a selection descriptor; its cached vocabulary fields are
never trusted.

## Usage

``` r
graft_read_vocabulary(store, release)
```

## Arguments

- store:

  An
  [ArtifactStore](https://jameshwade.github.io/graft/reference/ArtifactStore.md)
  returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- release:

  A
  [VocabularyRelease](https://jameshwade.github.io/graft/reference/VocabularyRelease.md),
  [ArtifactSelection](https://jameshwade.github.io/graft/reference/ArtifactSelection.md),
  or exact selection digest returned by
  [`graft_publish_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_publish_vocabulary.md).

## Value

A freshly materialized
[VocabularyRelease](https://jameshwade.github.io/graft/reference/VocabularyRelease.md).
