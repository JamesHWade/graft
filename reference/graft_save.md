# Save text or raw bytes as an immutable artifact

Scalar nonmissing character input is encoded as UTF-8 and defaults to
`text/plain`. Raw input is retained exactly and defaults to
`application/octet-stream`. Strings are always content; use
[`graft_save_file()`](https://jameshwade.github.io/graft/reference/graft_save_file.md)
for explicit file ingestion.

## Usage

``` r
graft_save(
  store,
  x,
  id,
  media_type = NULL,
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

- x:

  One scalar character value or a raw vector.

- id:

  Stable artifact identity.

- media_type:

  Media type, or `NULL` for the input-dependent default.

- dependencies:

  One
  [ArtifactRef](https://jameshwade.github.io/graft/reference/ArtifactRef.md)
  or a list of them.

- max_artifacts:

  Maximum dependency references to verify.

## Value

An
[ArtifactRef](https://jameshwade.github.io/graft/reference/ArtifactRef.md).
