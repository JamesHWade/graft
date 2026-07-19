# graft

<div class="graft-hero">
<p class="graft-eyebrow">A knowledge layer for R workflows</p>
<h2 data-toc-skip>Keep workflow results consistent, connected, and traceable.</h2>
<p class="graft-hero-copy">
    Define what your domain records mean once. graft applies that contract
    whenever R workflows write or retrieve data&mdash;reconciling identities
    across runs, validating relationships, preserving claims with exact
    evidence, and exposing predictable queries to analysts and AI tools.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Get started</a>
<a class="btn btn-outline-secondary" href="https://github.com/JamesHWade/graft">
      View source
</a>
</div>
<div class="graft-tags" aria-label="Core package characteristics">
<span class="graft-tag">Stable identity</span>
<span class="graft-tag">Schema-checked ingestion</span>
<span class="graft-tag">Claims and evidence</span>
<span class="graft-tag">Bounded retrieval</span>
</div>
</div>

## When tidy tables are not enough

<p class="graft-section-lead">
An R workflow can produce tidy tables and still leave hard questions scattered
across scripts. Is this the same material as last run? Which source supports
this claim? Is a relationship stated or inferred? What may an automated tool
retrieve? graft makes those decisions explicit, versioned, and enforceable.
</p>

<div class="graft-card-grid">
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">01</div>
<h3>Recognize the same thing</h3>
<p>
      Use declared identifiers and workflow-specific keys to match new results
      to existing records.
</p>
</div>
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">02</div>
<h3>Keep claims traceable</h3>
<p>
      Preserve what a source said, where it said it, and whether the stored
      evidence supports or challenges the claim.
</p>
</div>
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">03</div>
<h3>Control retrieval</h3>
<p>
      Give R code schema-aware query helpers and AI tools structured access
      without arbitrary SQL or invented relationships.
</p>
</div>
</div>

## What graft does

<div class="graft-flow" aria-label="The four-stage graft workflow">
<div class="graft-flow-step">
<span class="graft-flow-number">01</span>
<strong>Define the contract</strong>
<span>Describe records, identifiers, validation, and relationships.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">02</span>
<strong>Write workflow results</strong>
<span>Ingest related data frames as one producer batch.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">03</span>
<strong>Reconcile and validate</strong>
<span>Reuse identities, check references, and record lineage.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">04</span>
<strong>Retrieve with context</strong>
<span>Inspect records together with claims, evidence, and relationships.</span>
</div>
</div>

graft uses an ordinary LinkML schema as the source contract and compiles it
into a portable <code>.graft.json</code> manifest. At runtime, that manifest
drives validation, identity, storage, and retrieval. The current backend is
embedded DuckDB, so stores are local and remain available through familiar DBI
and dbplyr workflows.

## From a data frame to a durable record

```r
library(graft)

manifest <- system.file(
  "extdata",
  "materials.graft.json",
  package = "graft"
)
schema <- kg_schema(manifest)
store <- kg_connect_duckdb(schema, ":memory:")
kg_init(store)

kg_ingest(
  store,
  kg_batch(
    producer = "materials-pipeline",
    source_run_id = "run-42",
    idempotency_key = "lldpe-v1"
  ),
  list(Material = data.frame(
    preferred_name = "Linear low-density polyethylene",
    cas_number = "9002-88-4"
  ))
)

material_id <- kg_lookup(store, "cas", "CAS: 9002-88-4")$record_id[[1]]
kg_get(store, material_id)
```

Reuse the same producer and idempotency key, and graft recognizes the write as
a replay rather than a new observation. The getting-started guide continues
from this foundation by adding a source-backed claim and retrieving the exact
evidence stored with it.

Python and `linkml-runtime` are needed only to compile a schema. After
compilation, graft loads committed manifests and operates stores entirely in R.

## Query interfaces

<div class="graft-audience-grid">
<div class="graft-audience">
<h3>Analysts and applications</h3>
<p>
      <code>kg_records()</code> returns a lazy dbplyr table.
      <code>kg_find()</code>, <code>kg_get()</code>, and the graph helpers
      return collected results with explicit limits and schema context.
</p>
</div>
<div class="graft-audience">
<h3>AI tools</h3>
<p>
      <code>kg_tools()</code> creates six read-only tools for one store. The
      tools accept structured arguments rather than SQL and report truncation
      state and the active schema digest.
</p>
</div>
</div>

<div class="graft-cta">
<h2 data-toc-skip>Next steps</h2>
<p>
    The getting-started guide builds a small materials store, then adds records,
    a claim, a source, and evidence.
</p>
<div class="graft-actions justify-content-center">
<a class="btn btn-primary" href="articles/getting-started.html">
      Read getting started
</a>
<a class="btn btn-outline-secondary" href="articles/examples.html">
      See examples
</a>
<a class="btn btn-outline-secondary" href="reference/index.html">
      Browse functions
</a>
</div>
</div>
