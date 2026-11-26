# graft <img src="man/figures/logo.png" align="right" height="138" alt="Graft logo" />

<!-- badges: start -->
[![R-CMD-check](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/JamesHWade/graft/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/graft)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

**Reviewed project memory and persistent artifacts for R apps and agents.**

graft saves findings, metric definitions, reports, and figures alongside the
exact evidence behind them. Your application records when a person accepts,
corrects, or withdraws a result, and exposes read-only recall to
[ellmer](https://ellmer.tidyverse.org/),
[shinychat](https://posit-dev.github.io/shinychat/),
[deputy](https://jameshwade.github.io/deputy/), or
[mcptools](https://posit-dev.github.io/mcptools/) so later conversations use
what your team actually reviewed.

## Installation

```r
# install.packages("pak")
pak::pak("JamesHWade/graft")
```

## Quick start

```r
library(graft)

store <- graft_store("analysis-memory", create = TRUE)

source <- graft_save(store, "Handbook: use a 30-day activity window.", "handbook")
note <- graft_save(
  store,
  "An active customer has a paid account and activity in the past 30 days.",
  id = "metric:active-customer",
  dependencies = source
)

decision <- graft_accept(
  store,
  note,
  stream = "metric:active-customer",
  expected = NULL,
  key = "review-1",
  actor = "analyst",
  reason = "Matches the metrics handbook",
  purpose = "project-assistance"
)

# Reopen in a later session and recall the accepted note
recalled <- graft_recall(
  graft_store("analysis-memory"),
  stream = "metric:active-customer",
  purpose = "project-assistance",
  eligible = TRUE
)
recalled@roots[[1L]]@data
```

Saving a correction under the same ID creates a new immutable revision. Earlier
revisions remain readable by exact reference with `graft_read()`, while
`graft_recall()` checks current acceptance, purpose, and host eligibility.

## Try the runnable Shiny example

The package ships with a small Shiny app pairing a reviewable project notebook
with a shinychat conversation. It runs locally with real graft storage and
scripted replies—no API key required:

```r
pak::pak(c("JamesHWade/graft", "ellmer", "shinychat", "shiny", "bslib"))
Sys.setenv(GRAFT_DEMO_STORE = file.path(getwd(), "project-memory"))
shiny::runApp(system.file("examples", "project-memory", package = "graft"))
```

1. Review and save the proposed definition and source.
2. Ask *"How do we count an active customer?"*
3. Start a **New conversation** and ask again—the saved knowledge persists.
4. Change the definition to 60 days, review the correction, and ask in a fresh
   chat.
5. Stop and restart the app with the same store path to reopen the notebook.

Configure `OPENAI_API_KEY` and set `Sys.setenv(GRAFT_DEMO_LIVE = "true")` to
run with a live ellmer agent. See the
[example source](inst/examples/project-memory/) and the
[getting-started guide](https://jameshwade.github.io/graft/articles/getting-started.html).

## How graft fits in the ellmer ecosystem

| Package | What it owns | How it pairs with graft |
|---|---|---|
| **ellmer** & **shinychat** | Model calls, tools, and chat UI | Register `graft_tool()` so chats consult reviewed memory with tool cards |
| **ragnar** | Similarity search (RAG) | **ragnar finds, graft verifies**: search broadly with ragnar, recall only accepted revisions via graft |
| **commons** & **data-dict** | Trusted data analysis & data contracts | Commons runs live queries; graft preserves reviewed outputs and pinned shared vocabularies |
| **deputy** | Governed agent runtime | Run `graft_tool()` in read-only/plan modes and capture drafts via `TrustedResults()` for human review |
| **mcptools** | Model Context Protocol | Serve `graft_tool()` to Claude Code, Positron, or Posit Assistant |
| **vitals** & **scans** | LLM evals & trajectory analysis | Score recall accuracy with `vitals`; inspect runs and promotion candidates with `scans` |

## Documentation

- [Give a chat agent project memory](https://jameshwade.github.io/graft/articles/getting-started.html) — ellmer, shinychat, deputy, and mcptools walkthrough
- [Persistent artifacts and review history](https://jameshwade.github.io/graft/articles/persistent-artifacts.html) — selections, decision streams, and PostgreSQL scopes
- [Shared concepts across workflows](https://jameshwade.github.io/graft/articles/shared-vocabulary.html) — publish and reuse pinned data-dict vocabularies
- [Evaluate agent recall](https://jameshwade.github.io/graft/articles/recall-evaluation.html) — credential-free `vitals::Task` for memory recall
- [Graft in the ellmer ecosystem](https://jameshwade.github.io/graft/articles/architecture.html) — ownership boundaries and persistence model

## Scope and storage

Local stores use trusted files on disk with per-stream advisory file locks for
multi-process decision recording (requires a file system that honors advisory
locks). For multi-user or transactional databases, `graft_store_postgres()`
persists artifacts inside a host-owned PostgreSQL transaction isolated by a
host-selected scope key. In both cases, your application owns authentication,
authorization, and approval policy.
