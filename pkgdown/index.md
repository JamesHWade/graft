# graft

<div class="graft-hero">
<p class="graft-eyebrow">Project memory for R apps and agents</p>
<h2 data-toc-skip>Give your next conversation<br>the knowledge your team has reviewed.</h2>
<p class="graft-hero-copy">
Save a finding or an agreed definition with the evidence behind it. An agent or
workflow can look it up later, check its exact sources, and see how it changed.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Build a project memory assistant</a>
<a class="btn btn-outline-secondary" href="https://github.com/JamesHWade/graft/tree/main/inst/examples/project-memory">Get the runnable Shiny example</a>
</div>
</div>

## Remember an agreed definition

You're building an analytics assistant with ellmer and shinychat. The team agrees
that an active customer has a paid account and used the product in the last
30 days. Next week, someone opens a fresh conversation and asks how to count
active customers.

With Graft, your app can retrieve the reviewed definition and the exact source
behind it. If the team changes the window to 60 days, you can review that
correction, use it in later conversations, and still inspect the earlier version.

<table class="table graft-workflow">
<thead><tr><th>Review once</th><th>Reuse later</th><th>Correct with history</th></tr></thead>
<tbody><tr>
<td>Save the agreed definition and its handbook excerpt.</td>
<td>Let a fresh chat retrieve the current reviewed note through <code>graft_tool()</code>.</td>
<td>Review the updated definition while preserving the original evidence.</td>
</tr></tbody>
</table>

## Try it in a Shiny app

The included project notebook puts review controls beside a shinychat conversation.
The default scripted preview uses real Graft files without model calls.

```r
pak::pak(c("JamesHWade/graft", "ellmer", "shinychat", "shiny", "bslib"))
Sys.setenv(GRAFT_DEMO_STORE = file.path(getwd(), "project-memory"))
shiny::runApp(system.file("examples", "project-memory", package = "graft"))
```

Review and save the proposed definition, then ask "How do we count an active
customer?" Start a new conversation and ask again. Stop and restart the app to
reopen the same notebook. The [getting-started guide](articles/getting-started.html)
walks through the storage calls, connects `graft_tool()` to ellmer, and explains
how to enable the live agent.

## Where you could use Graft

<div class="graft-paths">
<section>
<h3>Project knowledge for an agent</h3>
<p>Save a reviewed definition, decision, or finding for another conversation.
Your app chooses what to keep and who can use it.</p>
<p><a href="articles/getting-started.html">Give a chat agent project memory</a></p>
</section>
<section>
<h3>A report with its evidence</h3>
<p>Keep a conclusion, table, or figure with its exact inputs so you can check
what went into the result.</p>
<p><a href="articles/persistent-artifacts.html">Keep artifacts and review history</a></p>
</section>
<section>
<h3>Shared concepts across workflows</h3>
<p>Save definitions and relationships with a specific data-dict release so
agents and applications can recover the same vocabulary.</p>
<p><a href="articles/shared-vocabulary.html">Publish shared vocabulary</a></p>
</section>
</div>

## Save a result with its evidence

Start with a fresh directory and ordinary text:

```r
library(graft)
store <- graft_store("analysis-memory", create = TRUE)
source <- graft_save(store, "Handbook: use a 30-day activity window.", "handbook")
note <- graft_save(
  store, "An active customer used the product in the past 30 days.",
  id = "active-customer", dependencies = source
)
graft_read(store, note)@data
```

Reopen it later with `graft_store("analysis-memory")`. Saving a correction under
the same ID creates a new revision; the original reference still reads the
original content. Use `graft_accept()` to record a review and `graft_recall()` to
retrieve the current accepted result, as shown in the getting-started guide.

## Add Graft to an existing application

Keep ellmer for the model and tool calls, shinychat for the conversation, and your
application's review and access controls. Add Graft where a useful result should
outlive the current chat or R process.

Start with one kind of note and a read-only `graft_tool()` fixed to its stream and
purpose. A larger app can use its own catalog or search index to choose relevant
notes, then ask Graft to verify the saved selections and evidence.

## Storage and operational guides

A local Graft store uses trusted files and supports one writer. For PostgreSQL,
your application owns the transaction in which Graft reads and writes. This
pre-production example is for one trusted local user. Before deploying to
several users, your app needs to check access to each user or project and decide
how long to keep the data.

- [Back up and restore an artifact store](articles/artifact-backups.html)
- [Build a verified replacement store](articles/artifact-recovery.html)
- [Understand the architecture](articles/architecture.html)
- [Check integration requirements](articles/compatibility.html)

Permanent Forget and recovery from retired backups remain active work. Saving or
reviewing material records your application's decision; it does not establish
that a claim is true.
