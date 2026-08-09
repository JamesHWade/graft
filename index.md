# graft

Revision-first knowledge for R workflows

## Review what changes. Preserve why. Retrieve what was accepted.

graft turns candidate records into governed knowledge. A LinkML or
data-dict source compiles into the contract that defines what is valid,
a read-only plan shows exactly what would change, and one atomic commit
path preserves every accepted revision with its provenance.

[Run the 10-minute
workflow](https://jameshwade.github.io/graft/articles/getting-started.md)
[See the
architecture](https://jameshwade.github.io/graft/articles/architecture.md)

Read-only planning Atomic acceptance Immutable history Bounded retrieval

## One path from proposal to knowledge

The package has one visible acceptance boundary. Everything before
commit is a proposal; everything after commit is derived from the
accepted revision ledger.

01 **Contract** Define identity, fields, and relationships with LinkML
or data-dict.

02 **Provenance** Name the producer event and its replay boundary.

03 **Plan** Normalize and validate without writing accepted state.

04 **Review** Inspect inserts, updates, matches, and all collected
issues.

05 **Commit** Recheck preconditions and accept the complete plan
atomically.

06 **Retrieve** Read current records, history, and bounded projections.

## One authoritative ledger

A compiled domain contract supplies meaning. DuckDB stores accepted
revisions and provenance. Current records, search, contract-declared
graph relationships, and the readable OKF working tree are rebuildable
projections—never alternate write paths.

This makes the important question easy to answer: *what, exactly, was
accepted?* The revision ledger is the answer. A local OKF edit becomes
an ordinary proposal through
[`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
and still passes through
[`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md).

[Read the architecture and guarantees
→](https://jameshwade.github.io/graft/articles/architecture.md)

![A LinkML or data-dict contract compiles into Graft. OKF exchanges
readable proposals and projections with Graft. Graft commits to and
retrieves accepted revisions from
DuckDB.](reference/figures/okf-linkml-duckdb-system.svg)

Contract, authority, and readable projection stay distinct.

## Guarantees you can design around

P

### Planning is read-only

Validation and identity resolution produce an inspectable plan without
accepting records or provenance.

C

### Commit is defensive

Changed contracts, stale heads, altered plans, and incomplete
transactions fail before a partial acceptance.

H

### History is authoritative

Immutable revisions retain the accepted record, schema digest, batch,
and producer provenance.

R

### Retrieval is bounded

Fixed operations enforce limits and contract policy without exposing raw
SQL or mutation to agents.

## A complete change in R

``` r

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

The complete guide explains each decision, adds a connected record, and
shows search, advanced retrieval, history, and the readable OKF surface.
Loading the compiled example contract and operating the store are
R-only. Source contracts can be compiled from LinkML or from data-dict
YAML or trusted resolved `export-spec` JSON. A source provider defines
meaning; it never becomes the accepted ledger or another write path.

Use
[LinkML](https://jameshwade.github.io/graft/articles/linkml-schema.md)
for inheritance and rich graph semantics. Use
[data-dict](https://jameshwade.github.io/graft/articles/data-dict-schema.md)
for a strict, table-first contract with descriptions, glossary metadata,
enums, and scalar foreign-key validation. Its CLI-assisted YAML path
runs `export-spec`, not upstream metadata or data validation, and scalar
foreign keys are not graph traversal edges. YAML source-spec and
resolved JSON export-format versions are tracked separately, and Graft
re-hashes the selected CLI around export and version discovery. YAML
bytes are captured once so preflight, CLI export, and the source/build
fingerprints share one immutable snapshot.

The data-dict manifest is public contract metadata. Column examples and
ranges, dataset and table origins, and table source locators are
removed, although their raw values still bind source and build digests.
Those digests permit equality tests and offline guessing of low-entropy
values; redaction is not a secrecy boundary. Other retained fields can
expose observed or sensitive values embedded manually. The strict
profile rejects `number(id)` in scalar or list form, fails closed on
unsafe JSON numeric tokens before lossy conversion, and enforces its
supported datetime forms. The [data-dict
guide](https://jameshwade.github.io/graft/articles/data-dict-schema.md)
documents the exact boundary.

## Choose your path

[Use the package **Run the first accepted change** Start with a
complete, provider-free
workflow.](https://jameshwade.github.io/graft/articles/getting-started.md)
[Design a system **Understand authority and projections** See storage
boundaries, S7 choices, and
guarantees.](https://jameshwade.github.io/graft/articles/architecture.md)
[Govern changes **Review before acceptance** Work with plans, optimistic
preconditions, and
history.](https://jameshwade.github.io/graft/articles/knowledge-change-control.md)
[Build an integration **Use bounded retrieval** Choose current, search,
query, history, or agent
tools.](https://jameshwade.github.io/graft/articles/retrieval.md)

## Small on purpose

The v0.1 API is 15 functions arranged around the lifecycle, not the
storage engine. Rich objects protect durable invariants; records and
results stay as ordinary data frames and lists.

Define &
open[`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md)
[`graft_open()`](https://jameshwade.github.io/graft/reference/graft_open.md)
[`graft_close()`](https://jameshwade.github.io/graft/reference/graft_close.md)

Propose &
accept[`graft_provenance()`](https://jameshwade.github.io/graft/reference/graft_provenance.md)
[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
[`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md)
[`graft_ingest()`](https://jameshwade.github.io/graft/reference/graft_ingest.md)

Retrieve &
inspect[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md)
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md)
[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md)
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)

Synchronize &
integrate[`graft_sync()`](https://jameshwade.github.io/graft/reference/graft_sync.md)
[`graft_status()`](https://jameshwade.github.io/graft/reference/graft_status.md)
[`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)

Start with the boundary that matters

## Plan the change before you accept it.

Build one local store, inspect one plan, and recover the exact accepted
history.

[Get
started](https://jameshwade.github.io/graft/articles/getting-started.md)
[Browse the 15
functions](https://jameshwade.github.io/graft/reference/index.md)
