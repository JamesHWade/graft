# graft 0.0.0.9000

* A shipped `artifacts` data-dict contract (`inst/extdata/artifacts.data-dict.yaml`) models kept assistant artifacts: artifacts, versions and their bytes, provenance with the producing runtime, citations, checked evidence, and directions.
* Opening a store that another process holds now signals `graft_store_busy` (a `graft_backend_error`) with retry guidance. DuckDB lets one process hold a file at a time, even for reading.
* reticulate moved from Imports to Suggests: it is needed only to compile LinkML YAML, so stores opened from data-dict or compiled `.graft.json` contracts no longer install it.
* Graft v0.1 replaces the pre-production `kg_*` API, bundled applications, Tempest adapter, physical migration subsystem, and dual authoritative record tables with a 15-function revision-first package boundary.
* The pkgdown site now starts with ordinary tables and a shipped data-dict example, creates a blank store explicitly, demonstrates change history, and introduces LinkML when richer semantic graph modeling is needed.
* Canonical record and identity JSON now preserves finite numeric inputs with round-trip-safe double serialization, normalizes signed zero, and rejects character numeric underflow so distinct values cannot collapse into one revision or identity digest.
* Store format 3 makes immutable record revisions authoritative and treats current records, multivalued relations, graph edges, and search state as verified rebuildable projections.
* `graft_commit()` and `graft_ingest()` atomically accept immutable reviewed plans through set-based DuckDB operations and return ordinary summaries with insert, update, match, observation, replay, and timing details.
* `graft_find()`, `graft_get()`, `graft_history()`, and `graft_query()` provide bounded deterministic retrieval directly from the authoritative revision ledger, including exact historical types, evidence, graph traversal, and integrity diagnosis.
* `graft_open()` and `graft_close()` manage the only DuckDB backend through an invariant-checked S7 `GraftStore`, including ownership-aware connection cleanup and read-only reopen behavior.
* `graft_plan()` and `graft_review()` produce the same tamper-evident S7 `GraftCommitPlan` for ordinary records and edited OKF knowledge without persistent writes.
* `graft_provenance()` creates immutable S7 provenance carrying producer, run, replay, and JSON metadata identity.
* `graft_schema()` compiles LinkML or the supported `graft-table-v1` data-dict profile into the same invariant-checked contract. YAML authoring uses the optional data-dict CLI, committed resolved JSON remains R-only, and unsupported provider semantics fail closed.
* `graft_status()` and `graft_sync()` inspect and explicitly synchronize the deterministic OKF working tree without making it an independent source of accepted knowledge.
* `graft_tools()` creates four bounded read-only ellmer tools that delegate to the public retrieval and history operations.
