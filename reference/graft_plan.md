# Plan a candidate knowledge change without writing it

Planning normalizes records, resolves identity, validates the candidate
set, and binds its expected record heads to the active store and schema.
It does not persist records or batch metadata. Invalid input returns a
plan whose `@valid` property is `FALSE` and whose `@issues` table
describes the failure.

## Usage

``` r
graft_plan(store, records, provenance)
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

An immutable `GraftCommitPlan` S7 object.
