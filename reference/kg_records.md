# Read records from one concrete class

`kg_records()` exposes only a manifest-declared client class. It returns
a lazy dbplyr table and never collects implicitly.

## Usage

``` r
kg_records(store, class)
```

## Arguments

- store:

  An initialized `kg_store`.

- class:

  One concrete class name from the active manifest.

## Value

A lazy dbplyr table.
