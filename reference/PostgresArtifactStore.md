# PostgreSQL artifact store

PostgreSQL artifact store

## Usage

``` r
PostgresArtifactStore(
  max_bytes = integer(0),
  max_revision_bytes = integer(0),
  connection = NULL,
  scope = character(0)
)
```

## Arguments

- max_bytes:

  Maximum payload bytes for one artifact and the complete dependency set
  it references.

- max_revision_bytes:

  Maximum encoded revision metadata bytes.

- connection:

  An open transaction-scoped PostgreSQL connection.

- scope:

  Host-selected scope key.
