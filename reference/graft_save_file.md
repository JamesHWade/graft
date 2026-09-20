# Save a bounded regular file as an immutable artifact

File ingestion is explicit. The path must identify a regular file no
larger than the store byte bound, and file bytes are never deserialized
or executed.

## Usage

``` r
graft_save_file(
  store,
  path,
  id = basename(path),
  media_type = "application/octet-stream",
  dependencies = list(),
  max_artifacts = 1000L
)
```

## Arguments

- store:

  A store returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- path:

  Path to a regular file.

- id:

  Stable artifact identity; defaults to
  [`basename()`](https://rdrr.io/r/base/basename.html) of `path`.

- media_type:

  Media type recorded for the bytes.

- dependencies:

  One
  [ArtifactRef](https://jameshwade.github.io/graft/reference/ArtifactRef.md)
  or a list of them.

- max_artifacts:

  Maximum dependency references to verify.

## Value

An
[ArtifactRef](https://jameshwade.github.io/graft/reference/ArtifactRef.md).
