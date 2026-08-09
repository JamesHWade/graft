# Plan and immediately commit candidate records

This convenience function is equivalent to calling
[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
followed by
[`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md).
Use the two-step form when a person or host policy must review
`plan@changes` before acceptance.

## Usage

``` r
graft_ingest(store, records, provenance)
```

## Arguments

- store:

  An initialized `GraftStore`.

- records:

  A named list of concrete-class data frames.

- provenance:

  A
  [`graft_provenance()`](https://jameshwade.github.io/graft/reference/graft_provenance.md)
  object.

## Value

An ordinary list summarizing committed observations.
