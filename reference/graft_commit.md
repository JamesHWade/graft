# Commit a reviewed knowledge-change plan

Before writing, Graft rechecks the plan digest, store identity and
format, active schema, write capability, source state, and every
expected record head. All accepted changes then commit in one DuckDB
transaction.

## Usage

``` r
graft_commit(store, plan)
```

## Arguments

- store:

  An initialized, writable `GraftStore`.

- plan:

  A valid `GraftCommitPlan` returned by
  [`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
  or
  [`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md).

## Value

An ordinary list summarizing committed observations.
