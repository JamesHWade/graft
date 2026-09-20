# graft

<div class="graft-hero">
<p class="graft-eyebrow">Project memory for R apps and agents</p>
<h2 data-toc-skip>Keep what your project learns.<br>Use it in the next conversation.</h2>
<p class="graft-hero-copy">
Save reviewed findings, definitions, and decisions with their evidence. Give a
later agent or workflow the current knowledge and a way to inspect its history.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Build a project memory assistant</a>
<a class="btn btn-outline-secondary" href="https://github.com/JamesHWade/graft/tree/main/inst/examples/project-memory">Get the runnable Shiny example</a>
</div>
</div>

## Your assistant should remember what the team agreed on

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
<td>Let a fresh chat retrieve the current reviewed note through an ellmer tool.</td>
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

Review and save the proposed definition, then ask **“How do we count an active
customer?”** Start a new conversation and ask again. Stop and restart the app to
reopen the same notebook. The [getting-started guide](articles/getting-started.html)
walks through the storage calls, connects the memory tool to ellmer, and explains
how to enable the live agent.

## What could your project keep?

<div class="graft-paths">
<section>
<h3>Project knowledge for an agent</h3>
<p>Reviewed definitions, decisions, and findings that another conversation needs.
Your app chooses what to keep and who can use it.</p>
<p><a href="articles/getting-started.html">Give a chat agent project memory</a></p>
</section>
<section>
<h3>A report with its evidence</h3>
<p>A conclusion, table, or figure linked to the exact inputs behind it. Revisit
what was used when the result was produced.</p>
<p><a href="articles/persistent-artifacts.html">Keep artifacts and review history</a></p>
</section>
<section>
<h3>Shared concepts across workflows</h3>
<p>Definitions and relationships bound to a data-dict release. Different agents
and applications can recover the same retained vocabulary.</p>
<p><a href="articles/shared-vocabulary.html">Publish shared vocabulary</a></p>
</section>
</div>

## Add Graft to an existing application

Keep ellmer for the model and tool calls, shinychat for the conversation, and your
application's review and access controls. Add Graft where a useful result should
outlive the current chat or R process.

Start with one kind of note and a read-only tool that retrieves its current
reviewed version. A larger app can use its own catalog or search index to choose
relevant notes, then ask Graft to verify the retained selections and evidence.

## Storage and operational guides

Graft supports trusted local files with one writer and PostgreSQL scopes inside
application-owned transactions. This pre-production example is for one trusted
local user. Shared deployment needs user/project authorization and retention
controls supplied by the application.

- [Back up and restore an artifact store](articles/artifact-backups.html)
- [Build a verified replacement store](articles/artifact-recovery.html)
- [Understand the architecture](articles/architecture.html)
- [Check integration requirements](articles/compatibility.html)

Permanent Forget and recovery from retired backups remain active work. Saving or
reviewing material records your application's decision; it does not establish
that a claim is true.
