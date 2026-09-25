# graft

Project memory for R apps and agents

## Give your next conversation the knowledge your team has reviewed.

Save a finding or an agreed definition with the evidence behind it. An
agent or workflow can look it up later, check its exact sources, and see
how it changed.

[Build a project memory
assistant](https://jameshwade.github.io/graft/articles/getting-started.md)
[Get the runnable Shiny
example](https://github.com/JamesHWade/graft/tree/main/inst/examples/project-memory)

## Remember an agreed definition

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

Review and save the proposed definition, then ask “How do we count an
active customer?” Start a new conversation and ask again. Stop and
restart the app to reopen the same notebook. The [getting-started
guide](https://jameshwade.github.io/graft/articles/getting-started.md)
walks through the storage calls, connects
[`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
to ellmer, and explains how to enable the live agent.

## Where you could use Graft

### Project knowledge for an agent

Save a reviewed definition, decision, or finding for another
conversation. Your app chooses what to keep and who can use it.

[Give a chat agent project
memory](https://jameshwade.github.io/graft/articles/getting-started.md)

### A report with its evidence

Keep a conclusion, table, or figure with its exact inputs so you can
check what went into the result.

[Keep artifacts and review
history](https://jameshwade.github.io/graft/articles/persistent-artifacts.md)

### Shared concepts across workflows

Save definitions and relationships with a specific data-dict release so
agents and applications can recover the same vocabulary.

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
saved selections and evidence.

## Storage and operational guides

A local Graft store uses trusted files, and several R processes can
write to it on a file system that honours advisory locks (many network
file systems do not). For PostgreSQL, your application owns the
transaction in which Graft reads and writes. This pre-production example
is for one trusted local user. Before deploying to several users, your
app needs to check access to each user or project and decide how long to
keep the data.

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
