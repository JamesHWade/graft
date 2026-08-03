# graft

<!-- badges: start -->
[![R-CMD-check](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/JamesHWade/graft/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/graft)
<!-- badges: end -->

graft keeps records produced by R workflows consistent, connected, and
traceable across runs. It reconciles identities, validates related data as they
are written, preserves claims with exact source evidence, and provides bounded
retrieval for analysts, applications, and AI tools.

Graft is OKF-first and Graft-backed. People and agents work with a plain
Markdown [Open Knowledge
Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf)
(OKF) directory. A compiled LinkML contract and DuckDB revision ledger remain
underneath to enforce identity, validation, history, and approval.

[![Architecture diagram with Graft at the center. LinkML supplies the domain contract, OKF provides the readable working surface, and DuckDB holds accepted revisions and provenance.](man/figures/okf-linkml-duckdb-system.svg)](man/figures/okf-linkml-duckdb-system.svg)

Start with the [getting started
guide](https://jameshwade.github.io/graft/articles/getting-started.html) to
build a small store and query its records, claims, and evidence.
The [LinkML schema
article](https://jameshwade.github.io/graft/articles/linkml-schema.html) starts
from an ordinary schema with no graft-specific imports or annotations.
The [examples
page](https://jameshwade.github.io/graft/articles/examples.html) applies the
same workflow to chemistry and environmental biology.

The current storage backend is embedded DuckDB, which keeps a graft store local
and available through DBI and dbplyr. Python and `linkml-runtime` are required
only to compile a schema; loading a committed manifest and using a store run in
R:

```r
library(graft)

manifest <- system.file(
  "extdata",
  "personinfo.graft.json",
  package = "graft"
)
schema <- kg_schema(manifest)
store <- kg_connect_duckdb(schema, "knowledge.duckdb")
kg_init(store)

kg_ingest(
  store,
  kg_batch(
    producer = "directory-import",
    source_run_id = "run-42",
    idempotency_key = "daily-planet-v1"
  ),
  list(
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
)

kg_get(store, "person:clark-kent")

# Creates the managed sibling directory knowledge.okf
kg_sync_okf(store)
kg_okf_status(store)
```

The batch is atomic, its relationship is validated, and reusing the same
producer and idempotency key does not create another observation. Functions
that collect records or graph results require a limit and report whether the
result was truncated. `kg_tools()` exposes seven read-only ellmer tools,
including progressive access to the current accepted OKF working tree:

```r
chat <- ellmer::chat_anthropic()
chat$set_tools(kg_tools(store))
```

## Work in open knowledge

A file-backed `knowledge.duckdb` store manages the sibling `knowledge.okf`
directory by default. Synchronization is explicit so a filesystem failure
cannot be mistaken for a failed database transaction:

```r
bundle <- kg_sync_okf(store)
bundle

kg_okf_context(store)
kg_okf_context(
  store,
  query = "Daily Planet",
  types = "Organization"
)
```

Each concept remains readable Markdown, object references become links, and
source records become OKF source citations. The `graft` frontmatter extension
retains exact record, revision, batch, and schema identity. If a person or
agent edits the structured `graft.record` mapping, the edit is still only a
proposal:

```r
plan <- kg_plan_okf_import(store)
plan

result <- kg_apply_okf_import(
  store,
  plan,
  kg_batch(
    producer = "human:reviewer",
    idempotency_key = "approved-okf-edit-1"
  )
)
```

Planning is read-only. Application revalidates the plan, bundle, store,
schema, and accepted batch before committing through the ordinary Graft write
path. Historical or selected snapshots remain available through
`kg_export_okf()`. Read [Work with open knowledge by
default](https://jameshwade.github.io/graft/articles/open-knowledge-format.html)
for managed synchronization, agent retrieval, proposal review, historical
export.
