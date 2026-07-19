# graft

<!-- badges: start -->
[![R-CMD-check](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/JamesHWade/graft/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/graft)
<!-- badges: end -->

graft is an R package for storing schema-defined knowledge in DuckDB. A store
can contain domain records, claims about those records, sources, and evidence
that links a claim to a specific source location.

A LinkML schema defines the record classes, fields, identifiers, validation
rules, and graph projections. `kg_compile_schema()` resolves that schema into a
`.graft.json` manifest, which graft uses to initialize and query the database.

Start with the [getting started
guide](https://jameshwade.github.io/graft/articles/getting-started.html) to
build a small store and query its records, claims, and evidence.

Python and `linkml-runtime` are required only to compile a schema. Loading and
inspecting a committed manifest is pure R/JSON. The manifest drives DuckDB
storage, validation, identity, retrieval, and graph projections:

```r
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

Functions that collect records or graph results require a limit and report
whether the result was truncated. `kg_tools()` exposes six of the same
read-only queries as ellmer tools:

```r
chat <- ellmer::chat_anthropic()
chat$set_tools(kg_tools(store))
```

## Tempest integration

Tempest domain objects are mapped to concrete Graft record data frames before
handoff. `kg_ingest_tempest_records()` commits those records atomically and
uses the run ID, or `<run_id>:<stage>`, as the idempotency boundary:

```r
result <- kg_ingest_tempest_records(
  store,
  run_id = "tempest-run-42",
  records = mapped_records,
  stage = "search"
)
```

Typed Tempest deliverable persistence is not currently available. Tempest's
artifact-store write callback supplies a `TempestArtifact` without the
`TempestDeliverableSpec` needed for validated reconstruction, and Tempest does
not yet export a complete durable envelope/restore contract.
`tempest_artifact_store_graft()` therefore fails with an actionable classed
condition instead of storing an opaque R serialization or claiming that typed
persistence works.
