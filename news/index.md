# Changelog

## graft 0.0.0.9000

- Added a runnable project-memory Shiny example
  (`inst/examples/project-memory`) and an offline
  [`vitals::Task`](https://vitals.tidyverse.org/reference/Task.html)
  recall evaluation article
  ([\#41](https://github.com/JamesHWade/graft/issues/41),
  [\#112](https://github.com/JamesHWade/graft/issues/112)).
- Initial development version providing persistent immutable artifacts,
  exact dependency selections, host review decisions, bounded agent
  recall, and shared vocabulary releases.
- [`graft_accept()`](https://jameshwade.github.io/graft/reference/graft_accept.md),
  [`graft_withdraw()`](https://jameshwade.github.io/graft/reference/graft_withdraw.md),
  [`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md),
  [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md),
  and
  [`graft_streams()`](https://jameshwade.github.io/graft/reference/graft_streams.md)
  record and inspect append-only host review decisions with predecessor
  checks and idempotent request keys.
- [`graft_publish_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_publish_vocabulary.md)
  and
  [`graft_read_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_read_vocabulary.md)
  publish and reopen pinned `data-dict` concepts, relationships,
  qualified bindings, and `commons`-compatible Markdown context as
  `VocabularyRelease` values
  ([\#75](https://github.com/JamesHWade/graft/issues/75),
  [\#115](https://github.com/JamesHWade/graft/issues/115)).
- [`graft_save()`](https://jameshwade.github.io/graft/reference/graft_save.md),
  [`graft_save_file()`](https://jameshwade.github.io/graft/reference/graft_save_file.md),
  [`graft_read()`](https://jameshwade.github.io/graft/reference/graft_read.md),
  [`graft_select()`](https://jameshwade.github.io/graft/reference/graft_select.md),
  and
  [`graft_read_selection()`](https://jameshwade.github.io/graft/reference/graft_read_selection.md)
  preserve exact content-addressed artifacts and verified dependency
  closures as typed `ArtifactRef`, `Artifact`, and `ArtifactSelection`
  S7 values.
- [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  and
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md)
  create and reopen local file-backed and transaction-scoped PostgreSQL
  artifact stores as S7 `ArtifactStore` handles, with per-stream
  advisory file locks on local stores for multi-process Shiny
  deployments.
- [`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
  exposes bounded, read-only reviewed memory as an `ellmer` `ToolDef`
  with `shinychat` display metadata and plain-data `@extra$graft`
  consultation metadata for `scans`, compatible with `deputy` permission
  modes and local `mcptools` MCP servers
  ([\#110](https://github.com/JamesHWade/graft/issues/110),
  [\#113](https://github.com/JamesHWade/graft/issues/113),
  [\#128](https://github.com/JamesHWade/graft/issues/128)).
- [`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
  exposes bounded multi-stream discovery and recall tools
  (`list_project_memory` and `recall_project_memory`) with per-stream
  host eligibility and allowlist enforcement, alongside a `ragnar`
  composition recipe
  ([\#111](https://github.com/JamesHWade/graft/issues/111)).
