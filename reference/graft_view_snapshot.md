# Recover the immutable snapshot retained by a view

`graft_view_snapshot()` returns the exact path-free
[`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md)
retained by a `GraftView`. The returned snapshot is an isolated value:
changing its internal representation cannot change the view's pinned
boundary.

## Usage

``` r
graft_view_snapshot(view)
```

## Arguments

- view:

  A `GraftView` returned by
  [`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md).

## Value

An immutable, serializable `GraftSnapshot` S7 object.

## Details

This accessor reads only the snapshot already owned by the view. It does
not inspect the live store or advance the view to a later commit.
