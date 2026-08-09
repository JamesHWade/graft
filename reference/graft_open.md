# Open and initialize a Graft store

`graft_open()` opens a DuckDB store and initializes a blank writable
store or verifies an existing store in one call. Graft closes
connections it creates; caller-supplied connections remain owned by the
caller.

## Usage

``` r
graft_open(
  schema,
  path = ":memory:",
  read_only = FALSE,
  connection = NULL,
  okf = c("managed", "disabled"),
  okf_path = NULL
)
```

## Arguments

- schema:

  A `GraftSchema` object.

- path:

  DuckDB file path, or `":memory:"`.

- read_only:

  Whether the store must prohibit writes.

- connection:

  An optional existing DuckDB DBI connection.

- okf:

  Whether to manage an Open Knowledge Format working tree.

- okf_path:

  Optional managed OKF directory.

## Value

A `GraftStore` S7 object ready for use.
