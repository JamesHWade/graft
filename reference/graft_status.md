# Inspect the managed open-knowledge working tree

`graft_status()` reports whether the configured OKF working tree is
current, modified, stale, missing, unconfigured, or incompatible.
Inspection never changes the store or filesystem.

## Usage

``` r
graft_status(store, path = NULL, deep = TRUE)
```

## Arguments

- store:

  An initialized `GraftStore`.

- path:

  Optional OKF directory. The default uses the managed path.

- deep:

  Whether to verify the working tree's content digest.

## Value

An ordinary status list.
