# graft

<div class="graft-hero">
<p class="graft-eyebrow">Revision-first knowledge for R workflows</p>
<h2 data-toc-skip>Review what changes. Preserve why. Retrieve what was accepted.</h2>
<p class="graft-hero-copy">
    graft turns candidate records into governed knowledge. A LinkML or
    data-dict source compiles into the contract that defines what is valid, a
    read-only plan shows exactly what would change, and one atomic commit path
    preserves every accepted revision with its provenance.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Run the 10-minute workflow</a>
<a class="btn btn-outline-secondary" href="articles/architecture.html">See the architecture</a>
</div>
<div class="graft-tags" aria-label="Core package guarantees">
<span class="graft-tag">Read-only planning</span>
<span class="graft-tag">Atomic acceptance</span>
<span class="graft-tag">Immutable history</span>
<span class="graft-tag">Bounded retrieval</span>
</div>
</div>

## One path from proposal to knowledge

<p class="graft-section-lead">
The package has one visible acceptance boundary. Everything before commit is a
proposal; everything after commit is derived from the accepted revision
ledger.
</p>

<div class="graft-flow" aria-label="The six-stage graft workflow">
<div class="graft-flow-step">
<span class="graft-flow-number">01</span>
<strong>Contract</strong>
<span>Define identity, fields, and relationships with LinkML or data-dict.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">02</span>
<strong>Provenance</strong>
<span>Name the producer event and its replay boundary.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">03</span>
<strong>Plan</strong>
<span>Normalize and validate without writing accepted state.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">04</span>
<strong>Review</strong>
<span>Inspect inserts, updates, matches, and all collected issues.</span>
</div>
<div class="graft-flow-step graft-flow-step-accept">
<span class="graft-flow-number">05</span>
<strong>Commit</strong>
<span>Recheck preconditions and accept the complete plan atomically.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">06</span>
<strong>Retrieve</strong>
<span>Read current records, history, and bounded projections.</span>
</div>
</div>

## One authoritative ledger

<div class="graft-split">
<div>
<p class="graft-section-lead">
A compiled domain contract supplies meaning. DuckDB stores accepted revisions
and provenance. Current records, search, contract-declared graph
relationships, and the readable OKF working tree are rebuildable
projections&mdash;never alternate write paths.
</p>
<p>
This makes the important question easy to answer: <em>what, exactly, was
accepted?</em> The revision ledger is the answer. A local OKF edit becomes an
ordinary proposal through <code>graft_review()</code> and still passes through
<code>graft_commit()</code>.
</p>
<p><a href="articles/architecture.html">Read the architecture and guarantees &rarr;</a></p>
</div>
<figure class="graft-system-figure">
<img
  class="graft-architecture-visual"
  src="reference/figures/okf-linkml-duckdb-system.svg"
  alt="A LinkML or data-dict contract compiles into Graft. OKF exchanges readable proposals and projections with Graft. Graft commits to and retrieves accepted revisions from DuckDB."
>
<figcaption>Contract, authority, and readable projection stay distinct.</figcaption>
</figure>
</div>

## Guarantees you can design around

<div class="graft-card-grid graft-card-grid-four">
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">P</div>
<h3>Planning is read-only</h3>
<p>Validation and identity resolution produce an inspectable plan without accepting records or provenance.</p>
</div>
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">C</div>
<h3>Commit is defensive</h3>
<p>Changed contracts, stale heads, altered plans, and incomplete transactions fail before a partial acceptance.</p>
</div>
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">H</div>
<h3>History is authoritative</h3>
<p>Immutable revisions retain the accepted record, schema digest, batch, and producer provenance.</p>
</div>
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">R</div>
<h3>Retrieval is bounded</h3>
<p>Fixed operations enforce limits and contract policy without exposing raw SQL or mutation to agents.</p>
</div>
</div>

## A complete change in R

