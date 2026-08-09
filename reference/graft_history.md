# Retrieve accepted record history

`graft_history()` reads immutable revisions and hydrates them with the
exact historical contract and sensitivity rules. A batch ID or timestamp
selects a deterministic commit boundary.

## Usage

``` r
graft_history(store, id, as_of = NULL, limit = 100L)
```

## Arguments

- store:

  An initialized Graft store.

- id:

  One internal record identifier.

- as_of:

  Optional committed batch ID or scalar `POSIXt` time.

- limit:

  Maximum revisions to return.

## Value

A bounded newest-first data frame with public record list-columns.
