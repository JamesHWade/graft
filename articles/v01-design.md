# The v0.1 design

v0.1 is a deliberate pre-production cutover, not a compatibility
release. The package now teaches one revision-first model and exposes 18
functions around it. The older storage-shaped `kg_*` surface, parallel
write paths, and bundled demonstration applications are not part of this
design.

Existing development stores should be rebuilt from source records under
the current contract. graft does not include migration aliases or a
compatibility layer for the unreleased API.

## What became simpler

### One acceptance path

All candidate records become a `GraftCommitPlan`.
[`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md)
is the one internal function that accepts revisions.
[`graft_ingest()`](https://jameshwade.github.io/graft/reference/graft_ingest.md)
merely plans and commits when no separate review is required;
[`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
turns readable file edits into the same plan type.

There is no special OKF import mutation path, force-write path, or
direct current-record update.

### One authority for record content

Immutable revisions are authoritative. Current records, identity lookup,
search, semantic relationships, and OKF files are rebuildable
projections. This removes the need to reconcile multiple answers to
“what is current?”

### One public retrieval boundary

[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md),
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md),
[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md),
and
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
replace a larger family of storage- and projection-specific helpers.
Advanced reads are named, validated operations rather than arbitrary
SQL.
[`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md)
and
[`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md)
bind those reads to one accepted commit boundary.
[`graft_view_snapshot()`](https://jameshwade.github.io/graft/reference/graft_view_snapshot.md)
recovers that exact path-free boundary from a view.

### A smaller package scope

The package contains the reusable knowledge layer. Example applications
live outside the package so their Shiny, provider, and domain
dependencies do not define graft’s runtime or documentation
architecture. A public companion link will be added when that repository
is ready; the package site does not point to an unpublished location.

## The 18-function surface

| Lifecycle | Functions |
|----|----|
| Define and open | [`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md), [`graft_open()`](https://jameshwade.github.io/graft/reference/graft_open.md), [`graft_close()`](https://jameshwade.github.io/graft/reference/graft_close.md) |
| Propose and accept | [`graft_provenance()`](https://jameshwade.github.io/graft/reference/graft_provenance.md), [`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md), [`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md), [`graft_ingest()`](https://jameshwade.github.io/graft/reference/graft_ingest.md) |
| Retrieve and inspect | [`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md), [`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md), [`graft_view_snapshot()`](https://jameshwade.github.io/graft/reference/graft_view_snapshot.md), [`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md), [`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md), [`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md), [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md) |
| Synchronize and integrate | [`graft_sync()`](https://jameshwade.github.io/graft/reference/graft_sync.md), [`graft_status()`](https://jameshwade.github.io/graft/reference/graft_status.md), [`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md), [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md) |

The grouping follows user intent instead of internal subsystems.
Reference documentation uses the same four groups.

## Why S7, and why not everywhere

The redesign uses S7 for `GraftSchema`, `GraftProvenance`,
`GraftCommitPlan`, `GraftStore`, `GraftSnapshot`, and `GraftView`. These
objects own invariants that must survive across calls: contract digests,
producer semantics, commit preconditions, store and snapshot identity,
and connection-bound view state.

Records remain ordinary data frames, record sets remain named lists, and
read results remain ordinary lists or data frames. The compiled LinkML
or data-dict contract already supplies the domain type system. Mirroring
each domain class in S7 would create two class systems without
strengthening the acceptance boundary.

## Intentional non-goals

v0.1 does not promise:

- backward compatibility with the unreleased `kg_*` API;
- in-place migration from development store formats;
- mutation through SQL, agent tools, or OKF files;
- an ORM that maps every contract class or table to an R class;
- automatic contract transformations for historical payloads; or
- bundled workflow applications.

These exclusions keep the package small enough to reason about and leave
room to stabilize the correct semantics before production use.

## Start with the new model

Use [Getting
started](https://jameshwade.github.io/graft/articles/getting-started.md)
for the complete workflow,
[Architecture](https://jameshwade.github.io/graft/articles/architecture.md)
for the authority and projection model, and [Change
control](https://jameshwade.github.io/graft/articles/knowledge-change-control.md)
for the exact commit preconditions.
