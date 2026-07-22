# Govern knowledge changes

A current-state table can answer “what do we believe now?” It cannot, on
its own, answer the questions that make the result dependable:

- What changed, and which workflow run changed it?
- What had the store accepted before that change?
- Which exact schema governed each revision?
- Can the contract evolve without silently changing stored knowledge?

graft keeps the typed tables used for ordinary queries and an
append-only revision ledger used for these questions. Ingestion batches
connect each accepted change to its producer, schema, and commit order.
Schema evolution is a separate plan-review-apply operation.

This guide runs the complete loop with two small contract versions
included in the package. Both use store format 2 and are already
compiled, so the walkthrough does not require Python.

## Create a store with contract v1

``` r

library(graft)

manifest_v1 <- system.file(
  "extdata",
  "change-control-v1.graft.json",
  package = "graft"
)
schema_v1 <- kg_schema(manifest_v1)
store <- kg_connect_duckdb(schema_v1, ":memory:")
#> duckdb is keeping downloaded extensions in a temporary directory:
#> ℹ /tmp/Rtmphnc7wQ/duckdb/extensions
#> This is removed when the R session ends, so extensions are re-downloaded each session.
#> ℹ To keep them, point `options(duckdb.extension_directory =)` or the `DUCKDB_EXTENSION_DIRECTORY` environment variable at a permanent path.
kg_init(store)
```

The first batch records an initiative at the point it enters concept
review. The producer-side run identifier and idempotency key make that
provenance and replay boundary explicit.

``` r

baseline <- kg_write(
  store,
  kg_batch(
    producer = "portfolio-review",
    source_run_id = "daily-brief-001",
    idempotency_key = "firefly-v1"
  ),
  class = "Initiative",
  records = data.frame(
    preferred_name = "Project Firefly",
    status = "concept review",
    portfolio_id = "PF-001"
  )
)

initiative_id <- kg_lookup(
  store,
  namespace = "portfolio",
  value = "PF-001"
)$record_id[[1]]
```

A later batch accepts a new status for the same schema-declared
identity:

``` r

approved <- kg_write(
  store,
  kg_batch(
    producer = "portfolio-review",
    source_run_id = "daily-brief-002",
    idempotency_key = "firefly-v2"
  ),
  class = "Initiative",
  records = data.frame(
    preferred_name = "Project Firefly",
    status = "prototype approved",
    portfolio_id = "PF-001"
  )
)
```

The typed table remains the convenient current-state projection:

``` r

kg_records(store, "Initiative") |>
  dplyr::select(preferred_name, status, portfolio_id) |>
  dplyr::collect()
#> # A tibble: 1 × 3
#>   preferred_name  status             portfolio_id
#>   <chr>           <chr>              <chr>       
#> 1 Project Firefly prototype approved PF-001
```

## Inspect batches and changes

