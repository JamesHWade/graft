# Plan changes from an edited Open Knowledge Format working tree

Planning reads the editable `graft.record` mappings in a complete
managed bundle through a stable filesystem snapshot, compares them with
current accepted revisions, and validates proposed inserts and updates
against the active LinkML-derived manifest. It does not mutate the
store. Removing concept files is intentionally unsupported.

## Usage

``` r
kg_plan_okf_import(store, path = NULL)
```

## Arguments

- store:

  An initialized `kg_store`.

- path:

  Optional edited bundle directory. The default uses the managed OKF
  directory.

## Value

A deterministic, tamper-evident `kg_okf_import_plan`.

## Details

The resulting plan is bound to the store identity, exact accepted batch,
active schema, and edited bundle digest. This makes it suitable for an
explicit human or host-policy approval step.
