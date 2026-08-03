# graft

<!-- badges: start -->
[![R-CMD-check](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/JamesHWade/graft/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/graft)
<!-- badges: end -->

graft turns records from R workflows into governed, traceable knowledge. A
LinkML schema defines the domain contract. Every accepted change carries
provenance, passes through a reviewable plan, and becomes an immutable revision.
Bounded retrieval, history, and a readable Open Knowledge Format (OKF) working
tree are derived from that accepted ledger.

[![Graft architecture: LinkML supplies the contract, DuckDB stores accepted revisions and provenance, and OKF provides a readable working surface.](man/figures/okf-linkml-duckdb-system.svg)](man/figures/okf-linkml-duckdb-system.svg)

## A complete change

```r
library(graft)

schema <- graft_schema(system.file(
  "extdata",
  "personinfo.graft.json",
  package = "graft"
))
store <- graft_open(schema, "knowledge.duckdb")

provenance <- graft_provenance(
  producer = "directory-import",
  run_id = "run-42",
  idempotency_key = "daily-planet-v1"
)

records <- list(
  Organization = data.frame(
    id = "org:daily-planet",
    name = "Daily Planet"
  ),
  Person = data.frame(
    id = "person:clark-kent",
    full_name = "Clark Kent",
    employed_by = I(list("org:daily-planet"))
  )
)

plan <- graft_plan(store, records, provenance)
plan@changes
plan@issues

if (plan@valid) {
  graft_commit(store, plan)
}

graft_get(store, "person:clark-kent")
graft_find(store, "Clark", class = "Person")
graft_history(store, "person:clark-kent")

graft_sync(store)
graft_status(store)
graft_close(store)
```

Planning is read-only. Committing rechecks the plan against the store and
active contract before accepting all changes atomically. Use `graft_ingest()`
when the same process may plan and commit without a separate review step.

The revision ledger is the authority for accepted record content. Current
records, search results, graph projections, and the OKF working tree are
rebuildable views. Editing OKF therefore creates a proposal: `graft_review()`
turns the edits into an ordinary plan, and `graft_commit()` is still the only
acceptance boundary.

## Public API

The v0.1 surface is deliberately small:

- Contract: `graft_schema()`
- Store lifecycle: `graft_open()`, `graft_close()`
- Provenance and changes: `graft_provenance()`, `graft_plan()`,
  `graft_commit()`, `graft_ingest()`
- Retrieval and history: `graft_get()`, `graft_find()`, `graft_query()`,
  `graft_history()`
- Open knowledge: `graft_sync()`, `graft_status()`, `graft_review()`
- Read-only agent access: `graft_tools()`

Start with the [getting started
guide](https://jameshwade.github.io/graft/articles/getting-started.html). The
[LinkML contract
article](https://jameshwade.github.io/graft/articles/linkml-schema.html)
explains schemas, [change
control](https://jameshwade.github.io/graft/articles/knowledge-change-control.html)
explains plans and history, and the [OKF
article](https://jameshwade.github.io/graft/articles/open-knowledge-format.html)
explains synchronization and review.
