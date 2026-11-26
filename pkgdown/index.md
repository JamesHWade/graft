# graft

<div class="graft-hero">
<p class="graft-eyebrow">Persistent, reviewed memory for R</p>
<h2 data-toc-skip>Reviewed memory and artifacts for R apps and agents.</h2>
<p class="graft-hero-copy">
Chat sessions reset when the window closes, and vector search returns whatever
matches—drafts and outdated notes included. <code>graft</code> adds a
review-gated memory store to your <code>ellmer</code>, <code>shinychat</code>,
<code>deputy</code>, or <code>mcptools</code> workflow: save outputs with their
source evidence, record accept/withdraw decisions from your app, and give
models bounded, read-only recall.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Add graft to your app</a>
<a class="btn btn-outline-secondary" href="reference/index.html">Browse the reference</a>
</div>
</div>

## The integration boundary

`graft` stays small so it drops cleanly into applications you already own. It
handles immutable storage, verification, and decision history—never LLM calls,
UI, or user authentication.

<div class="graft-steps">
<section>
<span class="graft-step-num">WRITE &amp; REVIEW</span>
<h3>Your app owns writes and approval</h3>
<p><code>graft_save()</code>, <code>graft_accept()</code>, and <code>graft_withdraw()</code> sit behind your UI button, review queue, or pipeline—never behind an unreviewed model write tool.</p>
</section>
<section>
<span class="graft-step-num">AGENT READS</span>
<h3>Models get bounded read-only recall</h3>
<p><code>graft_tool()</code> and <code>graft_tools()</code> run your <code>eligible</code> callback on every call, cap UTF-8 previews, and attach <code>shinychat</code> cards plus <code>@extra$graft</code> metadata for <code>scans</code>.</p>
</section>
<section>
<span class="graft-step-num">PERSISTENCE</span>
<h3>Local files or PostgreSQL scopes</h3>
<p>Content-addressed SHA-256 revisions with per-stream advisory locks for multi-process Connect apps, or transaction-scoped <code>graft_store_postgres()</code> for multi-user isolation.</p>
</section>
</div>

## Plug into your stack

Pick the tool you already use to see how `graft` wires in:

<div class="graft-tabs">
<ul class="nav nav-tabs" id="graftStackTabs" role="tablist">
<li class="nav-item" role="presentation">
<button class="nav-link active" id="tab-ellmer-btn" data-bs-toggle="tab" data-bs-target="#tab-ellmer" type="button" role="tab" aria-controls="tab-ellmer" aria-selected="true">ellmer + shinychat</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link" id="tab-deputy-btn" data-bs-toggle="tab" data-bs-target="#tab-deputy" type="button" role="tab" aria-controls="tab-deputy" aria-selected="false">deputy</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link" id="tab-mcp-btn" data-bs-toggle="tab" data-bs-target="#tab-mcp" type="button" role="tab" aria-controls="tab-mcp" aria-selected="false">mcptools</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link" id="tab-ragnar-btn" data-bs-toggle="tab" data-bs-target="#tab-ragnar" type="button" role="tab" aria-controls="tab-ragnar" aria-selected="false">ragnar</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link" id="tab-scans-btn" data-bs-toggle="tab" data-bs-target="#tab-scans" type="button" role="tab" aria-controls="tab-scans" aria-selected="false">vitals + scans</button>
</li>
</ul>

<div class="tab-content" id="graftStackContent">
<div class="tab-pane fade show active" id="tab-ellmer" role="tabpanel" aria-labelledby="tab-ellmer-btn">

Register `graft_tools()` on your session's `ellmer` chat and keep `graft_accept()` behind your Shiny review button:

```r
library(graft)

store <- graft_store("project-memory", create = TRUE)

# In your app's review button handler:
source_ref <- graft_save(
  store, "Handbook: 30-day paid activity window.", "metrics.md"
)
note_ref <- graft_save(
  store, "Active customers have paid activity in the past 30 days.",
  id = "metric:active-customer", dependencies = source_ref
)
graft_accept(
  store, note_ref, stream = "metric:active-customer", expected = NULL,
  key = "review-1", actor = current_user, reason = "Verified", purpose = "chat"
)

# In each Shiny session's ellmer chat:
chat <- ellmer::chat_openai()
chat$set_tools(graft_tools(
  store,
  purpose = "chat",
  eligible = function(stream) user_can_read(current_user, stream)
))
```

</div>
<div class="tab-pane fade" id="tab-deputy" role="tabpanel" aria-labelledby="tab-deputy-btn">

Run read-only memory tools in `"readonly"` or `"plan"` mode, and capture agent drafts via `deputy::TrustedResults()` for human review:

```r
memory_tools <- graft_tools(
  store,
  purpose = "project-assistance",
  eligible = function(stream) TRUE
)

agent <- deputy::Agent$new(
  chat = ellmer::chat_openai(),
  tools = c(memory_tools, list(draft_tool)),
  trusted_results = deputy::TrustedResults(
    definition = "draft_definition",
    on_result = function(event) {
      # Saved as an unaccepted draft; never recalled until graft_accept()
      graft_save(store, event$value, id = "draft:metric:active-customer")
    }
  )
)
```

