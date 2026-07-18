# Look up an exact external identifier

The input is normalized using the versioned namespace contract declared
by the active manifest. Only active primary and equivalent registry
entries match.

## Usage

``` r
kg_lookup(store, namespace, value, class = NULL)
```

## Arguments

- store:

  An initialized `kg_store`.

- namespace:

  A manifest-declared external-identifier namespace.

- value:

  One external identifier value.

- class:

  Optional concrete class restriction.

## Value

A data frame containing exact registry matches and provenance.
