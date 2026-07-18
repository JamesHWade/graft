# Retrieve evidence for one statement

Evidence is joined to the exact stored source record. Citation and
locator fields are returned only from stored rows.

## Usage

``` r
kg_evidence(store, statement_id, support_type = NULL, limit = 100)
```

## Arguments

- store:

  An initialized `kg_store`.

- statement_id:

  One internal statement identifier.

- support_type:

  Optional evidence support type.

- limit:

  Maximum evidence records to return.

## Value

A bounded data frame of evidence and source details.