[`kg_batches()`](https://jameshwade.github.io/graft/reference/kg_batches.md)
returns committed workflow batches in newest-first commit order. Its
filters and result limits make it suitable for routine status views
rather than an unbounded audit-table dump.

``` r

kg_batches(store)[
  c("commit_order", "producer", "source_run_id", "status")
]
#>   commit_order         producer   source_run_id    status
#> 1            2 portfolio-review daily-brief-002 committed
#> 2            1 portfolio-review daily-brief-001 committed
```

[`kg_changes()`](https://jameshwade.github.io/graft/reference/kg_changes.md)
returns accepted inserts and updates. Each row identifies the batch and
schema build that governed the revision. Parsed records and changed
field names are exposed as list-columns; raw ledger payloads and content
digests are not.

``` r

kg_changes(store, record_id = initiative_id)[
  c(
    "commit_order",
    "revision_number",
    "operation",
    "changed_fields",
    "batch_id",
    "schema_build_digest"
  )
]
#>   commit_order revision_number operation changed_fields
#> 1            2               2    update         status
#> 2            1               1    insert   id, labe....
#>                           batch_id
#> 1 graft:01KY4Q7DXTQP8ZR98JRJEWGEYP
#> 2 graft:01KY4Q7DMRR1Z70V06BN89156B
#>                                                       schema_build_digest
#> 1 sha256:609ef168a26e8a9f1c1c2b52f97090d3beed23be57e5348b2b226038eda9673a
#> 2 sha256:609ef168a26e8a9f1c1c2b52f97090d3beed23be57e5348b2b226038eda9673a
```

[`kg_history()`](https://jameshwade.github.io/graft/reference/kg_history.md)
narrows the same ledger to one stable record:

``` r

kg_history(store, initiative_id)[
  c("revision_number", "operation", "changed_fields", "recorded_at")
]
#>   revision_number operation changed_fields         recorded_at
#> 1               2    update         status 2026-07-22 10:51:30
#> 2               1    insert   id, labe.... 2026-07-22 10:51:29
```

## Recover state at a commit boundary

Pass a committed batch ID to recover what Graft had accepted when that
batch completed. A scalar `POSIXt` value is also supported; Graft first
resolves it to the latest committed batch order, so equal or imprecise
timestamps do not reorder transactions.

``` r

at_baseline <- kg_history(
  store,
  initiative_id,
  as_of = baseline$batch_id,
  limit = 1
)

at_baseline$record[[1]][
  c("preferred_name", "status", "portfolio_id")
]
#> $preferred_name
#> [1] "Project Firefly"
#> 
#> $status
#> [1] "concept review"
#> 
#> $portfolio_id
#> [1] "PF-001"
```

This is **system time**: when Graft committed a version. It is different
from **domain-valid time**: when a claim is true in the world. Statement
schemas can model domain validity with `valid_from` and `valid_to`;
those remain user-supplied facts. Revision history should not be used as
a substitute for them.

## Plan and review an additive migration

Version 2 of the example contract adds an optional `decision_note`
field. Loading it does not change the store.

``` r

manifest_v2 <- system.file(
  "extdata",
  "change-control-v2.graft.json",
  package = "graft"
)
schema_v2 <- kg_schema(manifest_v2)

kg_schema_diff(schema_v1, schema_v2)
#> <kg_schema_diff> additive
#>   structural: changed
#>   old: sha256:1007cd8b6f043ed8072f0ea172ee0278866b874c6d9c10e3abaabbcd02c8e17a
#>   new: sha256:152894ca9006570a7f545daa715fa91122edd789c5967212c8c3b55ed0ac6710
#>   classes: +0 -0 ~1
#>   slots:   1 change(s)
#>   enums: +0 -0 ~0
#>   tables: +0 -0 ~1
#>   relations: +0 -0 ~0
```

The `additive` classification means this difference is supported by the
current migration path.

Planning is also read-only. The result is deterministic and bound to
this store’s identity, format version, and active schema build. Review
the classification, every classified change, and the declarative
operations before approval.

``` r

plan <- kg_plan_migration(store, schema_v2)
plan
#> <kg_migration_plan> additive graft-migration-8e6d0807d592b997259b340dac24ba913da71444ffdf24759ddc372e931e1700
#>   from:       sha256:609ef168a26e8a9f1c1c2b52f97090d3beed23be57e5348b2b226038eda9673a
#>   to:         sha256:3c830cc687617df734f95cfba51a51ff5b66b9b2369ace6ddfeb7ecb72563124
#>   changes:    2
#>   rules:      nullable_column_added, optional_slot_added
#>   operations: 1
#>   digest:     sha256:8e6d0807d592b997259b340dac24ba913da71444ffdf24759ddc372e931e1700

plan$changes[
  c("path", "object_type", "classification", "rule")
]
#>                                       path  object_type classification
#> 1  /classes/Initiative/slots/decision_note         slot       additive
#> 2 /tables/Initiative/columns/decision_note table_column       additive
#>                    rule
#> 1   optional_slot_added
#> 2 nullable_column_added

lapply(plan$operations, function(operation) {
  list(
    kind = operation$kind,
    table = operation$table,
    column = operation$column$name
  )
})
#> [[1]]
#> [[1]]$kind
#> [1] "add_column"
#> 
#> [[1]]$table
#> [1] "initiative"
#> 
#> [[1]]$column
#> [1] "decision_note"
```

The current migration engine accepts only compatible and supported
additive changes. Required fields, removals, type changes, normalization
changes, custom transformations, and other risky changes are reported
but refused. There is no force flag.

Once the plan has been reviewed, apply that exact object:

``` r

kg_apply_migration(store, plan)

kg_store_info(store)[
  c(
    "store_format_version",
    "required_store_format_version",
    "active_build_digest",
    "history_complete"
  )
]
#> $store_format_version
#> [1] "2.0.0"
#> 
#> $required_store_format_version
#> [1] "2.0.0"
#> 
#> $active_build_digest
#> [1] "sha256:3c830cc687617df734f95cfba51a51ff5b66b9b2369ace6ddfeb7ecb72563124"
#> 
#> $history_complete
#> [1] TRUE
```

Application revalidates the plan and its store preconditions, performs
the DDL, registers and activates the exact target manifest, rebuilds
generated graph views, and records the migration in one transaction.

## Continue writing under the new contract

The same stable initiative can now use the added field. Unchanged fields
do not create false differences merely because the governing schema
changed.

``` r

with_decision <- kg_write(
  store,
  kg_batch(
    producer = "portfolio-review",
    source_run_id = "daily-brief-003",
    idempotency_key = "firefly-v3"
  ),
  class = "Initiative",
  records = data.frame(
    preferred_name = "Project Firefly",
    status = "prototype approved",
    portfolio_id = "PF-001",
    decision_note = "Advance with a reversible prototype."
  )
)

kg_records(store, "Initiative") |>
  dplyr::select(preferred_name, status, decision_note) |>
  dplyr::collect()
#> # A tibble: 1 × 3
#>   preferred_name  status             decision_note                       
#>   <chr>           <chr>              <chr>                               
#> 1 Project Firefly prototype approved Advance with a reversible prototype.
```

History spans both schema builds and applies each historical manifest’s
sensitivity rules when hydrating records:

``` r

kg_changes(store, record_id = initiative_id)[
  c(
    "revision_number",
    "changed_fields",
    "schema_build_digest"
  )
]
#>   revision_number changed_fields
#> 1               3   decision....
#> 2               2         status
#> 3               1   id, labe....
#>                                                       schema_build_digest
#> 1 sha256:3c830cc687617df734f95cfba51a51ff5b66b9b2369ace6ddfeb7ecb72563124
#> 2 sha256:609ef168a26e8a9f1c1c2b52f97090d3beed23be57e5348b2b226038eda9673a
#> 3 sha256:609ef168a26e8a9f1c1c2b52f97090d3beed23be57e5348b2b226038eda9673a
```

## Check integrity

[`kg_check_store()`](https://jameshwade.github.io/graft/reference/kg_check_store.md)
validates relationships among batches, revisions, heads, schema
versions, and current typed tables. Deep checking also re-digests every
revision payload and compares current records with their revision heads.

``` r

check <- kg_check_store(store, deep = TRUE)
check
#> <kg_store_check> valid (deep)
#>   issues:    0
#>   truncated: FALSE
check$issues
#> [1] issue       record_id   class       revision_id batch_id    detail     
#> <0 rows> (or 0-length row.names)
```

Direct writes to client tables are unsupported because they bypass the
ledger. A deep check reports that kind of current-state drift.

## Store format 2 is a clean cutover

Knowledge history begins with store format 2. Stores created by earlier
development versions are rejected with a classed format error; Graft
does not silently upgrade them or run in a legacy mode. During this
pre-release phase, recreate an older development store from its source
records under the current contract.

This boundary keeps every format 2 store honest about the same
guarantee: its accepted current state has complete revision history from
initialization onward.
