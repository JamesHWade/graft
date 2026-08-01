# Apply an approved Open Knowledge Format import plan

Revalidates the plan, bundle digest, store identity, schema, and
accepted batch before committing its records through
[`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md).
After a successful commit, Graft synchronizes the working tree back to
the canonical accepted projection.

## Usage

``` r
kg_apply_okf_import(store, plan, batch)
```

## Arguments

- store:

  An initialized, writable `kg_store`.

- plan:

  A `kg_okf_import_plan` returned by
  [`kg_plan_okf_import()`](https://jameshwade.github.io/graft/reference/kg_plan_okf_import.md).

- batch:

  A
  [`kg_batch()`](https://jameshwade.github.io/graft/reference/kg_batch.md)
  describing the approved import.

## Value

A `kg_ingest_result`. The synchronized `kg_okf_bundle` is available in
the `okf_bundle` attribute.
