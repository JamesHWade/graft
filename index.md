# graft

Project memory for R apps and agents

## Keep what your project learns. Use it in the next conversation.

Save reviewed findings, definitions, and decisions with their evidence.
Give a later agent or workflow the current reviewed knowledge, its exact
sources, and its history.

[Build a project memory
assistant](https://jameshwade.github.io/graft/articles/getting-started.md)
[Get the runnable Shiny
example](https://github.com/JamesHWade/graft/tree/main/inst/examples/project-memory)

## Your assistant should remember what the team agreed on

You’re building an analytics assistant with ellmer and shinychat. The
team agrees that an active customer has a paid account and used the
product in the last 30 days. Next week, someone opens a fresh
conversation and asks how to count active customers.

With Graft, your app can retrieve the reviewed definition and the exact
source behind it. If the team changes the window to 60 days, you can
review that correction, use it in later conversations, and still inspect
the earlier version.

| Review once | Reuse later | Correct with history |
|----|----|----|
| Save the agreed definition and its handbook excerpt. | Let a fresh chat retrieve the current reviewed note through [`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md). | Review the updated definition while preserving the original evidence. |

## Try it in a Shiny app

The included project notebook puts review controls beside a shinychat
conversation. The default scripted preview uses real Graft files without
model calls.

``` r

pak::pak(c("JamesHWade/graft", "ellmer", "shinychat", "shiny", "bslib"))
Sys.setenv(GRAFT_DEMO_STORE = file.path(getwd(), "project-memory"))
shiny::runApp(system.file("examples", "project-memory", package = "graft"))
```

Review and save the proposed definition, then ask **“How do we count an
active customer?”** Start a new conversation and ask again. Stop and
restart the app to reopen the same notebook. The [getting-started
guide](https://jameshwade.github.io/graft/articles/getting-started.md)
walks through the storage calls, connects
[`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
to ellmer, and explains how to enable the live agent.

## What could your project keep?

### Project knowledge for an agent

Reviewed definitions, decisions, and findings that another conversation
needs. Your app chooses what to keep and who can use it.

[Give a chat agent project
memory](https://jameshwade.github.io/graft/articles/getting-started.md)

### A report with its evidence

A conclusion, table, or figure linked to the exact inputs behind it.
Revisit what was used when the result was produced.

[Keep artifacts and review
history](https://jameshwade.github.io/graft/articles/persistent-artifacts.md)

### Shared concepts across workflows

Definitions and relationships bound to a data-dict release. Different
agents and applications can recover the same retained vocabulary.

[Publish shared
vocabulary](https://jameshwade.github.io/graft/articles/shared-vocabulary.md)

## Save a result with its evidence

Start with a fresh directory and ordinary text:

``` r

library(graft)
store <- graft_store("analysis-memory", create = TRUE)
source <- graft_save(store, "Handbook: use a 30-day activity window.", "handbook")
note <- graft_save(
  store, "An active customer used the product in the past 30 days.",
  id = "active-customer", dependencies = source
)
graft_read(store, note)@data
```

Reopen it later with `graft_store("analysis-memory")`. Saving a
correction under the same ID creates a new revision; the original
reference still reads the original content. Use
[`graft_accept()`](https://jameshwade.github.io/graft/reference/graft_accept.md)
to record a review and
[`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md)
to retrieve the current accepted result, as shown in the getting-started
guide.

## Add Graft to an existing application

Keep ellmer for the model and tool calls, shinychat for the
conversation, and your application’s review and access controls. Add
Graft where a useful result should outlive the current chat or R
process.

Start with one kind of note and a read-only
[`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
fixed to its stream and purpose. A larger app can use its own catalog or
search index to choose relevant notes, then ask Graft to verify the
retained selections and evidence.

## Storage and operational guides

Graft supports trusted local files with one writer and PostgreSQL scopes
inside application-owned transactions. This pre-production example is
for one trusted local user. Shared deployment needs user/project
authorization and retention controls supplied by the application.

- [Back up and restore an artifact
  store](https://jameshwade.github.io/graft/articles/artifact-backups.md)
- [Build a verified replacement
  store](https://jameshwade.github.io/graft/articles/artifact-recovery.md)
- [Understand the
  architecture](https://jameshwade.github.io/graft/articles/architecture.md)
- [Check integration
  requirements](https://jameshwade.github.io/graft/articles/compatibility.md)

Permanent Forget and recovery from retired backups remain active work.
Saving or reviewing material records your application’s decision; it
does not establish that a claim is true.
