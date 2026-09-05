# graft

<div class="graft-hero">
<p class="graft-eyebrow">Durable knowledge for R workflows and agents</p>
<h2 data-toc-skip>Keep what you learn.<br>Review what changes.</h2>
<p class="graft-hero-copy">
Give research conclusions, interpretations, definitions and related records an
accepted history. Start with <code>data-dict.yaml</code>, review proposed changes,
and let a later task return to the exact knowledge an earlier task used.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Build your first store</a>
<a class="btn btn-outline-secondary" href="articles/ecosystem.html">Try narrative reuse</a>
</div>
</div>

## From a result to a reusable record

An R workflow produces a conclusion. A person corrects it. A later agent needs
the earlier answer and the evidence behind it. Replacing yesterday's file
loses that distinction; Graft retains each accepted revision and the producer
recorded for the change.

<table class="table graft-workflow">
<thead><tr><th>Describe</th><th>Review</th><th>Reuse</th></tr></thead>
<tbody><tr>
<td>Use data-dict to describe fields, meaning and relationships.</td>
<td>Inspect a proposed plan, correct invalid references, then accept it.</td>
<td>Read current history or pin an exact boundary for a later task.</td>
</tr></tbody>
</table>

data-dict supplies the contract. Graft adds validated acceptance, stable
identity, revisions, snapshots and bounded retrieval. Ordinary tables are a
useful starting point; their values can include Markdown, interpretations,
preferences and normalized evidence links.

Acceptance records a decision for a purpose. It does not make a claim true,
authorize access, or permit execution of stored code. Applications retain those
responsibilities.

## Start in R

Install the development package:

```r
pak::pak("JamesHWade/graft")
```

The [quickstart](articles/getting-started.html) runs entirely offline. It uses a
shipped resolved data-dict contract to create a store, reject a broken
reference, accept a correction, inspect history and pin a snapshot. No model
credentials or Python installation are required.

Author your own `data-dict.yaml` with the optional data-dict CLI, then compile
its resolved export in R. Existing compiled contracts also run in R alone.
[LinkML](articles/linkml-schema.html) remains available for domains needing
richer graph semantics.

## Choose your next workflow

<div class="graft-paths">
<section>
<h3>Review changing knowledge</h3>
<p>Keep proposals separate from accepted records. Inspect changes, handle stale
plans and retry without manufacturing another revision.</p>
<p><a href="articles/knowledge-change-control.html">Review and accept changes</a></p>
</section>
<section>
<h3>Return to an exact answer</h3>
<p>Retain the full selected evidence across restarts and unchanged days. Flag
changed dependencies for review while preserving the earlier interpretation.</p>
<p><a href="articles/reuse-basis.html">Retain an exact reuse basis</a></p>
</section>
<section>
<h3>Give an agent bounded reads</h3>
<p>Use ordinary ellmer tools with ellmer, Deputy or dsprrr. Keep connections in
the process that owns them and reconnect workers from serializable references.</p>
<p><a href="articles/ecosystem.html">Explore tested host recipes</a></p>
</section>
<section>
<h3>Calculate and inspect receipts</h3>
<p>Evaluate accepted Definitions against a pinned boundary. Inspect the recorded
evidence path without treating a receipt as a fact-check.</p>
<p><a href="reference/graft_calculate.html">Calculate with accepted Definitions</a></p>
</section>
</div>

## What works together today

Graft's tested host loops cover ellmer, Deputy and dsprrr; Commons consumes a
detached public copy and retains its own file measures. Tempest owns research
products and promotion, with accepted-evidence restart checks. Rill's Reader
integration, isolation and permanent Forget gates remain separate work.

The [integration guide](articles/compatibility.html) records supported versions
and limitations. The [ecosystem guide](articles/ecosystem.html) separates tested
composition from planned application behavior. Generic read tools alone do not
enforce Reader permissions or decide what an agent may consult automatically.

## Read a result's evidence path

Graft classifies recorded answer evidence as **Verified**, **Cited** or
**Untrusted**. Verified paths use governed calculations with matching receipts;
Cited paths use independently matched Graft reads. Failures, unknown sources or
mixed unsupported evidence keep a result Untrusted.

These labels describe the recorded path. They do not measure factual accuracy,
authenticate producer identities or guarantee that prose faithfully represents
a source. [Work with agents](articles/agents.html) explains the checks and their
limits.
