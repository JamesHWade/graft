# Derive a structured proposal type from the accepted dictionary

`graft_proposal_type()` returns a public ellmer type for an object whose
properties are table names and whose values are arrays of complete
candidate records. Use
`chat$chat_structured(..., type = type, convert = FALSE)` to retain raw
output for
[`graft_proposal_plan()`](https://jameshwade.github.io/graft/reference/graft_proposal_plan.md).
The type can also be supplied to a dsprrr signature's `output_type`
argument.

## Usage

``` r
graft_proposal_type(source, tables = NULL, fields = NULL, max_rows = 100L)
```

## Arguments

- source:

  An initialized `GraftStore` or immutable `GraftView` with a data-dict
  contract. A view freezes the type's contract; planning always
  validates against the destination store's active contract.

- tables:

  Optional character vector of dictionary table names.

- fields:

  Optional named list of column-name vectors, keyed by selected table.
  Unspecified tables include every public column. Selections must
  include all required columns and may not include restricted columns.

- max_rows:

  Maximum records per table, from 1 to 1,000.

## Value

An [`ellmer::Type`](https://ellmer.tidyverse.org/reference/Type.html)
object usable by `chat_structured()` or dsprrr.

## Details

Every selected property is required in the output object. Optional
columns accept JSON null; required columns and list elements do not.
Primary keys and foreign keys are strings. Foreign-key existence,
cross-record constraints, and accepted state are checked by planning,
not by a model's output schema. Restricted columns are excluded. Tables
with required restricted columns are rejected: those records require a
trusted host's ordinary
[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
path. Only schema-derived type information is sent to the model, with no
examples, source paths, or free-form dictionary metadata.
