# Close a Graft store

Closing is idempotent. Graft disconnects only connections it created; a
caller-supplied connection remains open.

## Usage

``` r
graft_close(store)
```

## Arguments

- store:

  A `GraftStore` object.

## Value

`store`, invisibly.
