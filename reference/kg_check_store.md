# Check revision-ledger and current-state integrity

Shallow checks validate relationships among batches, revisions, heads,
observations, schema versions, and typed current tables. With
`deep = TRUE`, Graft also parses and re-digests every revision payload
and compares every current typed record with its revision head. All
records may be scanned, but reported issues are always bounded.

## Usage

``` r
kg_check_store(store, deep = FALSE, limit = 100)
```

## Arguments

- store:

  An initialized `kg_store`.

- deep:

  Whether to perform payload and current-state digest checks.

- limit:

  Maximum number of issues to report.

## Value

A `kg_store_check` containing `valid`, scan details, and a bounded
`issues` data frame.
