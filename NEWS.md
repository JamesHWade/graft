# graft 0.0.0.9000

* Graft v0.1 replaces the pre-production `kg_*` API, bundled applications, Tempest adapter, physical migration subsystem, and dual authoritative record tables with a 15-function revision-first package boundary.
* Store format 3 makes immutable record revisions authoritative and treats current records, multivalued relations, graph edges, and search state as verified rebuildable projections.
* `graft_commit()` and `graft_ingest()` atomically accept immutable reviewed plans through set-based DuckDB operations and return ordinary summaries with insert, update, match, observation, replay, and timing details.
* `graft_find()`, `graft_get()`, `graft_history()`, and `graft_query()` provide bounded deterministic retrieval directly from the authoritative revision ledger, including exact historical types, evidence, graph traversal, and integrity diagnosis.
* `graft_open()` and `graft_close()` manage the only DuckDB backend through an invariant-checked S7 `GraftStore`, including ownership-aware connection cleanup and read-only reopen behavior.
* `graft_plan()` and `graft_review()` produce the same tamper-evident S7 `GraftCommitPlan` for ordinary records and edited OKF knowledge without persistent writes.
* `graft_provenance()` creates immutable S7 provenance carrying producer, run, replay, and JSON metadata identity.
* `graft_schema()` loads compiled manifests or compiles LinkML YAML into an invariant-checked S7 `GraftSchema`; LinkML remains the domain type system and data frames remain the bulk record boundary.
* `graft_status()` and `graft_sync()` inspect and explicitly synchronize the deterministic OKF working tree without making it an independent source of accepted knowledge.
* `graft_tools()` creates four bounded read-only ellmer tools that delegate to the public retrieval and history operations.
