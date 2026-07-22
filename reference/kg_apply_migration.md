# Apply a planned additive schema migration

Revalidates the plan and its store preconditions before changing the
store. Supported DDL, schema registration and activation, graph-view
recreation, catalog verification, and migration recording commit in one
DuckDB transaction. The in-process store schema changes only after that
commit.

## Usage

``` r
kg_apply_migration(store, plan)
```

## Arguments

- store:

  An initialized, writable `kg_store`.

- plan:

  A `kg_migration_plan` returned by
  [`kg_plan_migration()`](https://jameshwade.github.io/graft/reference/kg_plan_migration.md).

## Value

`store`, invisibly, with its active schema updated.
