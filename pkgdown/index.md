# graft

<div class="graft-hero">
<p class="graft-eyebrow">Reviewed project memory for the ellmer ecosystem</p>
<h2 data-toc-skip>Give your next agent<br>the knowledge your team reviewed.</h2>
<p class="graft-hero-copy">
Save findings, metric definitions, and reports with the exact evidence behind
them. Record human review and corrections, then let ellmer, shinychat, deputy,
or MCP clients recall only what is currently accepted.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Get started</a>
<a class="btn btn-outline-secondary" href="articles/architecture.html">See the ecosystem map</a>
</div>
</div>

## How graft works

Chat histories stay trapped in a single session, and similarity indexes return
whatever matches a query—including drafts, superseded definitions, or withdrawn
conclusions. Graft gives your application an explicit review boundary between
what an agent generates and what future runs remember.

<div class="graft-steps">
<section>
<span class="graft-step-num">01</span>
<h3>Save with evidence</h3>
<p>Store text, JSON, reports, or figures as immutable SHA-256 revisions linked to exact input references.</p>
</section>
<section>
<span class="graft-step-num">02</span>
<h3>Review explicitly</h3>
<p>Record who accepted, corrected, or withdrew a selection—always from host code, never from an unreviewed model write.</p>
</section>
<section>
<span class="graft-step-num">03</span>
<h3>Recall safely</h3>
<p>Pass <code>graft_tool()</code> or <code>graft_tools()</code> to ellmer, shinychat, deputy, or mcptools with per-call eligibility checks.</p>
</section>
</div>

## Quick start in R

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

# Expose bounded, read-only recall to ellmer, deputy, or mcptools
tools <- graft_tools(
  store,
  purpose = "project-assistance",
  eligible = function(stream) TRUE
)
```

Saving a correction under the same ID creates a new immutable revision while
leaving the original reference readable with `graft_read()`.

## Where graft fits in the ellmer ecosystem

<div class="graft-ecosystem-table">

| Package | Role | How it pairs with graft |
|---|---|---|
| **ellmer** & **shinychat** | Model calls, tools, and chat UI | Register `graft_tool()` or `graft_tools()` so fresh chats consult reviewed memory with rich tool cards |
| **ragnar** | Similarity search (RAG) | **ragnar finds, graft verifies**: search broadly with ragnar, then verify current acceptance through `graft_recall()` |
| **commons** & **data-dict** | Trusted data analysis & data contracts | Commons runs live queries; graft preserves reviewed outputs and pinned shared vocabularies |
| **deputy** | Governed agent runtime & `TrustedResults` | Run graft tools in read-only/plan modes and capture agent drafts via `TrustedResults()` for human review |
| **mcptools** | Model Context Protocol servers | Serve `graft_tool()` or `graft_tools()` to Claude Code, Positron, or Posit Assistant |
| **vitals** & **scans** | LLM evals & trajectory analysis | Score recall accuracy with `vitals`; inspect `@extra$graft` consultations and promote findings from `scans` |

</div>

See [Graft in the ellmer ecosystem](articles/architecture.html) for the full
diagram and ownership map.

## Try the interactive Shiny notebook

The package includes a runnable Shiny app pairing a reviewable project notebook
with a shinychat conversation. By default it runs locally with real graft files
and scripted replies—no API key required:

```r
pak::pak(c("JamesHWade/graft", "ellmer", "shinychat", "shiny", "bslib"))
Sys.setenv(GRAFT_DEMO_STORE = file.path(getwd(), "project-memory"))
shiny::runApp(system.file("examples", "project-memory", package = "graft"))
```

Review and save the proposed definition, ask *"How do we count an active
customer?"*, start a **New conversation**, and then review a 60-day correction.
Set `OPENAI_API_KEY` and `Sys.setenv(GRAFT_DEMO_LIVE = "true")` to switch to a
live ellmer agent.

## Explore the guides

<div class="graft-paths">
<section>
<h3>Project memory for chat agents</h3>
<p>Build the workflow step by step and connect <code>graft_tool()</code> and <code>graft_tools()</code> to ellmer, shinychat, deputy, mcptools, and ragnar.</p>
<p><a href="articles/getting-started.html">Give a chat agent project memory →</a></p>
</section>
<section>
<h3>Artifacts, evidence, and history</h3>
<p>Save reports, tables, and figures with exact dependencies, list streams, and persist to local directories or PostgreSQL scopes.</p>
<p><a href="articles/persistent-artifacts.html">Persistent artifacts and review history →</a></p>
</section>
<section>
<h3>Shared vocabulary across workflows</h3>
<p>Pin concepts, relationships, and qualified data-dict bindings so agents and Commons workflows share consistent terminology.</p>
<p><a href="articles/shared-vocabulary.html">Shared concepts across workflows →</a></p>
</section>
<section>
<h3>Evaluate recall with vitals</h3>
<p>Test accepted, corrected, withdrawn, instruction-like, and host-denied memory with a credential-free <code>vitals::Task</code>.</p>
<p><a href="articles/recall-evaluation.html">Evaluate agent recall →</a></p>
</section>
</div>
