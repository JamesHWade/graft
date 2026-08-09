# Review edited open knowledge as a commit plan

`graft_review()` reads and validates an edited managed Open Knowledge
Format bundle without changing accepted knowledge. It returns the same
immutable plan type as
[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md),
bound to the exact bundle and accepted batch observed during review.
Call
[`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md)
after approval, then synchronize the working tree explicitly with
[`graft_sync()`](https://jameshwade.github.io/graft/reference/graft_sync.md).

## Usage

``` r
graft_review(store, path = NULL, provenance)
```

## Arguments

- store:

  An initialized `GraftStore`.

- path:

  Optional edited bundle directory. The default uses the managed OKF
  directory.

- provenance:

  A
  [`graft_provenance()`](https://jameshwade.github.io/graft/reference/graft_provenance.md)
  object describing the reviewer or host policy proposing the change.

## Value

An immutable `GraftCommitPlan` S7 object.
