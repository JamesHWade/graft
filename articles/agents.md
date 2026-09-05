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

See [Reuse narrative
knowledge](https://jameshwade.github.io/graft/articles/ecosystem.md) for
an offline narrative example, real ellmer/Deputy/dsprrr recipes,
long-result behavior and worker ownership.

## Hand the agent bounded tools

Install ellmer 0.5.0 or later for
[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
and
[`graft_verify()`](https://jameshwade.github.io/graft/reference/graft_verify.md).
The [compatibility
guide](https://jameshwade.github.io/graft/articles/compatibility.md)
records the tested versions and the unpinned Commons setup.

[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
returns [ellmer](https://ellmer.tidyverse.org/) tool definitions for
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md),
[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md),
[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md),
and
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md),
plus
[`graft_dictionary()`](https://jameshwade.github.io/graft/reference/graft_dictionary.md)
for data-dict contracts:

``` r

tools <- graft_tools(store)
names(tools)
#> [1] "graft_find"       "graft_get"        "graft_query"
#> [4] "graft_history"    "graft_dictionary"
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

When the accepted ledger contains `GraftDefinition` records,
[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
also supplies `graft_definitions` and one `graft_calculate` tool. The
first discovers metrics, filters, derived values, dependencies, and
eligible columns. The second combines same-table definitions and public
dimensions at one exact boundary; it never accepts SQL.

Every tool result is a named list with `result`, `truncated`, `limit`,
and one canonical `receipt`. A model that receives a bounded prefix is
told that it received one, rather than silently reasoning over a partial
answer:

``` r

str(tools$graft_find(query = "Lois", class = "person", limit = 5), max.level = 2)
#> List of 4
#>  $ result   :'data.frame': 1 obs. of 5 variables:
#>  $ truncated: logi FALSE
#>  $ limit    : int 5
#>  $ receipt  :List of 3
#>   ..$ store   :List of 1
#>   ..$ boundary:List of 4
#>   ..$ schema  :List of 2
```

The receipt names the store, accepted batch and commit order, and both
schema digests. Live tools pin that state for one invocation; tools
built from a `GraftView` also carry its immutable snapshot identifier. A
calculation result adds the complete accepted definition closure under
`receipt$definitions`.

## Discover meaning before reading records

Data-dict-backed stores expose
[`graft_dictionary()`](https://jameshwade.github.io/graft/reference/graft_dictionary.md)
to R callers and as an ellmer tool. LinkML stores retain their existing
tools and report that a data-dict contract is required if dictionary
discovery is called directly.

These calls need no model or API key:

``` r

view <- graft_at(store, graft_snapshot(store))
context <- graft_dictionary(view, table = "person", field = "full_name")
context$result$entries

tools <- graft_tools(view)
metadata <- tools$graft_dictionary(table = "person", field = "full_name")
people <- tools$graft_find(query = "Lois", class = "person", limit = 5)
identical(metadata$receipt, people$receipt)
#> [1] TRUE
```

The entries distinguish supported contract properties such as
requiredness from descriptive labels, units, relationships, glossary
terms, and assertions. Unsupported profile semantics are identified
explicitly. Assertion prose is never executed. Accepted definitions
remain available through
[`graft_definitions()`](https://jameshwade.github.io/graft/reference/graft_definitions.md)
rather than being copied from dictionary source text.

Use `limit` and the returned `result$next_offset` for subsequent pages.
Each page contains at most 100 entries, and each string cell is capped
at 2,000 characters. `text_truncated` identifies clipped entries; the
outer `truncated` flag reports clipping or another page. A selected
field still includes dataset, table, glossary, and adapter semantics
needed to interpret it.

Restricted columns and relationships with restricted endpoints are
omitted. Examples, observed ranges, source locators, and arbitrary
extension metadata are excluded. Public prose is not content-scrubbed:
authors must keep private information out of public descriptions,
assertions, and glossary entries. Relationships report resolved public
endpoint pairs and cardinality. Pairs do not encode operators or
aliases, so discovery does not reconstruct joins. Assertions likewise
require resolved public column references; dataset assertions and
assertions without resolved references are omitted.

Dictionary discovery follows the generic-read verification rule. Quoting
its returned prose can support a `cited` answer; an uncited discovery
call fails closed. Combining it with a calculation cannot produce
`verified` evidence. A pinned view retains the same dictionary and
boundary receipt after later commits.

## Use the same boundary with Commons

[`graft_commons_data_source()`](https://jameshwade.github.io/graft/reference/graft_commons_data_source.md)
copies selected public class tables, applicable normalized relations,
and accepted definitions into a detached source created through
Commons’s public API:

``` r

commons_source <- graft_commons_data_source(view, classes = "person")
layer <- commons::semantic_layer(commons_source)
```

Commons owns that copy, its file measures, and its fallback query paths.
It never receives Graft’s live DuckDB connection, and later Graft
commits do not change an existing Commons source.

## Verify recorded answers offline

After the host has recorded a chat,
[`graft_verify()`](https://jameshwade.github.io/graft/reference/graft_verify.md)
classifies its completed, text-bearing assistant answers from the trace
already held by ellmer. It is a deterministic, read-only inspection: it
does not call the model, use the network, reopen the store, or
authenticate identifiers in a receipt.

``` r

verification <- graft_verify(chat)
verification[, c("answer_index", "turn_index", "answer_text", "label")]
verification$reason_codes
verification$diagnostics
```

The result has one row per answer, excluding tool-only turns and partial
answers. Each row includes the answer text, its label, stable reason
codes, the receipts and paired tool calls considered, matched citations,
and any diagnostics.

The three labels classify the recorded evidence path:

- **Verified** (`"verified"`) means the window contains only successful
  `graft_calculate` calls with valid governed receipts.
- **Cited** (`"cited"`) means every successful generic Graft result is
  independently matched to an explicit quotation or Markdown blockquote
  in the answer. A generic read caps mixed calculation and generic
  evidence at this label.
- **Untrusted** (`"untrusted"`) covers missing evidence, unmatched
  generic reads, non-Graft tools, tool errors, malformed receipts, and
  unsupported trace shapes.

Citation candidates are normalized for whitespace, Markdown emphasis,
typographic quotation marks, and dashes. They must contain at least ten
characters and match a textual value in the bounded result with a
case-sensitive fixed match. Unquoted overlap, receipt fields, tool
arguments, and unrelated chat text are not citation evidence.

This is deterministic provenance classification, not fact-checking or
cryptographic authentication.
[`graft_verify()`](https://jameshwade.github.io/graft/reference/graft_verify.md)
does not prove that every claim follows from the cited text, and it does
not reopen a store to authenticate receipt identifiers.

Diagnostics are separate from trust. For example, valid calculation
results from mixed accepted boundaries are reported in `diagnostics`,
but do not downgrade an otherwise valid `"verified"` label.

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

## Generate proposals from the accepted contract

[`graft_proposal_type()`](https://jameshwade.github.io/graft/reference/graft_proposal_type.md)
builds an ellmer structured-output type from the same accepted data-dict
contract that planning validates. Select tables and, if needed, a subset
of their public columns:

``` r

type <- graft_proposal_type(
  view,
  tables = "person",
  fields = list(person = c("id", "full_name", "job_title")),
  max_rows = 20
)

raw <- chat$chat_structured(
  "Propose records from the supplied source text; do not invent identifiers.",
  type = type,
  convert = FALSE
)
```

Keep `convert = FALSE` so the raw object reaches Graft without field
dropping or coercion by an upstream converter. Selected tables are
arrays of records. All selected properties are explicit in the schema;
optional values can be JSON null. Lists are flat and their elements
cannot be null. Foreign keys are string IDs whose existence is checked
during planning, including references to other records in the same
proposal.

The schema excludes restricted columns, source locations, examples, and
free-form metadata. Selections must contain every required column. A
table with a required restricted column needs the host’s ordinary
[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
path instead. Provider-specific structured-output restrictions can still
apply; Graft validates returned data independently of provider
guarantees.

This offline example starts with a malformed candidate and corrects it
before review. It uses the store from the setup above and makes no model
call:

``` r

raw <- list(person = list(list(
  id = "person:jimmy-olsen", full_name = NULL, job_title = "Photographer"
)))
provenance <- graft_provenance(
  "directory-agent", run_id = "proposal-demo",
  idempotency_key = "proposal-demo-1"
)
invalid <- graft_proposal_plan(store, raw, provenance, max_rows = 20)
invalid@issues

raw$person[[1]]$full_name <- "Jimmy Olsen"
plan <- graft_proposal_plan(store, raw, provenance, max_rows = 20)
plan@valid
plan@changes
plan@issues

host_approved <- FALSE # Set only after the host's review decision.
if (host_approved && plan@valid) {
  graft_commit(store, plan)
}
```

Malformed objects, unknown or restricted fields, and incompatible JSON
value types raise `graft_validation_error`. Validly shaped but invalid
candidates return plan issues, including missing required values,
invalid enums, and unknown references. No malformed row is silently
dropped. Optional missing values follow complete-record planning
semantics; these proposals are not patches.

Keep the reviewed `plan` to retry `graft_commit(store, plan)` safely.
Creating a new plan after acceptance changes its preconditions, and
reusing the committed idempotency key for that different plan fails
rather than duplicating data.

The same type can be used by a dsprrr signature:

``` r

sig <- dsprrr::signature(
  inputs = list(text = dsprrr::input("text", description = "Source text")),
  output_type = type
)
```

This composes the public type boundary; it does not certify all dsprrr
modules or introduce a Graft chat/session wrapper. The host still owns
generation, credentials, retries, and acceptance. Run
`Rscript tools/check-proposal-dsprrr.R` from the checkout to check the
installed dsprrr signature interface offline.

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
- Set an `idempotency_key` per proposed batch. Retry the retained
  reviewed plan so commit replay does not create duplicate revisions.

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
