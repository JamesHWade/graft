# Recall the current accepted evidence for a stream

Recall the current accepted evidence for a stream

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

  Host-chosen decision stream.

- purpose:

  Required consultation purpose.

- eligible:

  Fresh explicit host eligibility decision.

- max_decisions:

  Maximum decision records to inspect.

- max_metadata_bytes:

  Maximum aggregate decision metadata bytes.

- max_artifacts:

  Maximum artifacts in the selected closure.

- max_selection_bytes:

  Maximum encoded selection metadata bytes.

## Value

A point-in-time
[Recall](https://jameshwade.github.io/graft/reference/Recall.md).
