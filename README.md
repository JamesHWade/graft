# graft <img src="man/figures/logo.png" align="right" height="139" alt="Graft hex sticker: a tree frog tending a grafted branch." />

<!-- badges: start -->
[![R-CMD-check](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/graft/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/JamesHWade/graft/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/graft)
<!-- badges: end -->

graft gives R workflows and agents durable, reviewed knowledge. Preserve research
conclusions, interpretations, definitions and related records so a later task
can reuse an exact accepted version and inspect what changed.

Start with a [data-dict](https://data-dict.tidyverse.org/) contract. Graft adds
validated acceptance, stable identity, revision history, snapshots and bounded
reads. Applications own the meaning of accepted content, permission to consult
it and authority to execute code. Acceptance is not factual truth.

Follow the [offline quickstart](https://jameshwade.github.io/graft/articles/getting-started.html),
try [narrative reuse](https://jameshwade.github.io/graft/articles/ecosystem.html),
or retain an [exact reuse basis](https://jameshwade.github.io/graft/articles/reuse-basis.html).
The tested agent recipes use ellmer, Deputy and dsprrr. Commons receives a
detached public source; LinkML supports richer graph domains.

## Installation

Install the development version from GitHub:

```r
pak::pak("JamesHWade/graft")
```

Using a resolved data-dict contract or an existing `.graft.json` contract is
R-only. The data-dict CLI and LinkML's Python dependencies are optional
authoring tools, not store runtime requirements.

## From related tables to history

The package includes a small team directory as data-dict source YAML and
resolved `export-spec` JSON. `graft_schema()` compiles the resolved JSON using R
alone. `graft_open()` initializes a blank store when its path does not exist.

```r
library(graft)

resolved_json <- system.file(
  "extdata",
  "team-directory.data-dict.json",
  package = "graft",
  mustWork = TRUE
)
schema <- graft_schema(resolved_json)

store_path <- tempfile(fileext = ".duckdb")
store <- graft_open(schema, store_path, okf = "disabled")
```

Candidate records are ordinary data frames. Here, an employment row points to
an organization that is not part of the batch or the store:

```r
records <- list(
  organization = data.frame(
    id = "org:daily-planet",
    name = "Daily Planet"
  ),
  person = data.frame(
    id = "person:lois-lane",
    full_name = "Lois Lane",
    job_title = "Reporter"
  ),
  employment = data.frame(
    id = "employment:lois-lane:daily-planet",
    person_id = "person:lois-lane",
    organization_id = "org:missing"
  )
)

origin <- graft_provenance(
  producer = "directory-import",
  idempotency_key = "directory-2026-08-09"
)

plan <- graft_plan(store, records, origin)
plan@valid
#> [1] FALSE

plan@issues[, c("class", "record_id", "field", "message")]
```

Planning is read-only. Correct the reference, create a fresh plan, inspect the
proposed inserts, and commit the complete batch:

```r
records$employment$organization_id <- "org:daily-planet"
plan <- graft_plan(store, records, origin)

plan@changes[, c("class", "record_id", "action", "changed_fields")]

if (plan@valid) {
  graft_commit(store, plan)
}
```

When a later source changes a fact, the update becomes another reviewable plan
rather than overwriting the earlier record:

```r
updated_person <- list(person = data.frame(
  id = "person:lois-lane",
  full_name = "Lois Lane",
  job_title = "Investigative editor"
))

update_plan <- graft_plan(
  store,
  updated_person,
  graft_provenance(
    producer = "hr-review",
    idempotency_key = "hr-review-2026-08-10"
  )
)

update_plan@changes[, c("record_id", "action", "changed_fields")]
graft_commit(store, update_plan)

graft_get(store, "person:lois-lane")$record
graft_history(store, "person:lois-lane")[
  , c("revision_number", "committed_at", "producer", "changed_fields")
]
```

The current record has the new title. History retains both accepted versions,
their changed fields, and their producers.

## Give an agent bounded reads

Pin the accepted boundary, then hand the pinned view to a model. Later commits
cannot change what that session reads:

```r
snapshot <- graft_snapshot(store)
view <- graft_at(store, snapshot)

tools <- graft_tools(view)
names(tools)
#> [1] "graft_find"       "graft_get"        "graft_query"
#> [4] "graft_history"    "graft_dictionary"

chat <- ellmer::chat_anthropic()
chat$set_tools(tools)
chat$chat("Who works at the Daily Planet, and has that person's title changed?")
```

The record tools delegate to `graft_find()`, `graft_get()`, `graft_query()`, and
`graft_history()`. They expose no SQL, filesystem, network, or mutation
argument, and every result reports the limit it applied, whether it was
truncated, and the contract digest it came from. Writes stay in R, behind a
reviewable plan.

```r
graft_close(store)
unlink(store_path)
```

## Choose a contract provider

Start with [data-dict](https://jameshwade.github.io/graft/articles/data-dict-schema.html)
when the domain is naturally expressed as related tables. Graft validates its
scalar foreign keys, but does not treat them as graph traversal edges.

Use [LinkML](https://jameshwade.github.io/graft/articles/linkml-schema.html)
when you need traversable relationships, inheritance, ontology identifiers,
polymorphic references, or other richer graph semantics. Both providers compile
to the same Graft contract and use the same store, plan, commit, retrieval, and
history functions.

## Documentation

1. [Get started](https://jameshwade.github.io/graft/articles/getting-started.html)
   with the complete data-dict workflow.
2. [Author a data-dict
   contract](https://jameshwade.github.io/graft/articles/data-dict-schema.html).
3. Read about [change
   control](https://jameshwade.github.io/graft/articles/knowledge-change-control.html)
   and [retrieval and
   history](https://jameshwade.github.io/graft/articles/retrieval.html).
4. [Work with
   agents](https://jameshwade.github.io/graft/articles/agents.html): bounded
   tools, pinned snapshots, and agent-authored proposals.
5. [Add graph semantics with
   LinkML](https://jameshwade.github.io/graft/articles/linkml-schema.html).
6. Use [open
   knowledge](https://jameshwade.github.io/graft/articles/open-knowledge-format.html)
   for a readable file projection, or read the
   [architecture](https://jameshwade.github.io/graft/articles/architecture.html)
   and [contract compiler
   reference](https://jameshwade.github.io/graft/articles/contract-compilers.html)
   for implementation details.
