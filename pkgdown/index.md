# graft

<div class="graft-hero">
<p class="graft-eyebrow">Persistent artifacts and shared vocabulary for R</p>
<h2 data-toc-skip>Keep what you learn.<br>Return to the exact evidence.</h2>
<p class="graft-hero-copy">
Retain reports, evidence and shared concepts after the workflow ends. Record
what a host accepted, preserve earlier revisions, and give a later task the
exact artifacts behind an answer.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Retain your first artifact</a>
<a class="btn btn-outline-secondary" href="articles/shared-vocabulary.html">Share concepts across workflows</a>
</div>
</div>

## From a result to persistent memory

A workflow produces a conclusion. A person reviews it. A later task needs both
the original answer and the evidence behind it. Graft keeps immutable artifact
revisions and exact dependency selections so a correction can coexist with the
history it replaces.

<table class="table graft-workflow">
<thead><tr><th>Retain</th><th>Review</th><th>Reuse</th></tr></thead>
<tbody><tr>
<td>Save artifact bytes and select exact dependencies.</td>
<td>Record the host's acceptance or withdrawal for a stated purpose.</td>
<td>Verify the selected bytes and check current host eligibility.</td>
</tr></tbody>
</table>

Saving or selecting an artifact does not approve it. Historical inspection
preserves evidence of an earlier decision; a new task still needs current
permission. Applications decide access, scientific validity, review and retention.

## Start in R

```r
pak::pak("JamesHWade/graft")

library(graft)
store <- graft_artifact_store("research-artifacts", create = TRUE)
report <- graft_artifact_save(
  store, "report:pilot", charToRaw("Pilot evidence and conclusions"), "text/plain"
)
selection <- graft_artifact_select(store, list(report))
rawToChar(graft_artifact_read(store, report)$bytes)
```

The [quickstart](articles/getting-started.html) runs offline and introduces exact
revisions, selections and host decisions. The core artifact workflow requires
neither a schema compiler nor model credentials.

## Choose your next workflow

<div class="graft-paths">
<section>
<h3>Preserve a reviewed result</h3>
<p>Retain a report with its evidence and record acceptance or withdrawal without
rewriting its earlier bytes.</p>
<p><a href="articles/persistent-artifacts.html">Use artifacts and decisions</a></p>
</section>
<section>
<h3>Share concepts and relationships</h3>
<p>Bind vocabulary to exact data-dict dictionary releases. Reopen the retained
source and rendered context without the original files.</p>
<p><a href="articles/shared-vocabulary.html">Build a shared vocabulary</a></p>
</section>
<section>
<h3>Verify a replacement store</h3>
<p>Preview exclusions and verify exact survivors in a separate store. Keep
Forget approval and backup admission with the application.</p>
<p><a href="articles/artifact-recovery.html">Build a verified replacement</a></p>
</section>
<section>
<h3>Understand the package boundaries</h3>
<p>Compose Commons analysis, data-dict contracts and Graft persistence while
keeping application policy with the consuming product.</p>
<p><a href="articles/architecture.html">Read the architecture</a></p>
</section>
<section>
<h3>Check integration contracts</h3>
<p>Inspect the supported formats, optional dependencies and tested scope before
connecting a workflow.</p>
<p><a href="articles/compatibility.html">Read integration requirements</a></p>
</section>
</div>

## What works together

Commons supplies live analytical capabilities. Data-dict describes data. Graft
retains artifacts, exact selections, decision history and shared meaning.
Tempest and Rill consume this infrastructure as applications; their scientific
or Reader-specific policies remain theirs. Vocabulary relationships describe
meaning and do not execute reasoning, authorize joins or select agent tools.

Tempest's public artifact workflow publishes completed research and retains its
reports and evidence. New research and resume require fresh host admission.
See the [persistent artifact guide](articles/persistent-artifacts.html) for the
application handoff and its tested scope. Rill now retains opt-in Reader Memory
through scoped PostgreSQL artifacts. Permanent Forget and durable restore remain
rollout gates.

## Scope and status

Graft supports trusted local files with one writer and PostgreSQL scopes inside
host-owned transactions. Complete manifests and non-destructive replacement
plans verify retained objects. Power-loss recovery, authenticated access, restore
admission and permanent erasure remain separate work. No interchangeable
backend API is promised today.

Consumer contract **3.1.0** adds verified replacement mechanics. Contract 3 removes the native graph store, LinkML compiler,
commit plans, graph snapshots, managed OKF tree and graph-specific agent tools.
There are no compatibility wrappers. Retained artifact, selection, decision and
vocabulary formats keep their exact identities.
