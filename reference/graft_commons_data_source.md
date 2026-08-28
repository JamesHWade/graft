# Create a detached Commons data source

`graft_commons_data_source()` materializes accepted public tables and
definitions at one immutable boundary, then loads exact typed values and
a generated data-dict dictionary into
[`commons::data_source()`](https://posit-dev.github.io/commons/reference/data_source.html).
The returned Commons source owns its DuckDB connection and does not
share Graft's backend.

## Usage

``` r
graft_commons_data_source(source, classes = NULL)
```

## Arguments

- source:

  An initialized `GraftStore` or immutable `GraftView`.

- classes:

  Optional public class names to materialize. The default is every
  public class in the active schema.

## Value

A detached `commons_data_source` object.
