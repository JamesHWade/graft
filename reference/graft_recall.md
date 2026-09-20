# Read the evidence currently accepted for a stream

Check the host application's current eligibility decision and the
stream's current decision. When the current decision accepts evidence
for the requested purpose, return its selection and verified artifacts.
The function checks the decision head again after reading the artifacts;
if it changed, it errors instead of returning a mixed result. The result
is a point-in-time check, not an access token.

## Usage

``` r
graft_recall(
  store,
  stream,
  purpose,
  eligible,
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

- stream:

  A decision stream chosen and controlled by the host application.

- purpose:

  Purpose for which consultation is requested.

- eligible:

  Fresh boolean supplied by the host application indicating whether
  consultation is currently allowed.

- max_decisions:

  Maximum decision records to inspect.

- max_metadata_bytes:

  Maximum aggregate decision metadata bytes.

- max_artifacts:

  Maximum artifacts in the selected dependency set.

- max_selection_bytes:

  Maximum encoded selection metadata bytes.

## Value

A point-in-time
[Recall](https://jameshwade.github.io/graft/reference/Recall.md).
