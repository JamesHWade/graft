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
export, and the Tempest handoff.

## Continuous intelligence example

The installable `continuous-intelligence` example combines Graft with
Tempest's generic workflow kernel without adding application-specific package
functions. A frozen three-day corpus drives a passive briefing, an
approval-gated knowledge handoff, a promoted decision workflow, and a
no-material-change day:

```r
example <- system.file(
  "examples",
  "continuous-intelligence",
  package = "graft",
  mustWork = TRUE
)
file.show(file.path(example, "README.md"))
```

Open the interactive Briefing Room to advance the three mornings, inspect
accepted evidence, and act at each approval boundary:

```r
shiny::runApp(file.path(example, "app"))
```

Or take the operator's seat in the console:

```r
source(file.path(example, "walkthrough.R"))
walkthrough <- run_continuous_intelligence_walkthrough()
```

The walkthrough pauses at the knowledge, promotion, and decision boundaries
instead of approving the complete story automatically.

The example keeps scheduling, workflow routing, approval, and writes in the
host application. A contrasting package-maintainer profile exercises the same
host contract with different domain configuration.

## Materials Market Radar example

The installable `market-intelligence` example turns competitor, business, and
downstream-market signals into a governed morning decision loop. Its portfolio
map spans six Dow business clusters, an enterprise and specialist competitor
watchlist, and downstream lenses such as data centers, electrification,
packaging, construction, and consumer care:

```r
example <- system.file(
  "examples",
  "market-intelligence",
  package = "graft",
  mustWork = TRUE
)
shiny::runApp(file.path(example, "app"))
```

The provider-free two-scan walkthrough makes organizational learning visible.
The first scan proposes a cross-business thesis and waits for approval. Only
the accepted assessment, sources, and accountable action enter Graft; the next
competitor scan receives that reviewed history as explicit context. Rejected
interpretations never enter the knowledge ledger.

Read [Build a governed materials market
radar](https://jameshwade.github.io/graft/articles/market-intelligence.html) for
the market model, workflow boundary, production source strategy, model
configuration, and tool-extension recipes.

## Graft Coworker example

The installable `coworker` example is a local, outcome-oriented work surface
inspired by OpenWorker. A shinychat assistant can call a tool that uses a
dsprrr planner and Tempest's typed workflow runtime to prepare a finished
Markdown deliverable. Tempest stops at the file-publication boundary. The
approved file, approval decision, source links, and outcome memory enter Graft
only after the operator approves the exact artifact:

Read [Build a governed local Coworker](https://jameshwade.github.io/graft/articles/coworker.html)
for the architecture, approval contract, model configuration, and
tool-extension recipes.

```r
example <- system.file(
  "examples",
  "coworker",
  package = "graft",
  mustWork = TRUE
)

options(tempest.chat = "openai/gpt-5-mini")
shiny::runApp(file.path(example, "app"))
```

Coworker builds its clients from `tempest_config()`, so a personal
`tempest.chat` default, an explicit role-specific model configuration, or a
custom Tempest `chat_fn` can select the provider without changing the
workflow. Its per-session ellmer tool registry accepts custom tools and can
load a conservative R-aware [btw](https://github.com/posit-dev/btw) tool belt:

```r
options(graft.coworker.btw = "read_only")
shiny::runApp(file.path(example, "app"))
```

Use `options(graft.coworker.tools = list(...))` for additional ellmer tools or
a provider function that constructs session-aware tools. Mutating tools remain
an explicit host decision; the read-only btw profile excludes file and Git
writes so it cannot bypass the Tempest approval card.

The app also includes a provider-free reference request so the complete
prepare, review, approve, publish, and remember loop can be exercised without
an API key. By default its DuckDB store and deliverables persist under
`tools::R_user_dir("graft", "data")`; set `GRAFT_COWORKER_HOME` to choose
another local directory.

This is a vertical slice rather than a desktop-agent replacement. It currently
ships one bounded source bundle and one approval-gated local-file action. The
host boundaries are ready for additional source adapters, connector actions,
schedules, and durable conversation storage without turning those
application concerns into workflow-specific Graft APIs.
