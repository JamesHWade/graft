# Build a governed materials market radar

A useful market-intelligence system should do more than summarize news.
It should connect a signal to the businesses it affects, the competitors
changing the market, the downstream demand that explains why it matters,
and an owner who can act.

Materials Market Radar is an installable Graft example for that decision
loop:

``` text
observe -> reconcile -> brief -> propose -> review -> accept -> learn
```

It combines a six-business portfolio map, enterprise and specialist
competitor watchlists, and downstream lenses for data centers,
electrification, packaging, construction, and consumer care. A
provider-free two-scan story makes the important product claim testable:
accepted organizational knowledge changes the interpretation of a later
competitor signal.

## Ask portfolio questions, not feed questions

The example organizes monitoring around four connected questions:

1.  **What changed?** Capture a bounded claim, metric, time, and exact
    source.
2.  **Where does it matter?** Link the observation to businesses,
    competitors, and downstream markets.
3.  **What does it mean now?** Reconcile the new evidence with accepted
    assessments rather than treating every alert as a fresh story.
4.  **What should happen next?** Propose one material, owner-assigned
    action with a due date and keep it pending until reviewed.

This model separates enterprise competitors, such as LyondellBasell,
INEOS, BASF, and SABIC, from specialists that matter in a narrower
business cluster. It also prevents a common analytical error: treating
price-led segment results as proof of downstream volume growth.

The reference corpus is deliberately bounded. It demonstrates the
contract; it is not a complete market-share model or a substitute for
licensed market data.

## Give each package one responsibility

| Component | Responsibility |
|----|----|
| **Shiny and bslib** | Responsive morning brief, portfolio map, review inbox, accepted-knowledge ledger, and audit view |
| **dsprrr** | One analyst signature with deterministic and model-backed implementations |
| **Tempest** | Typed Markdown briefing, structured change set, ordered run events, and approval pause |
| **Graft** | Schema-checked storage for accepted sources, observations, assessments, actions, and monitor-run lineage |

The application owns the market schema, source adapters, routing, model
selection, tool registry, schedule, and side effects. Neither Graft nor
Tempest gains a market-specific public function.

## Run the complete loop without a model key

From an installed package:

``` r

library(graft)

radar <- system.file(
  "examples",
  "market-intelligence",
  package = "graft",
  mustWork = TRUE
)

shiny::runApp(file.path(radar, "app"))
```

The five views expose separate parts of the contract:

- **Briefing** shows the current evidence packet and source-linked
  narrative.
- **Portfolio map** shows enterprise overlap, business-specific
  competitors, and downstream lenses.
- **Review** shows the exact assessment and accountable action proposed
  for durable storage.
- **Knowledge** contains only approved assessments and open actions.
- **Audit** separates Tempest workflow events from accepted Graft runs.

The first scan identifies data-center and electrification materials as a
cross-business watch theme while keeping price-led plastics performance
separate from volume evidence. Approval resumes the same Tempest run and
atomically records the reviewed sources, observations, assessment,
action, and planner path.

The second scan reconciles LyondellBasell and BASF portfolio moves with
that accepted thesis. Its result reports that memory was used and
explains how the new evidence reinforces or qualifies the earlier
assessment. Rejecting this second proposal resolves the run without
adding its interpretation to Graft.

From a development checkout:

``` r

devtools::load_all("../tempest")
devtools::load_all(".")
shiny::runApp("inst/examples/market-intelligence/app")
```

The same proof runs without Shiny:

``` r

source("inst/examples/market-intelligence/run-demo.R")
```

## Treat approval as the knowledge boundary

The briefing is readable before approval, but its interpretation is not
yet organizational knowledge.

| Decision state | Tempest | Graft |
|----|----|----|
| Awaiting approval | Briefing and change set are inspectable | No scan observations, assessment, action, or monitor run |
| Rejected | Run records the rejection | Proposed interpretation remains absent |
| Approved | The same run resumes and completes | Sources, observations, assessment, action, approval lineage, and planner path are committed |

This boundary is especially important when the model can use broad
research tools. Reading more sources does not grant authority to publish
an internal thesis, create a CRM task, or contact a customer. Each
external write should be a separate typed capability with its target and
payload shown before execution.

## Configure the analyst through Tempest

The easiest model configuration remains Tempest’s ambient option:

``` r

options(tempest.chat = "openai/gpt-5-mini")
shiny::runApp(file.path(radar, "app"))
```

Use an explicit configuration for role-specific models or an internal
provider:

``` r

options(
  graft.market.tempest_config = tempest::tempest_config(
    models = list(
      coordinator = "anthropic/claude-sonnet-4-20250514",
      writer = "openai/gpt-5-mini"
    )
  )
)
```

An explicit market configuration wins over `tempest.chat`, and Tempest’s
`chat_fn` remains the escape hatch for a custom ellmer client. A
configured chat template is deep-cloned for each app session before the
market-analyst prompt and tools are added.

## Extend the analyst tool belt

Register any number of ellmer tools for model-backed scans:

``` r

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

A provider function receives the current worker, Shiny input, session,
and example directory, so it can build session-aware source tools.

The optional [posit-dev/btw](https://github.com/posit-dev/btw)
integration provides a broad R-aware tool collection:

``` r

install.packages("btw")
options(graft.market.btw = "read_only")
```

The read-only profile admits documentation, environment description,
file reading and search, Git inspection, session information, skills,
CRAN, IDE context, and web reading. It excludes file edits, arbitrary R
execution, package operations, Git mutations, GitHub API access, and
subagents. Use a smaller set when appropriate:

``` r

options(graft.market.btw = c("docs", "env", "web"))
```

Duplicate tool names are rejected. `options(graft.market.btw = "all")`
exposes all locally available btw tools and is appropriate only in a
trusted, single-user host.

## Replace the fixture with production sources

A production radar can preserve the same contract while replacing the
local JSON bundles with authenticated adapters for:

- company and competitor filings, calls, presentations, asset
  announcements, patents, pricing, capacity, logistics, and licensed
  market data;
- approved sales, margin, pipeline, customer, technical-service, and
  supply signals; and
- downstream indicators for packaging, construction, mobility, consumer
  care, electrification, and data centers.

Raw source snapshots belong in an immutable source store. Deterministic
facts may enter Graft under an explicit validation policy. Ambiguous
entity matches, assessments, implications, and proposed actions should
remain reviewable.

The complete implementation is in the [market-intelligence example
directory](https://github.com/JamesHWade/graft/tree/main/inst/examples/market-intelligence).
Continue with [Build a governed local
Coworker](https://jameshwade.github.io/graft/articles/coworker.md) for
the broader agent work-surface pattern, or [Govern knowledge
changes](https://jameshwade.github.io/graft/articles/knowledge-change-control.md)
for revision history and reviewed schema evolution.
