# graft

<div class="graft-hero">
<p class="graft-eyebrow">An R package for LinkML and DuckDB</p>
<h2 data-toc-skip>Schema-defined knowledge in DuckDB.</h2>
<p class="graft-hero-copy">
    graft compiles a LinkML schema into a JSON manifest. The manifest defines
    records, tables, identifiers, validation rules, and graph projections.
    graft uses it to create and query a DuckDB database from R.
</p>
<div class="graft-actions">
<a class="btn btn-primary" href="articles/getting-started.html">Get started</a>
<a class="btn btn-outline-secondary" href="https://github.com/JamesHWade/graft">
      View source
</a>
</div>
<div class="graft-tags" aria-label="Core package characteristics">
<span class="graft-tag">LinkML schemas</span>
<span class="graft-tag">DuckDB storage</span>
<span class="graft-tag">DBI and dbplyr</span>
<span class="graft-tag">Optional ellmer tools</span>
</div>
</div>

## What graft adds

<p class="graft-section-lead">
A database schema describes columns and types. It does not usually say which
fields identify the same record across runs, how a claim relates to its
evidence, or which relationships belong in a graph. graft records those
decisions in a LinkML schema and applies them when data are written and read.
</p>

<div class="graft-card-grid">
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">01</div>
<h3>Define the domain</h3>
<p>
      Describe materials, sources, claims, evidence, or other project-specific
      records as LinkML classes.
</p>
</div>
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">02</div>
<h3>Generate the manifest</h3>
<p>
      Resolve the schema once with <code>kg_compile_schema()</code>. Commit the
      generated <code>.graft.json</code> file with the project.
</p>
</div>
<div class="graft-card">
<div class="graft-card-mark" aria-hidden="true">03</div>
<h3>Use the store from R</h3>
<p>
      Write validated records to DuckDB, query lazy dbplyr tables, and inspect
      claims, evidence, identifiers, and graph neighborhoods.
</p>
</div>
</div>

## The basic workflow

<div class="graft-flow" aria-label="The four-stage graft workflow">
<div class="graft-flow-step">
<span class="graft-flow-number">01</span>
<strong>Write a schema</strong>
<span>Extend the core LinkML record classes.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">02</span>
<strong>Compile it</strong>
<span>Create a resolved <code>.graft.json</code> manifest.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">03</span>
<strong>Initialize a store</strong>
<span>Create the declared tables and graph views in DuckDB.</span>
</div>
<div class="graft-flow-step">
<span class="graft-flow-number">04</span>
<strong>Read and write records</strong>
<span>Use dbplyr tables or graft's collected query functions.</span>
</div>
</div>

## A small example

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

kg_classes(schema)
kg_slots(schema, "Claim")
```

Python and `linkml-runtime` are needed to compile a schema. Loading a compiled
manifest and using a store run entirely in R.

## Query interfaces

<div class="graft-audience-grid">
<div class="graft-audience">
<h3>R and dbplyr</h3>
<p>
      <code>kg_records()</code> returns a lazy dbplyr table.
      <code>kg_find()</code>, <code>kg_get()</code>, and the graph helpers
      return collected results with explicit limits.
</p>
</div>
<div class="graft-audience">
<h3>ellmer tools</h3>
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
<a class="btn btn-outline-secondary" href="reference/index.html">
      Browse functions
</a>
</div>
</div>
