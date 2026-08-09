# Changelog

## graft 0.0.0.9000

- Graft v0.1 replaces the pre-production `kg_*` API, bundled
  applications, Tempest adapter, physical migration subsystem, and dual
  authoritative record tables with a 15-function revision-first package
  boundary.
- Canonical record and identity JSON now preserves finite numeric inputs
  with round-trip-safe double serialization, normalizes signed zero, and
  rejects character numeric underflow so distinct values cannot collapse
  into one revision or identity digest.
- Store format 3 makes immutable record revisions authoritative and
  treats current records, multivalued relations, graph edges, and search
  state as verified rebuildable projections.
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
  loads compiled manifests or compiles LinkML and optional data-dict
  contracts into an invariant-checked S7 `GraftSchema`; the strict
  `graft-table-v1` adapter separates YAML source-spec and resolved JSON
  export-format versions, runs YAML preflight and CLI export from one
  byte snapshot, guards CLI provenance against executable replacement,
  publishes a digest-bound public manifest with examples, ranges,
  origins, and source locators redacted, rejects unsafe JSON numeric
  tokens, `number(id)`, and primary IDs that are also foreign keys,
  normalizes optional blank foreign keys, and enforces supported
  datetime forms, while trusted resolved JSON avoids a required CLI
  dependency.
- [`graft_schema()`](https://jameshwade.github.io/graft/reference/graft_schema.md)
  now fails closed when LinkML custom types or unsupported schema,
  class, slot, enum, or permissible-value semantics would be discarded;
  resolved data-dict versions retain their upstream lexical contract,
  provider metadata is allowlisted, and `foreign_key` constraints must
  agree with resolved references.
- [`graft_status()`](https://jameshwade.github.io/graft/reference/graft_status.md)
  and
  [`graft_sync()`](https://jameshwade.github.io/graft/reference/graft_sync.md)
  inspect and explicitly synchronize the deterministic OKF working tree
  without making it an independent source of accepted knowledge.
- [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
  creates four bounded read-only ellmer tools that delegate to the
  public retrieval and history operations.
