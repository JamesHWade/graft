# List unresolved mentions

List unresolved mentions

## Usage

``` r
kg_unresolved(store, class = NULL, source_id = NULL, limit = 1000)
```

## Arguments

- store:

  An initialized `kg_store`.

- class:

  Optional concrete mention class.

- source_id:

  Optional source record restriction.

- limit:

  Maximum rows to return.

## Value

A bounded data frame of mention records with null `entity_id`.
