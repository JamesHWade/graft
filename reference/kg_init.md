# Initialize or verify a graft store

Initialization creates client tables from the compiled manifest plus the
five package-owned metadata tables and three generated graph views. It
is atomic and idempotent. Existing stores must have the same structural
digest as the active schema.

## Usage

``` r
kg_init(store)
```

## Arguments

- store:

  A `kg_store` object.

## Value

`store`, invisibly.
