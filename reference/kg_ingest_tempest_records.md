# Ingest records mapped from one Tempest run

This is the durable Tempest-to-Graft knowledge handoff. Tempest maps its
domain objects to concrete Graft record data frames before calling this
function. The run identifier is both producer lineage and the default
idempotency key. A stage uses `<run_id>:<stage>`, allowing independently
replayable stage commits.

## Usage

``` r
kg_ingest_tempest_records(
  store,
  run_id,
  records,
  stage = NULL,
  producer_version = NULL
)
```

## Arguments

- store:

  An initialized, writable `kg_store`.

- run_id:

  One stable Tempest run identifier.

- records:

  A named list of mapped concrete-class data frames accepted by
  [`kg_ingest()`](https://jameshwade.github.io/graft/reference/kg_ingest.md).

- stage:

  Optional stable stage identifier, such as `"search"` or
  `"synthesize"`.

- producer_version:

  Optional Tempest producer version.

## Value

A `kg_ingest_result`. Replaying the same run and stage returns the
original committed result with `replay = TRUE` and signals
`graft_batch_replay`.

## Details

This function is independent of Tempest's typed deliverable
artifact-store adapter.
