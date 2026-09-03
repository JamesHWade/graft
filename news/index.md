# Changelog

## graft 0.0.0.9000

- `GraftSchema` and `GraftStore` now print concise identity, contract,
  and lifecycle summaries instead of recursively dumping their internal
  state.
- A new
  [`vignette("agents")`](https://jameshwade.github.io/graft/articles/agents.md)
  documents how Graft is used from an agent host: bounded read-only
  tools, snapshot-pinned sessions, agent-authored proposals that pass
  through validation and review, and file-editing agents working through
  the OKF tree. Getting started, the README, and the site home page now
  show the same path.
- [`graft_calculate()`](https://jameshwade.github.io/graft/reference/graft_calculate.md)
  and
  [`graft_definitions()`](https://jameshwade.github.io/graft/reference/graft_definitions.md)
  replace the pre-production singular measure API with composable,
  data-dict-compatible metrics, filters, and derived values over one
  accepted public table, including plan-time type checking, pinned
  evaluation, grouping, typed predicates, dependency closure, and
  canonical definition receipts
  ([\#21](https://github.com/JamesHWade/graft/issues/21)).
- [`graft_calculate()`](https://jameshwade.github.io/graft/reference/graft_calculate.md)
  now fails closed before evaluating a public table or normalized
  relation that exceeds the hard calculation-input bound.
- [`graft_changes()`](https://jameshwade.github.io/graft/reference/graft_changes.md)
  lists every record whose accepted revision differs between two
  committed boundaries (snapshots, batch IDs, or times) as one bounded
  store-wide table with the action, revision count, the public fields
  whose values differ between the two boundary revisions, and the latest
  public record, so a host can ask “what was accepted since this
  snapshot” without looping over
  [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
  ([\#32](https://github.com/JamesHWade/graft/issues/32)).
- [`graft_commons_data_source()`](https://jameshwade.github.io/graft/reference/graft_commons_data_source.md)
  materializes selected public tables, normalized relations, prose, and
  accepted definitions at one immutable boundary, then returns a
  detached source owned by an optional, exactly tested Commons
  integration ([\#21](https://github.com/JamesHWade/graft/issues/21)).
- [`graft_contract_version()`](https://jameshwade.github.io/graft/reference/graft_contract_version.md)
  reports the semantic consumer contract version together with the
  persisted store, plan, snapshot, manifest, and OKF format versions,
  giving downstream packages a stable value to pin against instead of a
  git commit or a namespace digest
  ([\#32](https://github.com/JamesHWade/graft/issues/32)).
- [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
  adds bounded definition discovery and one composite calculation tool
  when accepted definitions exist; every result carries one canonical
  receipt for its exact accepted boundary and schema, while calculation
  receipts identify the full accepted definition closure
  ([\#21](https://github.com/JamesHWade/graft/issues/21),
  [\#23](https://github.com/JamesHWade/graft/issues/23)).
- [`graft_verify()`](https://jameshwade.github.io/graft/reference/graft_verify.md)
  classifies every completed text-bearing assistant answer in a recorded
  ellmer chat from deterministic, offline Graft evidence: valid
  governed-calculation-only evidence is verified, while missing,
  non-Graft, errored, malformed, or citation-unmatched read evidence
  fails closed as untrusted with stable reasons
  ([\#24](https://github.com/JamesHWade/graft/issues/24)).
- [`graft_verify()`](https://jameshwade.github.io/graft/reference/graft_verify.md)
  now labels successful generic Graft reads as cited only when every
  contributing result is independently matched to an explicit quotation
  or Markdown blockquote; mixed calculation and generic evidence is
  capped at cited, while unmatched or failed paths remain untrusted
  ([\#25](https://github.com/JamesHWade/graft/issues/25)).
- Graft v0.1 replaces the pre-production `kg_*` API, bundled
  applications, Tempest adapter, physical migration subsystem, and dual
  authoritative record tables with a focused revision-first package
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
- [`graft_open()`](https://jameshwade.github.io/graft/reference/graft_open.md)
  now seeds contract definitions only when initializing a new store, so
  reopening with edited definitions cannot bypass plan review;
  package-owned DuckDB connections also use isolated extension storage.
- [`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
  and
  [`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
  produce the same tamper-evident S7 `GraftCommitPlan` for ordinary
  records and edited OKF knowledge without persistent writes.
- [`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md)
  and
  [`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
  now carry a `disposition` column on `@changes`: `duplicate`, `new`, or
  `revision` restate the ledger action for accepted statements, while
  `supersedes`, `superseded`, `contradicts`, and `contradicted` surface
  statement-level relations declared by the staged records through
  `superseded_by` and `contradicts` evidence, attached to the declaring
  row so they remain visible when the accepted target is not restaged;
  the plan format version is now `0.2.0`
  ([\#32](https://github.com/JamesHWade/graft/issues/32)).
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
