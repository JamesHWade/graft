# graft

<!-- badges: start -->
[![R-CMD-check](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/JamesHWade/graft/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/graft)
<!-- badges: end -->

graft is an R package for storing schema-defined knowledge in DuckDB. A store
can contain domain records, claims about those records, sources, and evidence
that links a claim to a specific source location.

A LinkML schema defines the record classes, fields, identifiers, validation
rules, and graph projections. `kg_compile_schema()` resolves that schema into a
`.graft.json` manifest, which graft uses to initialize and query the database.

Start with the [getting started
guide](https://jameshwade.github.io/graft/articles/getting-started.html) to
build a small store and query its records, claims, and evidence.
The [LinkML schema
article](https://jameshwade.github.io/graft/articles/linkml-schema.html) starts
from an ordinary schema with no graft-specific imports or annotations.
The [examples
page](https://jameshwade.github.io/graft/articles/examples.html) applies the
same workflow to chemistry and environmental biology.

Python and `linkml-runtime` are required only to compile a schema. Loading and
inspecting a committed manifest is pure R/JSON. The manifest drives DuckDB
storage, validation, identity, retrieval, and graph projections:

```r
library(graft)

manifest <- system.file(
  "extdata",
  "personinfo.graft.json",
  package = "graft"
)
schema <- kg_schema(manifest)
store <- kg_connect_duckdb(schema, ":memory:")
kg_init(store)

kg_classes(schema)
kg_slots(schema, "Person")
```

Functions that collect records or graph results require a limit and report
whether the result was truncated. `kg_tools()` exposes six of the same
read-only queries as ellmer tools:

```r
chat <- ellmer::chat_anthropic()
chat$set_tools(kg_tools(store))
```
