# graft

graft is a table-native knowledge layer for R. It compiles a LinkML
semantic contract into a portable JSON manifest that describes concrete
record classes, relational tables, identity policies, validation
invariants, and graph projections.

Python and `linkml-runtime` are required only to compile a schema.
Loading and inspecting a committed manifest is pure R/JSON. The manifest
drives DuckDB storage, validation, identity, retrieval, and graph
projections:

``` r

library(graft)

schema <- kg_schema("tempest-artifacts.graft.json")
store <- kg_connect_duckdb(schema, "knowledge.duckdb")
kg_init(store)

kg_classes(schema)
kg_slots(schema, "Claim")

matches <- kg_find(store, "LLDPE crystallinity", class = "Entity")
record <- kg_get(store, matches$id[[1]])
graph <- kg_neighbors(
  store,
  record$id,
  projection = "combined",
  hops = 2
)
```

All collected retrieval and graph operations are bounded and report
truncation. For model-assisted retrieval,
[`kg_tools()`](https://jameshwade.github.io/graft/reference/kg_tools.md)
exposes six read-only structured tools over the same bounded APIs:

``` r

chat <- ellmer::chat_anthropic()
chat$set_tools(kg_tools(store))
```

## Tempest integration

Tempest domain objects are mapped to concrete Graft record data frames
before handoff.
[`kg_ingest_tempest_records()`](https://jameshwade.github.io/graft/reference/kg_ingest_tempest_records.md)
commits those records atomically and uses the run ID, or
`<run_id>:<stage>`, as the idempotency boundary:

``` r

result <- kg_ingest_tempest_records(
  store,
  run_id = "tempest-run-42",
  records = mapped_records,
  stage = "search"
)
```

Typed Tempest deliverable persistence is not currently available.
Tempest’s artifact-store write callback supplies a `TempestArtifact`
without the `TempestDeliverableSpec` needed for validated
reconstruction, and Tempest does not yet export a complete durable
envelope/restore contract.
[`tempest_artifact_store_graft()`](https://jameshwade.github.io/graft/reference/tempest_artifact_store_graft.md)
therefore fails with an actionable classed condition instead of storing
an opaque R serialization or claiming that typed persistence works.
