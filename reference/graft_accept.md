# Record an acceptance of exact retained evidence

Record an acceptance of exact retained evidence

## Usage

``` r
graft_accept(
  store,
  x,
  stream,
  expected,
  key,
  actor,
  reason,
  purpose,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2,
  max_artifacts = 1000L,
  max_selection_bytes = 1024^2
)
```

## Arguments

- store:

  A store returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- x:

  One
  [ArtifactRef](https://jameshwade.github.io/graft/reference/ArtifactRef.md),
  a list of them, or an
  [ArtifactSelection](https://jameshwade.github.io/graft/reference/ArtifactSelection.md).

- stream:

  Host-chosen decision stream.

- expected:

  Required predecessor: `NULL`, a
  [Decision](https://jameshwade.github.io/graft/reference/Decision.md),
  or an exact external decision digest.

- key:

  Required stable host request key.

- actor:

  Host-supplied actor identity.

- reason:

  Host-supplied review reason.

- purpose:

  Host-supplied consultation purpose.

- max_decisions:

  Maximum decision records to inspect.

- max_metadata_bytes:

  Maximum aggregate decision metadata bytes.

- max_artifacts:

  Maximum artifacts in the selected closure.

- max_selection_bytes:

  Maximum encoded selection metadata bytes.

## Value

A recorded
[Decision](https://jameshwade.github.io/graft/reference/Decision.md).
The host transaction governs durability.
