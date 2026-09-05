# Turn raw structured proposals into a reviewable plan

`graft_proposal_plan()` checks the raw object shape, preserves each row
and value in list-columns, and delegates acceptance validation to
[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md).
It never commits, calls a provider, or requires ellmer. Supply the
unconverted result of `chat_structured(..., convert = FALSE)`; converted
data frames are rejected so upstream conversion cannot hide unknown
fields or malformed rows.

## Usage

``` r
graft_proposal_plan(store, proposal, provenance, max_rows = 100L)
```

## Arguments

- store:

  An initialized `GraftStore` with a data-dict contract.

- proposal:

  A named list of table arrays, each an unnamed list of named record
  objects. JSON arrays must remain lists, including primitive lists.

- provenance:

  A
  [`graft_provenance()`](https://jameshwade.github.io/graft/reference/graft_provenance.md)
  object with explicit idempotency.

- max_rows:

  Maximum records per table, from 1 to 1,000. Set this to the same value
  used for
  [`graft_proposal_type()`](https://jameshwade.github.io/graft/reference/graft_proposal_type.md).

## Value

A `GraftCommitPlan` from
[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md),
without changing accepted data.

## Details

Malformed objects, unknown or restricted fields, and incompatible JSON
value types raise a `graft_validation_error`. Missing required values,
invalid enum values, and unknown references are reported in the returned
plan's `@issues`. These are complete candidate records, not patches:
omitted optional values are missing values under ordinary planning
semantics. The host retains review, provenance, idempotency,
credentials, and the decision to
[`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md).
Retain the accepted plan to retry its commit. Replanning after
acceptance creates a different plan and cannot reuse an already
committed replay key.
