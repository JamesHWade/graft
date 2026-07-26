# Materials Market Radar

Materials Market Radar is an installable market and competitive intelligence
example for a multi-business materials portfolio. It turns bounded public
signals into a governed decision loop:

```text
observe -> reconcile -> brief -> propose -> review -> accept -> learn
```

The example is intentionally a decision system rather than a news feed. Every
signal is attached to businesses, competitors, downstream markets, source
documents, an evidence-backed implication, and one accountable action.

- **dsprrr** provides one analyst contract with deterministic and model-backed
  implementations.
- **Tempest** owns the typed briefing, change set, run events, and approval
  pause.
- **Graft** stores the portfolio taxonomy and only approved observations,
  assessments, actions, source lineage, and run records.
- **Shiny and bslib** provide the morning brief, portfolio map, review inbox,
  knowledge ledger, and workflow audit.

The application owns its schema, sources, routing, schedule, model choice,
tool registry, and side effects. It adds no market-specific Graft or Tempest
API.

## Run it

From a development checkout, load the current Tempest development version
before Graft:

```r
devtools::load_all("../tempest")
devtools::load_all(".")
shiny::runApp("inst/examples/market-intelligence/app")
```

The default path is provider-free. Select **Use configured model** before a
scan to use the same dsprrr signature with the model configured through
Tempest:

```r
options(tempest.chat = "openai/gpt-5-mini")
```

For role-specific or internal-provider configuration:

```r
options(
  graft.market.tempest_config = tempest::tempest_config(
    models = list(
      coordinator = "anthropic/claude-sonnet-4-20250514",
      writer = "openai/gpt-5-mini"
    )
  )
)
```

`tempest.chat` may also be a cloneable ellmer `Chat`. An explicit
`graft.market.tempest_config` wins over the ambient option, and an explicit
Tempest `chat_fn` remains the escape hatch for a custom internal provider.
Each app session deep-clones a configured chat template before adding the
market-analyst prompt.

From an installed package:

```r
example <- system.file(
  "examples",
  "market-intelligence",
  package = "graft",
  mustWork = TRUE
)
shiny::runApp(file.path(example, "app"))
```

Run the noninteractive two-scan walkthrough with:

```r
source("inst/examples/market-intelligence/run-demo.R")
```

## What the walkthrough proves

The first signal bundle contains the July 2026 quarterly-results evidence used
to distinguish price-led polymer performance from downstream volume signals.
The provider-free analyst identifies data-center and electrification materials
as a cross-business watch theme.

1. Tempest produces a source-linked Markdown brief and a structured assessment
   package.
2. The brief is readable immediately, but the assessment package pauses at
   `awaiting_approval`.
3. Before approval, Graft contains zero observations, assessments, actions, or
   monitor runs from the scan.
4. Approval resumes the same run and atomically commits the reviewed sources,
   observations, assessment, action, approval lineage, and planner path.
5. The second competitor-strategy scan receives that accepted assessment as
   explicit context and reports `memory_used = TRUE`.
6. Rejection resolves a run without adding the proposed interpretation to
   Graft.

This makes the differentiated claim observable: governed organizational memory
changes a later market readout, and the application can show exactly why.

## Add analyst tools

Register any number of ellmer tools for model-backed scans:

```r
market_database <- ellmer::tool(
  function(query) search_internal_market_database(query),
  "Search the approved internal market database.",
  arguments = list(
    query = ellmer::type_string("A bounded materials-market query.")
  ),
  name = "search_market_database"
)

options(graft.market.tools = list(market_database))
```

A provider function receives the current `worker` reactive, Shiny `input`,
`session`, and `example_dir`:

```r
options(
  graft.market.tools = function(context) {
    list(my_source_tool(context$session))
  }
)
```

The optional [btw](https://github.com/posit-dev/btw) integration supplies a
broad R-aware tool belt:

```r
install.packages("btw")
options(graft.market.btw = "read_only")
```

The read-only profile admits documentation, environment description, file
reading and search, Git inspection, session information, skills, CRAN, IDE
context, and web reading. It excludes file edits, arbitrary R execution,
package operations, Git mutations, GitHub API access, and subagents. Select
specific btw groups or tools when a smaller registry is appropriate:

```r
options(graft.market.btw = c("docs", "env", "web"))
```

`options(graft.market.btw = "all")` exposes all locally available btw tools and
is appropriate only in a trusted single-user host. Directly registered
mutating tools do not inherit the assessment approval boundary. Production
writes to CRM, Planview, email, or collaboration systems should be separate
typed Tempest capabilities whose exact targets are shown before execution.
Duplicate tool names are rejected.

## Production boundary

The committed corpus is a bounded public-source fixture, not a claim to
complete market coverage or market-share estimation. A production host would
replace it with authenticated adapters for:

- company and competitor filings, earnings calls, investor presentations, and
  asset announcements;
- trade publications, regulatory filings, patents, job postings, pricing,
  capacity, logistics, and licensed market data;
- approved internal sales, margin, pipeline, customer, technical-service, and
  supply signals; and
- downstream demand indicators for packaging, construction, mobility,
  consumer care, electrification, and data centers.

Raw source snapshots belong in an immutable source store. Deterministic facts
may enter Graft under an explicit policy after validation. Ambiguous entity
matches, assessments, hypotheses, implications, and action proposals require
review. External writes require a second, target-specific approval.

## Layout

- `schema/market-intelligence.linkml.yaml` defines the application-owned
  business, competitor, market, source, observation, assessment, action, and
  run contract.
- `schema/market-intelligence.graft.json` is the committed compiled manifest.
- `corpus/` contains the portfolio taxonomy and two bounded public signal
  bundles.
- `R/planner.R` defines the dsprrr analyst, Tempest model configuration, and
  extensible tool registry.
- `R/workflow.R` defines the typed Tempest briefing and approval lifecycle.
- `R/worker.R` owns session-local DuckDB storage, approval resolution, and
  approved Graft ingestion.
- `app/` contains the responsive bslib decision room.
- `run-demo.R` executes the provider-free before/after walkthrough.
