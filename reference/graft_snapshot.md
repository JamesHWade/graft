# Capture an immutable knowledge snapshot

`graft_snapshot()` records the active schema build and latest committed
knowledge boundary of a Graft store. The returned value is serializable
and path-free: it contains no database connection, backend, or
filesystem path.

## Usage

``` r
graft_snapshot(store)
```

## Arguments

- store:

  An initialized, open `GraftStore`.

## Value

An immutable, serializable `GraftSnapshot` S7 object.
