# List accepted measures

`graft_measures()` returns the measure definitions accepted into the
store: governed, named calculations that evaluate over accepted state. A
`GraftView` lists only measures accepted at its pinned boundary.

## Usage

``` r
graft_measures(store)
```

## Arguments

- store:

  An initialized `GraftStore` or immutable `GraftView`.

## Value

A bounded data frame with one row per accepted measure and list-columns
for declared parameters and dimensions.
