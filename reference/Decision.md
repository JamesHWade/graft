# A host decision recorded in an artifact stream

`Decision` is a journal value describing one acceptance or withdrawal.
Its `selection` property is the exact selection digest, not a
materialized selection. It is a descriptor and does not authenticate its
actor or grant current consultation access.

## Usage

``` r
Decision(
  id = character(0),
  sequence = integer(0),
  stream = character(0),
  key = character(0),
  previous = NULL,
  action = character(0),
  selection = character(0),
  actor = character(0),
  reason = character(0),
  purpose = character(0)
)
```

## Arguments

- id:

  Decision digest.

- sequence:

  Chronological sequence number within the stream.

- stream:

  Host-chosen decision stream.

- key:

  Stable host idempotency key.

- previous:

  Exact predecessor decision digest, or `NULL` for the first record.

- action:

  Either `"accept"` or `"withdraw"`.

- selection:

  Exact selection digest named by the decision.

- actor:

  Host-supplied actor identity.

- reason:

  Host-supplied review or withdrawal reason.

- purpose:

  Host-supplied consultation purpose.
