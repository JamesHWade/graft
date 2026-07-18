# Search manifest-declared record text

Search is case-insensitive and uses only each class's declared label and
search slots. Results are deterministically ranked and bounded.

## Usage

``` r
kg_find(store, query, class = NULL, limit = 20)
```

## Arguments

- store:

  An initialized `kg_store`.

- query:

  One non-empty search string.

- class:

  Optional concrete class restriction.

- limit:

  Maximum results to return.

## Value

A bounded data frame with stable IDs, classes, labels, and scores.
