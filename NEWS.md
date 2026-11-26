# graft 0.0.0.9000

* Added a runnable project-memory Shiny example (`inst/examples/project-memory`) and an offline `vitals::Task` recall evaluation article (#41, #112).
* Initial development version providing persistent immutable artifacts, exact dependency selections, host review decisions, bounded agent recall, and shared vocabulary releases.
* `graft_accept()`, `graft_withdraw()`, `graft_recall()`, `graft_history()`, and `graft_streams()` record and inspect append-only host review decisions with predecessor checks and idempotent request keys.
* `graft_publish_vocabulary()` and `graft_read_vocabulary()` publish and reopen pinned `data-dict` concepts, relationships, qualified bindings, and `commons`-compatible Markdown context as `VocabularyRelease` values (#75, #115).
* `graft_save()`, `graft_save_file()`, `graft_read()`, `graft_select()`, and `graft_read_selection()` preserve exact content-addressed artifacts and verified dependency closures as typed `ArtifactRef`, `Artifact`, and `ArtifactSelection` S7 values.
* `graft_store()` and `graft_store_postgres()` create and reopen local file-backed and transaction-scoped PostgreSQL artifact stores as S7 `ArtifactStore` handles, with per-stream advisory file locks on local stores for multi-process Shiny deployments.
* `graft_tool()` exposes bounded, read-only reviewed memory as an `ellmer` `ToolDef` with `shinychat` display metadata, compatible with `deputy` permission modes and local `mcptools` MCP servers (#110, #113).
