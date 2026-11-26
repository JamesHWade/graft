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
<a class="btn btn-primary" href="articles/getting-started.html">Build a project memory assistant</a>
<a class="btn btn-outline-secondary" href="articles/architecture.html">See how graft fits the ellmer ecosystem</a>
</div>
</div>

## Why reviewed memory?

Language models start every session from scratch. Conversations live in a chat
window; search indexes return whatever matches a query—even drafts, superseded
definitions, or withdrawn results.

Suppose your team agrees that an "active customer" has a paid account and used
the product in the past 30 days. With graft, your app saves that definition
alongside its source, records your review, and exposes a read-only tool to
future chats. When the window changes to 60 days, you review the correction
while keeping the original evidence and decision history intact.

<table class="table graft-workflow">
<thead><tr><th>1. Save with evidence</th><th>2. Review explicitly</th><th>3. Recall safely</th></tr></thead>
<tbody><tr>
<td>Store text, JSON, reports, or figures with exact references to their inputs.</td>
<td>Record who accepted or withdrew a selection—never from an unreviewed model write.</td>
<td>Hand <code>graft_tool()</code> to ellmer, shinychat, deputy, or mcptools so agents read only current approved memory.</td>
</tr></tbody>
</table>

## Try the project notebook app

The package includes a runnable Shiny app pairing a reviewable notebook with a
shinychat conversation. By default it runs locally with real graft storage and
scripted replies—no API key required.

```r
pak::pak(c("JamesHWade/graft", "ellmer", "shinychat", "shiny", "bslib"))
Sys.setenv(GRAFT_DEMO_STORE = file.path(getwd(), "project-memory"))
shiny::runApp(system.file("examples", "project-memory", package = "graft"))
```

1. Review and save the proposed definition and source.
2. Ask *"How do we count an active customer?"*
3. Start a **New conversation** and ask again—the reviewed definition persists.
4. Update the definition to 60 days, review the correction, and ask in a fresh
   chat to verify the updated answer while keeping history intact.

Set `OPENAI_API_KEY` and `Sys.setenv(GRAFT_DEMO_LIVE = "true")` to switch to a
live ellmer agent. See the [getting-started guide](articles/getting-started.html)
for the step-by-step code, `deputy` runtime integration, and `mcptools` setup.

## Where graft fits in the ellmer ecosystem

graft stays small and composes cleanly with Posit's ellmerverse and the wider
ellmerverse+ stack:

| Package | Role | How it pairs with graft |
|---|---|---|
| **ellmer** & **shinychat** | Model calls, tools, and chat UI | Register `graft_tool()` so chats consult reviewed memory with rich tool cards |
| **ragnar** | Similarity search (RAG) over documents | **ragnar finds, graft verifies**: use ragnar to locate candidates, then recall only current accepted revisions through graft |
| **commons** & **data-dict** | Trusted data analysis & dictionary contracts | Commons runs live analyses; graft retains reviewed reports, conclusions, and pinned shared vocabularies across sessions |
| **deputy** | Governed agent runtime & `TrustedResults` | Run `graft_tool()` in read-only/plan modes and capture agent drafts via `TrustedResults()` for human review |
| **mcptools** | Model Context Protocol servers | Serve `graft_tool()` to Claude Code, Positron, or Posit Assistant |
| **vitals** & **scans** | LLM evals & trajectory analysis | Evaluate memory recall with `vitals` and inspect completed agent runs and promotion candidates with `scans` |

Read [Graft in the ellmer ecosystem](articles/architecture.html) for the full
ownership map.

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

# Later session or fresh process
recalled <- graft_recall(
  graft_store("analysis-memory"),
  stream = "metric:active-customer",
  purpose = "project-assistance",
  eligible = TRUE
)
recalled@roots[[1L]]@data
```

Saving a correction under the same ID creates a new immutable revision while
leaving the original reference readable with `graft_read()`.

## Explore the guides

<div class="graft-paths">
<section>
<h3>Project memory for chat agents</h3>
<p>Wire reviewed notes into ellmer, shinychat, deputy, and local MCP servers
with <code>graft_tool()</code>.</p>
<p><a href="articles/getting-started.html">Give a chat agent project memory</a></p>
</section>
<section>
<h3>Artifacts, evidence, and history</h3>
<p>Save reports, tables, and figures with exact dependencies, list streams, and
persist to local directories or PostgreSQL scopes.</p>
<p><a href="articles/persistent-artifacts.html">Persistent artifacts and review history</a></p>
</section>
<section>
<h3>Shared vocabulary across workflows</h3>
<p>Pin concepts, relationships, and qualified data-dict bindings so agents
share consistent terminology across releases.</p>
<p><a href="articles/shared-vocabulary.html">Shared concepts across workflows</a></p>
</section>
<section>
<h3>Evaluate recall with vitals</h3>
<p>Test accepted, corrected, withdrawn, instruction-like, and host-denied
memory with a credential-free <code>vitals::Task</code>.</p>
<p><a href="articles/recall-evaluation.html">Evaluate agent recall</a></p>
</section>
</div>
