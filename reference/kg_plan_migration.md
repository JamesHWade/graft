# Plan an additive schema migration

Creates a deterministic, serializable plan bound to the initialized
store's identity, format, and exact active schema. Planning is
read-only. The first migration version supports compatible schema
activations, new concrete classes, nullable scalar slots, generated
relation tables, and enum additions. The plan includes deterministic
schema-change details and physical operations so schema-only changes
remain reviewable.

## Usage

``` r
kg_plan_migration(store, new_schema)
```

## Arguments

- store:

  An initialized `kg_store`.

- new_schema:

  A `kg_schema` object or manifest path.

## Value

A deterministic, tamper-evident `kg_migration_plan` object. Its digest
is revalidated before application.
