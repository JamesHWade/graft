# List accepted definitions

`graft_definitions()` returns the composable metric, filter, and derived
definitions accepted into the store. A `GraftView` lists only
definitions accepted at its pinned boundary.

## Usage

``` r
graft_definitions(source, target = NULL)
```

## Arguments

- source:

  An initialized `GraftStore` or immutable `GraftView`.

- target:

  Optional public-table name used to filter the catalog.

## Value

A bounded data frame with one row per accepted definition and
list-columns for direct dependencies and eligible public columns.
