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

  Host-chosen decision stream.

- expected:

  Required current predecessor: a
  [Decision](https://jameshwade.github.io/graft/reference/Decision.md)
  or exact digest.

- key:

  Required stable host request key.

- actor:

  Host-supplied actor identity.

- reason:

  Host-supplied withdrawal reason.

- max_decisions:

  Maximum decision records to inspect.

- max_metadata_bytes:

  Maximum aggregate decision metadata bytes.

## Value

A recorded withdrawal
[Decision](https://jameshwade.github.io/graft/reference/Decision.md).
The host transaction governs durability.
