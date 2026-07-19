# graft

<div class="graft-hero">
<p class="graft-eyebrow">Table-native knowledge for R</p>
<h2 data-toc-skip>Keep knowledge connected to its evidence.</h2>
<p class="graft-hero-copy">
    graft turns a LinkML contract into a portable DuckDB knowledge layer where
    records, claims, identity, and citations remain inspectable from R and
    model-assisted workflows.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Get started</a>
<a class="btn btn-outline-secondary" href="https://github.com/JamesHWade/graft">
      View on GitHub
</a>
</div>
<div class="graft-tags" aria-label="Core package characteristics">
<span class="graft-tag">LinkML contract</span>
<span class="graft-tag">DuckDB runtime</span>
<span class="graft-tag">Evidence-backed claims</span>
<span class="graft-tag">Bounded retrieval</span>
</div>
</div>

## Why graft?

<p class="graft-section-lead">
Research and agentic systems rarely need only another table. They need to know
whether two observations refer to the same thing, which source supports a
claim, what changed between runs, and whether a query stayed inside the active
semantic contract.
</p>

<div class="graft-card-grid">
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">01</div>
<h3>Contract first</h3>
<p>
      Compile a LinkML domain schema into a portable, fingerprinted manifest
      that drives tables, validation, identity, and graph projections.
</p>
</div>
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">02</div>
<h3>Evidence stays attached</h3>
<p>
      Keep narrative and semantic claims distinct, then connect them to exact
      stored sources, locators, excerpts, and support relationships.
</p>
</div>
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">03</div>
<h3>Retrieval stays bounded</h3>
<p>
      Give analysts and language models structured access without arbitrary SQL
      or silent unbounded collection.
</p>
</div>
</div>

## From schema to answer

<div class="graft-flow" aria-label="The four-stage graft workflow">
<div class="graft-flow-step">
<span class="graft-flow-number">01</span>
<strong>Model the domain</strong>
<span>Extend graft's core LinkML record roles.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">02</span>
<strong>Compile the contract</strong>
<span>Commit the resolved <code>.graft.json</code> manifest.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">03</span>
<strong>Ingest atomically</strong>
<span>Reconcile identity and preserve batch provenance.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">04</span>
<strong>Retrieve safely</strong>
<span>Use lazy tables, bounded APIs, graphs, or ellmer tools.</span>
</div>
</div>

## A familiar R workflow

```r
library(graft)

schema <- kg_schema("materials.graft.json")
store <- kg_connect_duckdb(schema, "knowledge.duckdb")
kg_init(store)

matches <- kg_find(store, "LLDPE crystallinity", limit = 10)
record <- kg_get(store, matches$id[[1]])
claims <- kg_claims(store, record$id)
```

The manifest is compiled once. Loading it, managing DuckDB, and retrieving
knowledge run entirely in R.

<div class="graft-audience-grid">
<div class="graft-audience">
<h3>For R users</h3>
<p>
      Work with DBI and lazy dbplyr tables, exact identifier lookup, hydrated
      records, stored citations, and bounded graph neighborhoods.
</p>
</div>
<div class="graft-audience">
<h3>For model-assisted workflows</h3>
<p>
      Expose six read-only ellmer tools over the same manifest-controlled APIs,
      with limits, truncation state, and schema digests in every result.
</p>
</div>
</div>

<div class="graft-cta">
<h2 data-toc-skip>Build the first complete workflow</h2>
<p>
    The getting-started guide follows a material from its schema through
    identity resolution, a source-backed claim, and bounded retrieval.
</p>
<div class="graft-actions justify-content-center">
<a class="btn btn-primary" href="articles/getting-started.html">
      Read the guide
</a>
<a class="btn btn-outline-secondary" href="reference/index.html">
      Browse the reference
</a>
</div>
</div>
