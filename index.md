# graft

A knowledge layer for R workflows

## Keep workflow results consistent, connected, and traceable.

Define what your domain records mean once. graft applies that contract
whenever R workflows write or retrieve data—reconciling identities
across runs, validating relationships, preserving claims with exact
evidence, and exposing predictable queries to analysts and AI tools.

[Get
started](https://jameshwade.github.io/graft/articles/getting-started.md)
[View source](https://github.com/JamesHWade/graft)

Stable identity Schema-checked ingestion Claims and evidence Bounded
retrieval

## When tidy tables are not enough

An R workflow can produce tidy tables and still leave hard questions
scattered across scripts. Is this the same material as last run? Which
source supports this claim? Is a relationship stated or inferred? What
may an automated tool retrieve? graft makes those decisions explicit,
versioned, and enforceable.

01

### Recognize the same thing

Use declared identifiers and workflow-specific keys to match new results
to existing records.

02

### Keep claims traceable

Preserve what a source said, where it said it, and whether the stored
evidence supports or challenges the claim.

03

### Control retrieval

Give R code schema-aware query helpers and AI tools structured access
without arbitrary SQL or invented relationships.

## What graft does

01 **Define the contract** Describe records, identifiers, validation,
and relationships.

02 **Write workflow results** Ingest related data frames as one producer
batch.

03 **Reconcile and validate** Reuse identities, check references, and
record lineage.

04 **Retrieve with context** Inspect records together with claims,
evidence, and relationships.

graft uses an ordinary LinkML schema as the source contract and compiles
it into a portable `.graft.json` manifest. At runtime, that manifest
drives validation, identity, storage, and retrieval. The current backend
is embedded DuckDB, so stores are local and remain available through
familiar DBI and dbplyr workflows.

## From a data frame to a durable record

``` r

library(graft)

manifest <- system.file(
  "extdata",
  "materials.graft.json",
  package = "graft"
)
schema <- kg_schema(manifest)
store <- kg_connect_duckdb(schema, ":memory:")
kg_init(store)

kg_ingest(
  store,
  kg_batch(
    producer = "materials-pipeline",
    source_run_id = "run-42",
    idempotency_key = "lldpe-v1"
  ),
  list(Material = data.frame(
    preferred_name = "Linear low-density polyethylene",
    cas_number = "9002-88-4"
  ))
)

material_id <- kg_lookup(store, "cas", "CAS: 9002-88-4")$record_id[[1]]
kg_get(store, material_id)
```

Reuse the same producer and idempotency key, and graft recognizes the
write as a replay rather than a new observation. The getting-started
guide continues from this foundation by adding a source-backed claim and
retrieving the exact evidence stored with it.

Python and `linkml-runtime` are needed only to compile a schema. After
compilation, graft loads committed manifests and operates stores
entirely in R.

## Query interfaces

### Analysts and applications

[`kg_records()`](https://jameshwade.github.io/graft/reference/kg_records.md)
returns a lazy dbplyr table.
[`kg_find()`](https://jameshwade.github.io/graft/reference/kg_find.md),
[`kg_get()`](https://jameshwade.github.io/graft/reference/kg_get.md),
and the graph helpers return collected results with explicit limits and
schema context.

### AI tools

[`kg_tools()`](https://jameshwade.github.io/graft/reference/kg_tools.md)
creates six read-only tools for one store. The tools accept structured
arguments rather than SQL and report truncation state and the active
schema digest.

## Next steps

The getting-started guide builds a small materials store, then adds
records, a claim, a source, and evidence.

[Read getting
started](https://jameshwade.github.io/graft/articles/getting-started.md)
[See examples](https://jameshwade.github.io/graft/articles/examples.md)
[Browse
functions](https://jameshwade.github.io/graft/reference/index.md)
