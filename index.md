# graft

Persistent, reviewed memory for R

## Reviewed memory and artifacts for R apps and agents.

Chat sessions reset when the window closes, and vector search returns
whatever matches—drafts and outdated notes included. `graft` adds a
review-gated memory store to your `ellmer`, `shinychat`, `deputy`, or
`mcptools` workflow: save outputs with their source evidence, record
accept/withdraw decisions from your app, and give models bounded,
read-only recall.

[Add graft to your
app](https://jameshwade.github.io/graft/articles/getting-started.md)
[Browse the
reference](https://jameshwade.github.io/graft/reference/index.md)

## The integration boundary

`graft` stays small so it drops cleanly into applications you already
own. It handles immutable storage, verification, and decision
history—never LLM calls, UI, or user authentication.

WRITE & REVIEW

### Your app owns writes and approval

[`graft_save()`](https://jameshwade.github.io/graft/reference/graft_save.md),
[`graft_accept()`](https://jameshwade.github.io/graft/reference/graft_accept.md),
and
[`graft_withdraw()`](https://jameshwade.github.io/graft/reference/graft_withdraw.md)
sit behind your UI button, review queue, or pipeline—never behind an
unreviewed model write tool.

AGENT READS

### Models get bounded read-only recall

[`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
and
[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
run your `eligible` callback on every call, cap UTF-8 previews, and
attach `shinychat` cards plus `@extra$graft` metadata for `scans`.

PERSISTENCE

### Local files or PostgreSQL scopes

Content-addressed SHA-256 revisions with per-stream advisory locks for
multi-process Connect apps, or transaction-scoped
[`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md)
for multi-user isolation.

## Plug into your stack

Pick the tool you already use to see how `graft` wires in:

- ellmer + shinychat
- deputy
- mcptools
- ragnar
- vitals + scans

Register
[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
on your session’s `ellmer` chat and keep
[`graft_accept()`](https://jameshwade.github.io/graft/reference/graft_accept.md)
behind your Shiny review button:

``` r

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

Run read-only memory tools in `"readonly"` or `"plan"` mode, and capture
agent drafts via
[`deputy::TrustedResults()`](https://jameshwade.github.io/deputy/reference/TrustedResults.html)
for human review:

``` r

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

Expose reviewed project memory to Claude Code, Positron, or Posit
Assistant over stdio MCP with `mcptools`:

``` r

library(graft)

store <- graft_store("/absolute/path/to/project-memory")
tools <- graft_tools(
  store,
  purpose = "project-assistance",
  eligible = function(stream) TRUE
)

mcptools::mcp_server(tools = tools, session_tools = FALSE)
```

**ragnar finds, graft verifies:** index accepted notes by stream and
revision, then verify every search hit through
[`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md)
so withdrawn or superseded entries never reach the prompt:

``` r

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

Every
[`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
/
[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
result attaches a plain-data `@extra$graft` record for trajectory
analysis in `scans`, and promoted findings link back to the `scans`
investigation snapshot as an immutable dependency:

``` r

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

## Where graft fits in the ellmer ecosystem

| Package | Role | How it pairs with graft |
|----|----|----|
| **ellmer** & **shinychat** | Model calls, tools, and chat UI | Register [`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md) or [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md) so chats consult reviewed memory with tool cards |
| **ragnar** | Similarity search (RAG) | **ragnar finds, graft verifies**: search broadly with ragnar, verify current acceptance via [`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md) |
| **commons** & **data-dict** | Trusted data analysis & data contracts | Commons runs live queries; graft preserves reviewed outputs and pinned shared vocabularies |
| **deputy** | Governed agent runtime & `TrustedResults` | Enforce tool permissions and capture agent drafts for host-side review |
| **mcptools** | Model Context Protocol servers | Serve reviewed memory to Claude Code, Positron, or Posit Assistant |
| **vitals** & **scans** | LLM evals & trajectory analysis | Score recall accuracy with `vitals`; inspect `@extra$graft` consultations and promote findings from `scans` |

See [Integrate with the ellmer
ecosystem](https://jameshwade.github.io/graft/articles/architecture.md)
for the full architecture diagram and ownership boundaries.

## Copy a working Shiny template

The package includes a minimal Shiny + `shinychat` app
(`inst/examples/project-memory`) showing review controls, session reset
on correction, and persistent local storage. Run it locally with
scripted replies (no API key) or set `OPENAI_API_KEY` and
`GRAFT_DEMO_LIVE=true` for a live `ellmer` chat:

``` r

pak::pak(c("JamesHWade/graft", "ellmer", "shinychat", "shiny", "bslib"))
Sys.setenv(GRAFT_DEMO_STORE = file.path(getwd(), "project-memory"))
shiny::runApp(system.file("examples", "project-memory", package = "graft"))
```

## Guides

### Add reviewed memory to an app

Step-by-step integration for `ellmer`, `shinychat`, `deputy`,
`mcptools`, and `ragnar`.

[Read the integration guide
→](https://jameshwade.github.io/graft/articles/getting-started.md)

### Persist artifacts and PostgreSQL scopes

Save reports, tables, and figures with dependency closures, list
streams, and isolate multi-user stores in PostgreSQL.

[Read the storage guide
→](https://jameshwade.github.io/graft/articles/persistent-artifacts.md)

### Evaluate recall with vitals and scans

Verify that an integrated agent respects corrections, withdrawals, and
access denials using an offline
[`vitals::Task`](https://vitals.tidyverse.org/reference/Task.html).

[Read the evaluation guide
→](https://jameshwade.github.io/graft/articles/recall-evaluation.md)

### Share vocabulary across data-dict workflows

Pin concepts, relationships, and qualified `data-dict` bindings for R
workflows and `commons`.

[Read the vocabulary guide
→](https://jameshwade.github.io/graft/articles/shared-vocabulary.md)
