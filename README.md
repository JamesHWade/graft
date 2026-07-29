# graft

<!-- badges: start -->
[![R-CMD-check](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/JamesHWade/graft/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/graft)
<!-- badges: end -->

graft keeps records produced by R workflows consistent, connected, and
traceable across runs. It reconciles identities, validates related data as they
are written, preserves claims with exact source evidence, and provides bounded
retrieval for analysts, applications, and AI tools.

The package puts decisions that often drift across scripts into one versioned
contract: what each record means, how it is identified, which relationships are
valid, and what may be retrieved. The contract begins as an ordinary LinkML
schema and compiles to a portable `.graft.json` manifest.

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
store <- kg_connect_duckdb(schema, ":memory:")
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
```

The batch is atomic, its relationship is validated, and reusing the same
producer and idempotency key does not create another observation. Functions
that collect records or graph results require a limit and report whether the
result was truncated. `kg_tools()` exposes six of the same read-only queries as
ellmer tools:

```r
chat <- ellmer::chat_anthropic()
chat$set_tools(kg_tools(store))
```

## Share accepted knowledge

`kg_export_okf()` projects accepted revisions into an [Open Knowledge
Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf)
v0.2 directory:

```r
bundle <- kg_export_okf(store, "knowledge/okf")
bundle
```

Each concept remains readable Markdown, object references become links, and
source records become OKF source citations. The `graft` frontmatter extension
retains exact record, revision, batch, and schema identity. Exporting an
earlier committed batch or time produces the accepted knowledge boundary that
was visible then:

```r
historical <- kg_export_okf(
  store,
  "knowledge/okf-2026-q2",
  as_of = "batch-2026-q2"
)
```

OKF is the interchange layer, not a replacement for the LinkML-derived
manifest or DuckDB revision ledger. Read [Share accepted knowledge with
OKF](https://jameshwade.github.io/graft/articles/open-knowledge-format.html)
for the mapping, safety boundary, and Tempest handoff.

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
