# graft

Table-native knowledge for R

## Keep knowledge connected to its evidence.

graft turns a LinkML contract into a portable DuckDB knowledge layer
where records, claims, identity, and citations remain inspectable from R
and model-assisted workflows.

[Get
started](https://jameshwade.github.io/graft/articles/getting-started.md)
[View on GitHub](https://github.com/JamesHWade/graft)

LinkML contract DuckDB runtime Evidence-backed claims Bounded retrieval

## Why graft?

Research and agentic systems rarely need only another table. They need
to know whether two observations refer to the same thing, which source
supports a claim, what changed between runs, and whether a query stayed
inside the active semantic contract.

01

### Contract first

Compile a LinkML domain schema into a portable, fingerprinted manifest
that drives tables, validation, identity, and graph projections.

02

### Evidence stays attached

Keep narrative and semantic claims distinct, then connect them to exact
stored sources, locators, excerpts, and support relationships.

03

### Retrieval stays bounded

Give analysts and language models structured access without arbitrary
SQL or silent unbounded collection.

## From schema to answer

01 **Model the domain** Extend graft’s core LinkML record roles.

02 **Compile the contract** Commit the resolved `.graft.json` manifest.

03 **Ingest atomically** Reconcile identity and preserve batch
provenance.

04 **Retrieve safely** Use lazy tables, bounded APIs, graphs, or ellmer
tools.

## A familiar R workflow

``` r

library(graft)

schema <- kg_schema("materials.graft.json")
store <- kg_connect_duckdb(schema, "knowledge.duckdb")
kg_init(store)

matches <- kg_find(store, "LLDPE crystallinity", limit = 10)
record <- kg_get(store, matches$id[[1]])
claims <- kg_claims(store, record$id)
```

The manifest is compiled once. Loading it, managing DuckDB, and
retrieving knowledge run entirely in R.

### For R users

Work with DBI and lazy dbplyr tables, exact identifier lookup, hydrated
records, stored citations, and bounded graph neighborhoods.

### For model-assisted workflows

Expose six read-only ellmer tools over the same manifest-controlled
APIs, with limits, truncation state, and schema digests in every result.

## Build the first complete workflow

The getting-started guide follows a material from its schema through
identity resolution, a source-backed claim, and bounded retrieval.

[Read the
guide](https://jameshwade.github.io/graft/articles/getting-started.md)
[Browse the
reference](https://jameshwade.github.io/graft/reference/index.md)
