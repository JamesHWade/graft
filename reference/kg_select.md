# Perform a bounded structured selection

`kg_select()` validates every class, field, filter, ordering clause, and
value against the active manifest. It does not accept SQL.

## Usage

``` r
kg_select(
  store,
  class,
  fields,
  filters = list(),
  order_by = list(),
  limit = 100
)
```

## Arguments

- store:

  An initialized `kg_store`.

- class:

  One concrete class.

- fields:

  One or more public scalar fields to return.

- filters:

  A list of filter clauses with `field`, `operator`, and, when required,
  `value`.

- order_by:

  A list of ordering clauses with `field` and optional `direction`
  (`"asc"` or `"desc"`).

- limit:

  Maximum rows to collect, up to the hard package cap.

## Value

A bounded, collected data frame.