</div>
<div class="tab-pane fade" id="tab-mcp" role="tabpanel" aria-labelledby="tab-mcp-btn">

Expose reviewed project memory to Claude Code, Positron, or Posit Assistant over stdio MCP with `mcptools`:

```r
library(graft)

store <- graft_store("/absolute/path/to/project-memory")
tools <- graft_tools(
  store,
  purpose = "project-assistance",
  eligible = function(stream) TRUE
)

mcptools::mcp_server(tools = tools, session_tools = FALSE)
```

</div>
<div class="tab-pane fade" id="tab-ragnar" role="tabpanel" aria-labelledby="tab-ragnar-btn">

**ragnar finds, graft verifies:** index accepted notes by stream and revision, then verify every search hit through `graft_recall()` so withdrawn or superseded entries never reach the prompt:

```r
verify_ragnar_hit <- function(store, hit_stream, purpose, eligible) {
  recalled <- graft_recall(
    store,
    stream = hit_stream,
    purpose = purpose,
    eligible = eligible(hit_stream)
  )
  if (!identical(recalled@status, "accepted")) return(NULL)
  recalled
}
```

</div>
<div class="tab-pane fade" id="tab-scans" role="tabpanel" aria-labelledby="tab-scans-btn">

Every `graft_tool()` / `graft_tools()` result attaches a plain-data `@extra$graft` record for trajectory analysis in `scans`, and promoted findings link back to the `scans` investigation snapshot as an immutable dependency:

```r
investigation_ref <- graft_save_file(
  store, "scans-investigation.json",
  id = "scans:investigation:2026-11-26", media_type = "application/json"
)
note_ref <- graft_save(
  store, "Count paid accounts active in the past 30 days.",
  id = "metric:active-customer", dependencies = investigation_ref
)
graft_accept(
  store, note_ref, stream = "metric:active-customer", expected = NULL,
  key = "promote-1", actor = "reviewer",
  reason = "Promoted recurring untrusted route from scans", purpose = "chat"
)
```

</div>
</div>
</div>

## Where graft fits in the ellmer ecosystem

<div class="graft-ecosystem-table">

| Package | Role | How it pairs with graft |
|---|---|---|
| **ellmer** & **shinychat** | Model calls, tools, and chat UI | Register `graft_tool()` or `graft_tools()` so chats consult reviewed memory with tool cards |
| **ragnar** | Similarity search (RAG) | **ragnar finds, graft verifies**: search broadly with ragnar, verify current acceptance via `graft_recall()` |
| **commons** & **data-dict** | Trusted data analysis & data contracts | Commons runs live queries; graft preserves reviewed outputs and pinned shared vocabularies |
| **deputy** | Governed agent runtime & `TrustedResults` | Enforce tool permissions and capture agent drafts for host-side review |
| **mcptools** | Model Context Protocol servers | Serve reviewed memory to Claude Code, Positron, or Posit Assistant |
| **vitals** & **scans** | LLM evals & trajectory analysis | Score recall accuracy with `vitals`; inspect `@extra$graft` consultations and promote findings from `scans` |

</div>

See [Integrate with the ellmer ecosystem](articles/architecture.html) for the
full architecture diagram and ownership boundaries.

## Copy a working Shiny template

The package includes a minimal Shiny + `shinychat` app (`inst/examples/project-memory`)
showing review controls, session reset on correction, and persistent local
storage. Run it locally with scripted replies (no API key) or set
`OPENAI_API_KEY` and `GRAFT_DEMO_LIVE=true` for a live `ellmer` chat:

```r
pak::pak(c("JamesHWade/graft", "ellmer", "shinychat", "shiny", "bslib"))
Sys.setenv(GRAFT_DEMO_STORE = file.path(getwd(), "project-memory"))
shiny::runApp(system.file("examples", "project-memory", package = "graft"))
```

## Guides

<div class="graft-paths">
<section>
<h3>Add reviewed memory to an app</h3>
<p>Step-by-step integration for <code>ellmer</code>, <code>shinychat</code>, <code>deputy</code>, <code>mcptools</code>, and <code>ragnar</code>.</p>
<p><a href="articles/getting-started.html">Read the integration guide →</a></p>
</section>
<section>
<h3>Persist artifacts and PostgreSQL scopes</h3>
<p>Save reports, tables, and figures with dependency closures, list streams, and isolate multi-user stores in PostgreSQL.</p>
<p><a href="articles/persistent-artifacts.html">Read the storage guide →</a></p>
</section>
<section>
<h3>Evaluate recall with vitals and scans</h3>
<p>Verify that an integrated agent respects corrections, withdrawals, and access denials using an offline <code>vitals::Task</code>.</p>
<p><a href="articles/recall-evaluation.html">Read the evaluation guide →</a></p>
</section>
<section>
<h3>Share vocabulary across data-dict workflows</h3>
<p>Pin concepts, relationships, and qualified <code>data-dict</code> bindings for R workflows and <code>commons</code>.</p>
<p><a href="articles/shared-vocabulary.html">Read the vocabulary guide →</a></p>
</section>
</div>
