# Withdraw the current acceptance for a decision stream

Withdraw the current acceptance for a decision stream

## Usage

``` r
graft_withdraw(
  store,
  stream,
  expected,
  key,
  actor,
  reason,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2
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

- expected:

  Required current predecessor: a
  [Decision](https://jameshwade.github.io/graft/reference/Decision.md)
  or exact digest.

- key:

  Required stable request key supplied by the host application.

- actor:

  Actor identity supplied by the host application.

- reason:

  Withdrawal reason supplied by the host application.

- max_decisions:

  Maximum decision records to inspect.

- max_metadata_bytes:

  Maximum aggregate decision metadata bytes.

## Value

A recorded withdrawal
[Decision](https://jameshwade.github.io/graft/reference/Decision.md).
For PostgreSQL stores, the application controls the surrounding
transaction and commit.
