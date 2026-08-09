# graft

<!-- badges: start -->
[![R-CMD-check](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/JamesHWade/graft/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/graft)
<!-- badges: end -->

graft turns candidate records from R workflows into governed, traceable
knowledge changes. A LinkML or data-dict source compiles into the canonical
Graft domain contract; neither provider becomes the accepted ledger. Every
accepted change carries provenance, passes through a read-only plan, and
becomes an immutable revision through one atomic commit path. Bounded
retrieval, history, and a readable Open Knowledge Format (OKF) working tree are
derived from that accepted ledger.

[![Graft architecture: a LinkML or data-dict contract compiles into Graft; OKF exchanges readable proposals and projections with Graft; Graft commits to and retrieves accepted revisions from DuckDB.](man/figures/okf-linkml-duckdb-system.svg)](man/figures/okf-linkml-duckdb-system.svg)

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

Start with the [10-minute getting started
guide](https://jameshwade.github.io/graft/articles/getting-started.html). Then
read [architecture](https://jameshwade.github.io/graft/articles/architecture.html)
for the authority and projection model, choose a [LinkML
contract](https://jameshwade.github.io/graft/articles/linkml-schema.html) or
[data-dict contract](https://jameshwade.github.io/graft/articles/data-dict-schema.html),
and read [change
control](https://jameshwade.github.io/graft/articles/knowledge-change-control.html)
for plans and commit preconditions, [retrieval and
history](https://jameshwade.github.io/graft/articles/retrieval.html) for the read
surface, and [open
knowledge](https://jameshwade.github.io/graft/articles/open-knowledge-format.html)
for synchronization and file review. [The v0.1
design](https://jameshwade.github.io/graft/articles/v01-design.html) explains the
intentional pre-production cutover.

The data-dict path uses a strict table profile. It accepts trusted
`export-spec` JSON or runs only `export-spec` for YAML, and it validates scalar
foreign keys without turning them into graph traversal edges. YAML source-spec
and resolved JSON export-format versions are tracked separately, and the CLI
executable is re-hashed around export and version discovery. For YAML, graft
captures the source bytes once so preflight, CLI export, and the source/build
fingerprints share one immutable snapshot.

The compiled manifest is public contract metadata. It removes column examples
and ranges, dataset and table origins, and table source locators, while the raw
values still bind source and build digests. Those digests permit equality tests
and offline guessing of low-entropy values; redaction is not a secrecy
boundary. Other retained fields are public and can expose observed or
sensitive values embedded manually. `number(id)` and `list(number(id))` are
rejected in favor of quoted string codes, unsafe JSON numeric tokens fail
closed before lossy conversion, and supported datetime zones have exact input
rules. See the [data-dict
guide](https://jameshwade.github.io/graft/articles/data-dict-schema.html) for the
complete boundary.
