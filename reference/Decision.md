# A host decision recorded in an artifact stream

`Decision` is a retained journal record describing one acceptance or
withdrawal. Its `selection` property stores the exact selection digest,
not the selected artifacts themselves. The record does not authenticate
its actor or grant current consultation access.

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

  Decision stream chosen and controlled by the host application.

- key:

  Stable request key supplied by the host application.

- previous:

  Exact predecessor decision digest, or `NULL` for the first record.

- action:

  Either `"accept"` or `"withdraw"`.

- selection:

  Exact selection digest named by the decision.

- actor:

  Actor identity supplied by the host application.

- reason:

  Review or withdrawal reason supplied by the host application.

- purpose:

  Consultation purpose supplied by the host application.
