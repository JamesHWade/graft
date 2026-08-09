# Synchronize the managed open-knowledge working tree

`graft_sync()` replaces the configured OKF working tree with a
deterministic projection of current accepted knowledge. It returns an
ordinary summary list and never changes accepted records.

## Usage

``` r
graft_sync(store, path = NULL, limit = 5000L)
```

## Arguments

- store:

  An initialized `GraftStore`.

- path:

  Optional destination directory. The default uses the managed path
  configured by
  [`graft_open()`](https://jameshwade.github.io/graft/reference/graft_open.md).

- limit:

  Maximum number of concepts to synchronize.

## Value

An ordinary list summarizing the synchronized bundle.
