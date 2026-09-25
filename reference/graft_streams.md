# List decision streams and their current decisions

Find the decision streams in a store without keeping a separate catalog.
Each stream's journal is read and verified the same way as
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md),
and its latest decision is returned. Like
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md),
this reads decision records only: it returns no artifact content and
needs no eligibility decision. Use
[`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md)
to read the accepted evidence. The host application still decides who
may see stream names, actors, and reasons.

## Usage

``` r
graft_streams(
  store,
  purpose = NULL,
  max_streams = 1000L,
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

- purpose:

  Optional purpose. When supplied, only streams whose current decision
  was recorded for this purpose are returned.

- max_streams:

  Maximum decision streams to inspect.

- max_decisions:

  Maximum decision records to inspect per stream.

- max_metadata_bytes:

  Maximum aggregate decision metadata bytes across all streams.

## Value

A list of
[Decision](https://jameshwade.github.io/graft/reference/Decision.md)
values, one per stream: each stream's current decision, ordered by
stream name. Check `@action` for `"accept"` or `"withdraw"`.

## Details

Decisions carry no timestamps, so streams are ordered by name, compared
bytewise.
