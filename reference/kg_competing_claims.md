# Group candidate competing claims

The result contains comparison sets only. It preserves statement
wording, status, polarity, time fields, qualifiers, and attributes
without deciding whether any pair is contradictory.

## Usage

``` r
kg_competing_claims(
  store,
  class = "Claim",
  key = c("primary_subject"),
  include_superseded = FALSE,
  limit = 100
)
```

## Arguments

- store:

  An initialized `kg_store`.

- class:

  One concrete statement class.

- key:

  One or more public scalar grouping fields.

- include_superseded:

  Whether non-active statements may be candidates.

- limit:

  Maximum comparison groups to return.

## Value

A bounded data frame with one list-column of candidate records.
