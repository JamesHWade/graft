# Connect to a DuckDB knowledge store

A store combines a compiled graft schema with one DuckDB connection.
When graft creates the connection, graft owns and closes it. A
caller-supplied connection is never closed by graft.

## Usage

``` r
kg_connect_duckdb(
  schema,
  path = ":memory:",
  read_only = FALSE,
  connection = NULL
)
```

## Arguments

- schema:

  A `kg_schema` object or manifest path.

- path:

  DuckDB file path, or `":memory:"`. When supplied together with
  `connection`, it must identify that connection's database.

- read_only:

  Whether the store must prohibit writes.

- connection:

  An optional existing DuckDB DBI connection.

## Value

A `kg_store` object. Call
[`kg_init()`](https://jameshwade.github.io/graft/reference/kg_init.md)
before using a new store.
