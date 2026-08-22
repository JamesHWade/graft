# Changelog

## graft 0.0.0.9000

- A new
  [`vignette("agents")`](https://jameshwade.github.io/graft/articles/agents.md)
  documents how Graft is used from an agent host: bounded read-only
  tools, snapshot-pinned sessions, agent-authored proposals that pass
  through validation and review, and file-editing agents working through
  the OKF tree. Getting started, the README, and the site home page now
  show the same path.
- [`graft_measure()`](https://jameshwade.github.io/graft/reference/graft_measure.md)
  and
  [`graft_measures()`](https://jameshwade.github.io/graft/reference/graft_measures.md)
  add governed measures inspired by the semantic layer in
  [posit-dev/commons](https://github.com/posit-dev/commons):
  declarative, reviewed calculations stored as `GraftMeasure` records
  with full plan/review/commit history, validated at plan time,
  evaluated over accepted state or a pinned `GraftView`, and seeded from
  data-dict contract `definitions` at
  [`graft_open()`](https://jameshwade.github.io/graft/reference/graft_open.md)
  ([\#19](https://github.com/JamesHWade/graft/issues/19)).
- [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
  adds a fifth bounded `graft_measure` tool when the store has accepted
  measures and gives every tool result one canonical nested receipt
  identifying its exact accepted boundary and schema; measure receipts
  also identify the accepted definition
  ([\#19](https://github.com/JamesHWade/graft/issues/19),
  [\#23](https://github.com/JamesHWade/graft/issues/23)).
- Graft v0.1 replaces the pre-production `kg_*` API, bundled
  applications, Tempest adapter, physical migration subsystem, and dual
  authoritative record tables with an 18-function revision-first package
  boundary.
- The pkgdown site now starts with ordinary tables and a shipped
  data-dict example, creates a blank store explicitly, demonstrates
  change history, and introduces LinkML when richer semantic graph
  modeling is needed.
- Canonical record and identity JSON now preserves finite numeric inputs
  with round-trip-safe double serialization, normalizes signed zero, and
  rejects character numeric underflow so distinct values cannot collapse
  into one revision or identity digest.
- Store format 3 makes immutable record revisions authoritative and
  treats current records, multivalued relations, graph edges, and search
  state as verified rebuildable projections.
- [`graft_at()`](https://jameshwade.github.io/graft/reference/graft_at.md)
  and
  [`graft_snapshot()`](https://jameshwade.github.io/graft/reference/graft_snapshot.md)
  capture serializable accepted-knowledge references and create
  immutable read views; read-only tools built from a view remain pinned
  to that boundary.
- [`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md)
  and
  [`graft_ingest()`](https://jameshwade.github.io/graft/reference/graft_ingest.md)
  atomically accept immutable reviewed plans through set-based DuckDB
  operations and return ordinary summaries with insert, update, match,
  observation, replay, and timing details.
- [`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md),
  [`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md),
  [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md),
  and
  [`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md)
  provide bounded deterministic retrieval directly from the
  authoritative revision ledger, including exact historical types,
  evidence, graph traversal, and integrity diagnosis.
- [`graft_open()`](https://jameshwade.github.io/graft/reference/graft_open.md)
  and
  [`graft_close()`](https://jameshwade.github.io/graft/reference/graft_close.md)
  manage the only DuckDB backend through an invariant-checked S7
  `GraftStore`, including ownership-aware connection cleanup and
  read-only reopen behavior.
- [`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
  and
  [`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
  produce the same tamper-evident S7 `GraftCommitPlan` for ordinary
  records and edited OKF knowledge without persistent writes.
- [`graft_provenance()`](https://jameshwade.github.io/graft/reference/graft_provenance.md)
  creates immutable S7 provenance carrying producer, run, replay, and
  JSON metadata identity.
- [`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md)
  compiles LinkML or the supported `graft-table-v1` data-dict profile
  into the same invariant-checked contract. YAML authoring uses the
  optional data-dict CLI, committed resolved JSON remains R-only, and
  unsupported provider semantics fail closed.
- [`graft_status()`](https://jameshwade.github.io/graft/reference/graft_status.md)
  and
  [`graft_sync()`](https://jameshwade.github.io/graft/reference/graft_sync.md)
  inspect and explicitly synchronize the deterministic OKF working tree
  without making it an independent source of accepted knowledge.
- [`graft_view_snapshot()`](https://jameshwade.github.io/graft/reference/graft_view_snapshot.md)
  returns an isolated, path-free copy of the exact immutable snapshot
  retained by a `GraftView`.
