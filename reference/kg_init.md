# Initialize or verify a graft store

Initialization creates client tables from the compiled manifest plus the
package-owned metadata tables and three generated graph views. It is
atomic and idempotent. Before any store mutation, Graft verifies the
manifest's declared structural digest and compiler-required physical
type contracts. Existing stores must also be structurally compatible
with the active schema.

## Usage

``` r
kg_init(store)
```

## Arguments

- store:

  A `kg_store` object.

## Value

`store`, invisibly.
