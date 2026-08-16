# How graft stores and retrieves knowledge

Most Graft workflows begin with source records and a contract, not an
existing knowledge store.
[`graft_open()`](https://jameshwade.github.io/graft/reference/graft_open.md)
creates a blank local store when its path does not exist. From there,
candidate records are checked in a read-only plan before one transaction
accepts them as revisions.

The accepted revision ledger is the source of record content and
history. Current records, search indexes, supported graph relationships,
and the Open Knowledge Format (OKF) working tree are read views built
from that ledger. Snapshot views select those reads at one accepted
commit boundary.

Swipe to explore the diagram →

![A data-dict or LinkML contract compiles into Graft. OKF exchanges
readable proposals and projections with Graft. Graft commits to and
retrieves accepted revisions from
DuckDB.](../reference/figures/okf-linkml-duckdb-system.svg)

The contract defines valid records; the ledger records what was
accepted; OKF is a readable proposal and projection surface.

## From a contract to accepted knowledge

### Start with a source contract

For related tables, start with data-dict. Graft maps its supported
tables, columns, primary keys, scalar types, enums, sensitivity
declarations, and foreign keys into a compiled `.graft.json` contract.
Planning validates the mapped foreign keys, but Graft does not turn them
into graph traversal edges.

Move to LinkML when the domain needs ontology identifiers, inheritance,
polymorphic references, or semantic statements. An ordinary LinkML
object reference is also a validation rule, not automatically a graph
edge. The semantic graph projection is driven by classes that the
compiled contract declares as graph-producing edges or semantic
statements.

Both providers compile to the same runtime contract. A provider defines
valid record meaning; it does not store accepted records or provide
another mutation path. [Contract compiler
boundaries](https://jameshwade.github.io/graft/articles/contract-compilers.md)
documents the provider-specific dependencies, supported profiles, and
mapping limits.

### Review a plan before writing

[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
accepts named data frames and explicit provenance. It normalizes values,
resolves identity, validates the complete candidate set, and compares
the candidates with current accepted heads. The result separates
inserts, updates, matches, and issues so a caller can decide whether the
proposed change is correct.

Planning writes no accepted records or provenance. The plan binds its
result to the store identity, schema digest, expected record heads,
idempotency state, and a deterministic digest. If any of those
preconditions changes, the old plan cannot be committed.

### Commit one checked plan

[`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md)
rechecks the plan, store, active contract, write capability, idempotency
state, and expected heads immediately before mutation. Records,
provenance, and identity decisions commit in one transaction.

Each accepted revision retains its record content, predecessor, changed
fields, schema digest, accepted batch, and producer provenance.
Historical state comes from those accepted revisions rather than from
logs or overwritten current tables.

### Build read views from revisions

Graft derives current record heads, identifiers, search data, declared
semantic relationships, and the OKF working tree from accepted revisions
and the active contract. These views can be checked and rebuilt; they do
not accept writes on their own.

That separation matters when a projection is stale or damaged: the
accepted revision chain remains the recovery source.

## What appears in the semantic graph

Graft does not infer graph meaning from every field that contains
another record’s ID.

- A supported data-dict foreign key validates its concrete target.
- An ordinary LinkML object-reference slot validates its declared range.
- A LinkML class with a compiled edge or semantic-statement role
  contributes edges to the semantic graph projection.
- Narrative statements remain accepted, searchable knowledge but do not
  become semantic subject-predicate-object edges.

This keeps a database join, a validated reference, and a domain
assertion from being treated as interchangeable. See [Add graph
semantics with
LinkML](https://jameshwade.github.io/graft/articles/linkml-schema.md)
for a working semantic-statement example.

## Why Graft uses S7 at stable boundaries

S7 protects the objects whose invariants must survive across function
calls:

- `GraftSchema` owns a validated compiled contract and its digests.
- `GraftProvenance` identifies the producer event and replay boundary.
- `GraftCommitPlan` owns the candidate change set and commit
  preconditions.
- `GraftStore` owns store identity and private connection state.
- `GraftSnapshot` owns a serializable accepted commit identity.
- `GraftView` binds that snapshot to a live store for read-only
  retrieval.

Records remain data frames, candidate collections remain named lists,
and retrieval results remain data frames or lists. Graft does not create
an R class for every data-dict table or LinkML class; the compiled
contract remains the domain type system.

## DuckDB stays behind the package API

The current store uses embedded DuckDB, but public functions describe
user operations: open, plan, commit, retrieve, inspect, and synchronize.
No public function exposes internal table names or accepts raw SQL.

The store owns its connection, transactions, format version, migrations,
and projection maintenance. A future backend change therefore need not
change the public workflow.

## Failed preconditions do not become partial changes

The package makes common failure states explicit:

- invalid candidates return collected issues and cannot commit;
- an altered plan fails digest verification;
- a changed contract or record head makes a plan stale;
- a transaction failure accepts none of the batch;
- an OKF edit remains a proposal until reviewed and committed;
- projection drift can be detected and repaired from revisions; and
- retrieval limits and truncation are reported.

There is no force flag that turns a failed precondition into acceptance.
Create a new plan against the current state instead.

## OKF is a readable working surface

Swipe to explore the diagram →

![Accepted revisions synchronize to readable files; edits return through
review and commit.](../reference/figures/okf-acceptance-loop.svg)

Readable file edits remain proposals until they pass the same plan and
commit checks as records submitted from R.

For code, start with [Getting
started](https://jameshwade.github.io/graft/articles/getting-started.md).
Continue with
[data-dict](https://jameshwade.github.io/graft/articles/data-dict-schema.md),
[change
control](https://jameshwade.github.io/graft/articles/knowledge-change-control.md),
and
[retrieval](https://jameshwade.github.io/graft/articles/retrieval.md).
Add
[LinkML](https://jameshwade.github.io/graft/articles/linkml-schema.md)
when the domain needs semantic graph behavior, and use [open
knowledge](https://jameshwade.github.io/graft/articles/open-knowledge-format.md)
for the readable working surface.
