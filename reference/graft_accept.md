# Record acceptance of exact retained evidence

Record the host application's acceptance of a selection for a decision
stream and purpose. The returned decision records who made the decision
and why; it does not itself grant access to the selected artifacts.

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

  A decision stream chosen and controlled by the host application.

- expected:

  Required predecessor: `NULL`, a
  [Decision](https://jameshwade.github.io/graft/reference/Decision.md),
  or an exact external decision digest.

- key:

  Required stable request key supplied by the host application.

- actor:

  Actor identity supplied by the host application.

- reason:

  Review reason supplied by the host application.

- purpose:

  Purpose for which the host application records acceptance.

- max_decisions:

  Maximum decision records to inspect.

- max_metadata_bytes:

  Maximum aggregate decision metadata bytes.

- max_artifacts:

  Maximum artifacts in the selected dependency set.

- max_selection_bytes:

  Maximum encoded selection metadata bytes.

## Value

A recorded
[Decision](https://jameshwade.github.io/graft/reference/Decision.md).
For PostgreSQL stores, the application controls the surrounding
transaction and commit.
