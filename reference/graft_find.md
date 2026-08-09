# Search current accepted records

`graft_find()` searches manifest-declared public search fields in
current headed revisions. Results are collected, deterministic, and
bounded.

## Usage

``` r
graft_find(store, query, class = NULL, limit = 20L)
```

## Arguments

- store:

  An initialized Graft store.

- query:

  One non-empty case-insensitive search string.

- class:

  Optional concrete class restriction.

- limit:

  Maximum rows to return, up to the package hard limit.

## Value

A bounded data frame with a public-record list-column.
