# Evaluate accepted definitions

`graft_calculate()` composes accepted metrics with same-table
dimensions, filters, and simple predicates over current accepted state
or the immutable boundary of a `GraftView`. Evaluation fails closed when
the target exceeds Graft's hard calculation-input or result-row bound.

## Usage

``` r
graft_calculate(
  source,
  metrics,
  dimensions = NULL,
  filters = NULL,
  where = NULL
)
```

## Arguments

- source:

  An initialized `GraftStore` or immutable `GraftView`.

- metrics:

  One or more accepted metric names.

- dimensions:

  Optional public columns or accepted derived definitions.

- filters:

  Optional accepted filter definitions.

- where:

  Optional list of simple `column`, `op`, and string `value` predicates
  combined with AND.

## Value

A data frame with dimensions followed by metrics in request order.
