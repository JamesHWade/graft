# graft

<!-- badges: start -->
[![R-CMD-check](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/JamesHWade/graft/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/graft)
<!-- badges: end -->

graft keeps records produced by R workflows consistent, connected, and
traceable across runs. It reconciles identities, validates related data as they
are written, preserves claims with exact source evidence, and provides bounded
retrieval for analysts, applications, and AI tools.

The package puts decisions that often drift across scripts into one versioned
contract: what each record means, how it is identified, which relationships are
valid, and what may be retrieved. The contract begins as an ordinary LinkML
schema and compiles to a portable `.graft.json` manifest.

Start with the [getting started
guide](https://jameshwade.github.io/graft/articles/getting-started.html) to
build a small store and query its records, claims, and evidence.
The [LinkML schema
article](https://jameshwade.github.io/graft/articles/linkml-schema.html) starts
from an ordinary schema with no graft-specific imports or annotations.
The [examples
page](https://jameshwade.github.io/graft/articles/examples.html) applies the
same workflow to chemistry and environmental biology.

The current storage backend is embedded DuckDB, which keeps a graft store local
and available through DBI and dbplyr. Python and `linkml-runtime` are required
only to compile a schema; loading a committed manifest and using a store run in
R:

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

kg_ingest(
  store,
  kg_batch(
    producer = "directory-import",
    source_run_id = "run-42",
    idempotency_key = "daily-planet-v1"
  ),
  list(
    Organization = data.frame(
      id = "org:daily-planet",
      name = "Daily Planet"
    ),
    Person = data.frame(
      id = "person:clark-kent",
      full_name = "Clark Kent",
      employed_by = I(list("org:daily-planet"))
    )
  )
)

kg_get(store, "person:clark-kent")
```

The batch is atomic, its relationship is validated, and reusing the same
producer and idempotency key does not create another observation. Functions
that collect records or graph results require a limit and report whether the
result was truncated. `kg_tools()` exposes six of the same read-only queries as
ellmer tools:

```r
chat <- ellmer::chat_anthropic()
chat$set_tools(kg_tools(store))
```