```r
library(graft)

schema <- graft_schema(system.file(
  "extdata", "personinfo.graft.json", package = "graft"
))
store <- graft_open(schema, ":memory:", okf = "disabled")

records <- list(Person = data.frame(
  id = "person:lois-lane",
  full_name = "Lois Lane"
))
origin <- graft_provenance(
  producer = "directory-import",
  idempotency_key = "directory-2026-08-04"
)

plan <- graft_plan(store, records, origin)
plan@changes
plan@issues

if (plan@valid) graft_commit(store, plan)

graft_get(store, "person:lois-lane")
graft_history(store, "person:lois-lane")
graft_close(store)
```

The complete guide explains each decision, adds a connected record, and shows
search, advanced retrieval, history, and the readable OKF surface. Loading the
compiled example contract and operating the store are R-only. Source contracts
can be compiled from LinkML or from data-dict YAML or trusted resolved
`export-spec` JSON. A source provider defines meaning; it never becomes the
accepted ledger or another write path.

Use [LinkML](articles/linkml-schema.html) for inheritance and rich graph
semantics. Use [data-dict](articles/data-dict-schema.html) for a strict,
table-first contract with descriptions, glossary metadata, enums, and scalar
foreign-key validation. Its CLI-assisted YAML path runs `export-spec`, not
upstream metadata or data validation, and scalar foreign keys are not graph
traversal edges. YAML source-spec and resolved JSON export-format versions are
tracked separately, and Graft re-hashes the selected CLI around export and
version discovery. YAML bytes are captured once so preflight, CLI export, and
the source/build fingerprints share one immutable snapshot.

The data-dict manifest is public contract metadata. Column examples and ranges,
dataset and table origins, and table source locators are removed, although
their raw values still bind source and build digests. Those digests permit
equality tests and offline guessing of low-entropy values; redaction is not a
secrecy boundary. Other retained fields can expose observed or sensitive
values embedded manually. The strict profile rejects `number(id)` in scalar or
list form, fails closed on unsafe JSON numeric tokens before lossy conversion,
and enforces its supported datetime forms. The [data-dict
guide](articles/data-dict-schema.html) documents the exact boundary.

## Choose your path

<div class="graft-path-grid">
<a class="graft-path" href="articles/getting-started.html">
<span class="graft-path-label">Use the package</span>
<strong>Run the first accepted change</strong>
<span>Start with a complete, provider-free workflow.</span>
</a>
<a class="graft-path" href="articles/architecture.html">
<span class="graft-path-label">Design a system</span>
<strong>Understand authority and projections</strong>
<span>See storage boundaries, S7 choices, and guarantees.</span>
</a>
<a class="graft-path" href="articles/knowledge-change-control.html">
<span class="graft-path-label">Govern changes</span>
<strong>Review before acceptance</strong>
<span>Work with plans, optimistic preconditions, and history.</span>
</a>
<a class="graft-path" href="articles/retrieval.html">
<span class="graft-path-label">Build an integration</span>
<strong>Use bounded retrieval</strong>
<span>Choose current, search, query, history, or agent tools.</span>
</a>
</div>

## Small on purpose

<p class="graft-section-lead">
The v0.1 API is 15 functions arranged around the lifecycle, not the storage
engine. Rich objects protect durable invariants; records and results stay as
ordinary data frames and lists.
</p>

<div class="graft-api-grid">
<div><span>Define &amp; open</span><code>graft_schema()</code> <code>graft_open()</code> <code>graft_close()</code></div>
<div><span>Propose &amp; accept</span><code>graft_provenance()</code> <code>graft_plan()</code> <code>graft_commit()</code> <code>graft_ingest()</code></div>
<div><span>Retrieve &amp; inspect</span><code>graft_get()</code> <code>graft_find()</code> <code>graft_query()</code> <code>graft_history()</code></div>
<div><span>Synchronize &amp; integrate</span><code>graft_sync()</code> <code>graft_status()</code> <code>graft_review()</code> <code>graft_tools()</code></div>
</div>

<div class="graft-cta">
<p class="graft-eyebrow">Start with the boundary that matters</p>
<h2 data-toc-skip>Plan the change before you accept it.</h2>
<p>Build one local store, inspect one plan, and recover the exact accepted history.</p>
<div class="graft-actions justify-content-center">
<a class="btn btn-primary" href="articles/getting-started.html">Get started</a>
<a class="btn btn-outline-secondary" href="reference/index.html">Browse the 15 functions</a>
</div>
</div>
