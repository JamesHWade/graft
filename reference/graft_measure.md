# Evaluate an accepted measure

`graft_measure()` evaluates one accepted measure over current accepted
state, or over the pinned boundary of a `GraftView`. Supplied arguments
bind to the measure's declared parameters as equality predicates, and
`by` may name only declared dimensions. Evaluation is read-only and
deterministic: the same boundary, definition, and arguments always
return the same answer.

## Usage

``` r
graft_measure(store, name, arguments = list(), by = NULL)
```

## Arguments

- store:

  An initialized `GraftStore` or immutable `GraftView`.

- name:

  The name of one accepted measure.

- arguments:

  A named list of values for declared parameters.

- by:

  Optional character vector of declared dimensions to group by.

## Value

A data frame with one `value` column, preceded by one column per `by`
dimension, carrying `measure_id`, `revision_id`, and
`store_schema_digest` attributes.
