# Open and initialize a Graft store

`graft_open()` creates a blank writable DuckDB store when `path` does
not exist, or verifies an existing store in one call. No pre-existing
database is required. Graft closes connections it creates;
caller-supplied connections remain owned by the caller. Definitions in a
data-dict contract seed a new store, and a failed initial seed is
retried on the next writable open. Reopening an initialized store never
accepts changed definitions; submit those changes through
[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
and
[`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md).

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
