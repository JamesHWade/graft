# Open an immutable read view

`graft_at()` binds a live store connection to a previously captured
[`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md).
Reads through the returned view remain fixed at the snapshot's committed
boundary even after later commits. The view is connection-bound and
cannot outlive or close its underlying store.

## Usage

``` r
graft_at(store, snapshot)
```

## Arguments

- store:

  An initialized, open `GraftStore` containing the snapshot.

- snapshot:

  A `GraftSnapshot` returned by
  [`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md).

## Value

A read-only, connection-bound `GraftView` S7 object.
