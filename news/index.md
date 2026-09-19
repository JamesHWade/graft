# Changelog

## graft 0.0.0.9000

- Graft now contains persistent artifacts, exact dependency selections,
  host decision history, and shared vocabulary. Native graph stores,
  LinkML compilation, commit plans, snapshots, calculations, managed OKF
  trees, and graph agent adapters are removed without compatibility
  wrappers. The website describes the supported artifact architecture
  ([\#74](https://github.com/JamesHWade/graft/issues/74)).
- [`graft_artifact_decide()`](https://jameshwade.github.io/graft/reference/graft_artifact_decide.md),
  [`graft_artifact_read_decision()`](https://jameshwade.github.io/graft/reference/graft_artifact_decide.md),
  and
  [`graft_artifact_reuse()`](https://jameshwade.github.io/graft/reference/graft_artifact_decide.md)
  retain explicit host acceptance and withdrawal, guard predecessors and
  identical retries, and separate historical inspection from current
  purpose-bound consultation
  ([\#73](https://github.com/JamesHWade/graft/issues/73)).
- [`graft_artifact_select()`](https://jameshwade.github.io/graft/reference/graft_artifact_select.md)
  and
  [`graft_artifact_read_selection()`](https://jameshwade.github.io/graft/reference/graft_artifact_select.md)
  retain and verify bounded exact dependency closures
  ([\#72](https://github.com/JamesHWade/graft/issues/72)).
- [`graft_artifact_store()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md),
  [`graft_artifact_save()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md),
  and
  [`graft_artifact_read()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md)
  retain bounded opaque bytes as immutable revisions with verified exact
  reads ([\#71](https://github.com/JamesHWade/graft/issues/71)).
- [`graft_artifact_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_artifact_store_postgres.md)
  retains artifacts, selections, and decisions in host-selected
  PostgreSQL scopes with transaction rollback and serialized scope
  writes ([\#47](https://github.com/JamesHWade/graft/issues/47)).
- [`graft_contract_version()`](https://jameshwade.github.io/graft/reference/graft_contract_version.md)
  reports consumer contract 3.0.0 and the retained artifact, selection,
  decision, vocabulary, binding, and vocabulary-release formats.
  Existing artifact identities are unchanged
  ([\#74](https://github.com/JamesHWade/graft/issues/74)).
- [`graft_vocabulary_publish()`](https://jameshwade.github.io/graft/reference/graft_vocabulary_publish.md)
  and
  [`graft_vocabulary_read()`](https://jameshwade.github.io/graft/reference/graft_vocabulary_publish.md)
  retain shared concepts, relationships, exact data-dict bindings,
  source bytes, and literal context across dictionary corrections
  ([\#76](https://github.com/JamesHWade/graft/issues/76)).
