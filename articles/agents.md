# Work with agents

An agent connected to a database can read anything the connection
allows, write without review, and give a different answer tomorrow
because the underlying rows moved. Graft is built so that none of those
three things has to be true.

The same properties that make accepted knowledge reviewable for people
make it usable by a model: reads are bounded and deterministic, an
accepted boundary can be pinned and carried between sessions, and every
write is a proposal that carries its producer and passes validation
before it is accepted.

| What the agent does | Graft surface | Boundary |
|----|----|----|
| Reads records, searches, traverses, reads history | [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md) | Read-only, bounded, no SQL or filesystem |
| Works from fixed accepted state | [`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md), [`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md) | Later commits cannot change its answers |
| Proposes new or corrected records | [`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md), [`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md) | Validated, attributed, reviewable before acceptance |
| Edits readable files | [`graft_status()`](https://jameshwade.github.io/graft/reference/graft_status.md), [`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md) | File edits stay proposals until reviewed |

## Set up a store to work against

This guide uses the resolved data-dict contract included with the
package.

``` r

library(graft)

schema <- graft_schema(system.file(
  "extdata",
  "team-directory.data-dict.json",
  package = "graft",
  mustWork = TRUE
))
store <- graft_open(schema, ":memory:", okf = "disabled")

graft_ingest(
  store,
  list(
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
      organization_id = "org:daily-planet"
    )
  ),
  graft_provenance(
    producer = "team-directory-import",
    idempotency_key = "team-directory-v1"
  )
)
```

## Hand the agent four bounded tools

[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
returns [ellmer](https://ellmer.tidyverse.org/) tool definitions for
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md),
[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md),
[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md),
and
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md):

``` r

tools <- graft_tools(store)
names(tools)
#> [1] "graft_find"    "graft_get"     "graft_query"   "graft_history"
```

Register them with a chat and the model can search, retrieve, traverse,
and read history on its own:

``` r

chat <- ellmer::chat_anthropic()
chat$set_tools(tools)

chat$chat("Who works at the Daily Planet, and has that person's title changed?")
```

The definitions delegate to the same public retrieval functions a person
calls from the console. They accept no SQL, no connection, no path, and
no mutation argument, and each one is annotated read-only,
non-destructive, idempotent, and closed-world for hosts that act on
those hints.

Every tool result is a named list with `result` plus `truncated`,
`limit`, and `store_schema_digest`. A model that receives a bounded
prefix is told that it received one, rather than silently reasoning over
a partial answer:

``` r

str(tools$graft_find(query = "Lois", class = "person", limit = 5), max.level = 1)
#> List of 4
#>  $ result             :'data.frame': 1 obs. of 5 variables:
#>  $ truncated          : logi FALSE
#>  $ limit              : int 5
#>  $ store_schema_digest: chr "sha256:752574346c168754..."
```

`store_schema_digest` identifies the contract the answer came from, so a
transcript can be checked later against the schema in force at the time.

## Pin the boundary the agent reasons over

A long-running agent session should not change its mind because another
process committed a batch halfway through.
[`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md)
captures the accepted boundary as a serializable, path-free value,
[`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md)
binds it to a read-only view, and tools built from that view stay
pinned:

``` r

snapshot <- graft_snapshot(store)
view <- graft_at(store, snapshot)
pinned_tools <- graft_tools(view)
```

Accept a change after pinning:

``` r

graft_ingest(
  store,
  list(person = data.frame(
    id = "person:lois-lane",
    full_name = "Lois Lane",
    job_title = "Investigative reporter"
  )),
  graft_provenance(
    producer = "hr-review",
    idempotency_key = "hr-review-v1"
  )
)

graft_get(store, "person:lois-lane")$record$job_title
#> [1] "Investigative reporter"
graft_get(view, "person:lois-lane")$record$job_title
#> [1] "Reporter"
```

Because the snapshot carries no connection and no filesystem path, it
can be written to a job record, passed to another process, or stored
with an evaluation case and rebound later with
[`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md).
Two runs against the same snapshot read the same accepted knowledge.
[`graft_view_snapshot()`](https://jameshwade.github.io/graft/reference/graft_view_snapshot.md)
recovers the exact boundary a view is holding, which is what you record
alongside a transcript when you need to explain an answer.

The live-store `integrity` operation is unavailable through a view,
since a diagnostic of the current store would contradict the pinned
boundary.

## Let the agent propose, not write

Nothing about agent-supplied records is special: they are ordinary data
frames that go through the same plan, review, and commit path as any
other producer. What matters is that the agent is named as the producer
and that the plan is inspected before it is accepted.

``` r

proposal <- graft_provenance(
  producer = "directory-agent",
  version = "2026.08",
  run_id = "run-8842",
  idempotency_key = "run-8842-batch-1",
  metadata = list(model = "claude-opus-4-5", session = "s-1174")
)

plan <- graft_plan(
  store,
  list(person = data.frame(
    id = "person:clark-kent",
    full_name = "Clark Kent",
    job_title = "Reporter"
  )),
  proposal
)

plan@valid
plan@changes[, c("class", "record_id", "action", "changed_fields")]
plan@issues[, c("class", "record_id", "field", "message")]
```

Planning writes nothing. The plan is an immutable object bound to the
store, schema, and record heads observed during planning, so a person or
a host policy can read `@changes` and `@issues`, decide, and then call
[`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md).
If the store moved underneath the plan, the commit fails its
preconditions instead of writing a decision that was reviewed against
different state.

``` r

if (plan@valid) {
  graft_commit(store, plan)
}
```

Two habits make this durable in practice:

- Give each agent a distinct `producer` and a per-run `run_id`. Every
  accepted revision then answers “which agent, in which run, proposed
  this” through
  [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md).
- Set an `idempotency_key` per proposed batch. A retried run — the
  common failure mode for agents — replays instead of writing a
  duplicate revision.

[`graft_ingest()`](https://jameshwade.github.io/graft/reference/graft_ingest.md)
collapses plan and commit into one call. Use it for a trusted pipeline;
keep the two-step form when an agent is the producer and something, or
someone, should look at the change first.

``` r

graft_history(store, "person:clark-kent")[
  , c("revision_number", "committed_at", "producer", "changed_fields")
]
```

## Give a file-editing agent a working surface

Coding agents are good at reading and editing files and less good at
operating a database client. Opening a store with `okf = "managed"`
maintains an Open Knowledge Format working tree: a deterministic
Markdown projection of accepted knowledge that an agent can read, grep,
and edit directly. A file-backed store uses a sibling directory, so
`team.duckdb` projects into `team.okf` unless `okf_path` says otherwise.

``` r

okf_store <- graft_open(schema, "team.duckdb", okf = "managed")
graft_sync(okf_store)
graft_status(okf_store)
```

An edited file is a proposal, not accepted knowledge.
[`graft_status()`](https://jameshwade.github.io/graft/reference/graft_status.md)
reports that the tree is modified, and
[`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
turns the edits into the same plan type
[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
returns:

``` r

edit_plan <- graft_review(
  okf_store,
  provenance = graft_provenance(
    producer = "directory-agent",
    run_id = "run-8843"
  )
)

edit_plan@changes[, c("class", "record_id", "action", "changed_fields")]

if (edit_plan@valid) {
  graft_commit(okf_store, edit_plan)
  graft_sync(okf_store)
}
```

The loop is explicit at every step:

``` text
accepted revisions -> sync -> readable files -> agent edits -> review -> commit -> sync
```

An agent with filesystem access can therefore work in the surface it
handles best without gaining a second, unreviewed route into accepted
knowledge. See [Work with open
knowledge](https://jameshwade.github.io/graft/articles/open-knowledge-format.md)
for the full working tree.

## What the tools cannot do

The boundary is worth stating plainly, because it is what makes a
model-driven read safe to enable:

- No SQL, connection object, filesystem path, or network argument is
  reachable from a tool definition.
- No tool writes. Acceptance happens only through
  [`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md),
  in R, from a plan someone or some policy approved.
- Graph traversal is bounded in hops, nodes, and edges; every tabular
  result is bounded by an explicit limit.
- Only manifest-declared public fields are searchable and returnable.
  Fields the contract marks sensitive — `display: restricted` in
  data-dict — are not exposed by a tool because they are dropped from
  the underlying read.
- The host decides which provider receives the tools and remains
  responsible for tool authorization.

``` r

graft_close(store)
```

Read [Retrieve accepted
knowledge](https://jameshwade.github.io/graft/articles/retrieval.md) for
the read operations behind the tools, [Review knowledge
changes](https://jameshwade.github.io/graft/articles/knowledge-change-control.md)
for plans and commit preconditions, and
[Architecture](https://jameshwade.github.io/graft/articles/architecture.md)
for how the revision ledger and its derived projections fit together.
