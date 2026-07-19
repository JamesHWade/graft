# graft

An R package for LinkML and DuckDB

## Schema-defined knowledge in DuckDB.

graft compiles a LinkML schema into a JSON manifest. The manifest
defines records, tables, identifiers, validation rules, and graph
projections. graft uses it to create and query a DuckDB database from R.

[Get
started](https://jameshwade.github.io/graft/articles/getting-started.md)
[View source](https://github.com/JamesHWade/graft)

LinkML schemas DuckDB storage DBI and dbplyr Optional ellmer tools

## What graft adds

A database schema describes columns and types. It does not usually say
which fields identify the same record across runs, how a claim relates
to its evidence, or which relationships belong in a graph. graft records
those decisions in a LinkML schema and applies them when data are
written and read.

01

### Define the domain

Describe materials, sources, claims, evidence, or other project-specific
records as LinkML classes.

02

### Generate the manifest

Resolve the schema once with
[`kg_compile_schema()`](https://jameshwade.github.io/graft/reference/kg_compile_schema.md).
Commit the generated `.graft.json` file with the project.

03

### Use the store from R

Write validated records to DuckDB, query lazy dbplyr tables, and inspect
claims, evidence, identifiers, and graph neighborhoods.

## The basic workflow

01 **Write a schema** Extend the core LinkML record classes.

02 **Compile it** Create a resolved `.graft.json` manifest.

03 **Initialize a store** Create the declared tables and graph views in
DuckDB.

04 **Read and write records** Use dbplyr tables or graft’s collected
query functions.

## A small example

``` r

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

Python and `linkml-runtime` are needed to compile a schema. Loading a
compiled manifest and using a store run entirely in R.

## Query interfaces

### R and dbplyr

[`kg_records()`](https://jameshwade.github.io/graft/reference/kg_records.md)
returns a lazy dbplyr table.
[`kg_find()`](https://jameshwade.github.io/graft/reference/kg_find.md),
[`kg_get()`](https://jameshwade.github.io/graft/reference/kg_get.md),
and the graph helpers return collected results with explicit limits.

### ellmer tools

[`kg_tools()`](https://jameshwade.github.io/graft/reference/kg_tools.md)
creates six read-only tools for one store. The tools accept structured
arguments rather than SQL and report truncation state and the active
schema digest.

## Next steps

The getting-started guide builds a small materials store, then adds
records, a claim, a source, and evidence.

[Read getting
started](https://jameshwade.github.io/graft/articles/getting-started.md)
[Browse
functions](https://jameshwade.github.io/graft/reference/index.md)
