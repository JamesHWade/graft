# Retrieve the accepted history of one record

Revisions are returned in deterministic newest-first commit order.
`as_of` selects the state committed by a boundary: either an exact
committed batch identifier or a `POSIXt` time. Time boundaries are first
resolved to a committed batch order, so revision timestamps are never
used as transaction boundaries. With `limit = 1`, the returned `record`
is the accepted record at that boundary.

## Usage

``` r
kg_history(store, id, as_of = NULL, limit = 100)
```

## Arguments

- store:

  An initialized `kg_store`.

- id:

  One internal record identifier.

- as_of:

  Optional committed batch identifier or scalar `POSIXt` time.

- limit:

  Maximum number of revisions to return.

## Value

A bounded data frame with `changed_fields` and `record` list-columns.
