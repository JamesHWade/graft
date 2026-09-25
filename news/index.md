# Changelog

## graft 0.0.0.9000

- Graft provides persistent artifacts, exact dependency selections, host
  decision history, and shared vocabulary. Native graph stores, LinkML
  compilation, commit plans, snapshots, calculations, managed OKF trees,
  and graph agent adapters are removed without compatibility wrappers
  ([\#74](https://github.com/JamesHWade/graft/issues/74)).
- The public interface uses S7 store handles and typed references,
  content, selections, decisions, recall results, and vocabulary
  releases. The former artifact-prefixed functions are removed without
  compatibility aliases
  ([\#90](https://github.com/JamesHWade/graft/issues/90)).
- The getting-started guide and runnable project-memory example show how
  to give an ellmer agent in shinychat a reviewed notebook that survives
  new conversations and app restarts, including corrections with
  retained evidence
  ([\#41](https://github.com/JamesHWade/graft/issues/41)).
- [`graft_accept()`](https://jameshwade.github.io/graft/reference/graft_accept.md)
  and
  [`graft_withdraw()`](https://jameshwade.github.io/graft/reference/graft_withdraw.md)
  take a file lock per stream, so several R processes can record
  decisions in one local store, as a Shiny app on Posit Connect does;
  and a caller that waits longer than `graft_store(lock_timeout =)` gets
  a `graft_store_busy_error` with nothing recorded. The lock needs a
  file system that honours advisory locks. Consumer contract 4.1.0
  ([\#96](https://github.com/JamesHWade/graft/issues/96)).
- [`graft_accept()`](https://jameshwade.github.io/graft/reference/graft_accept.md),
  [`graft_withdraw()`](https://jameshwade.github.io/graft/reference/graft_withdraw.md),
  [`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md),
  and
  [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
  support reviewed reuse with explicit predecessor and retry controls.
  Current recall checks eligibility, purpose, retained evidence, and the
  decision head; historical inspection stays separate
  ([\#90](https://github.com/JamesHWade/graft/issues/90)).
- [`graft_backup()`](https://jameshwade.github.io/graft/reference/graft_backup.md),
  [`graft_verify_backup()`](https://jameshwade.github.io/graft/reference/graft_verify_backup.md),
  and
  [`graft_restore()`](https://jameshwade.github.io/graft/reference/graft_restore.md)
  create and verify bounded complete store bundles bound to a
  host-supplied scope and generation. Restores require an externally
  retained receipt and an empty quarantine target; applications still
  authorize restore using independent current registry state
  ([\#86](https://github.com/JamesHWade/graft/issues/86)).
- [`graft_contract_version()`](https://jameshwade.github.io/graft/reference/graft_contract_version.md)
  reports consumer contract 4.0.0 and the artifact, manifest,
  replacement, backup, selection, decision, vocabulary, binding, and
  vocabulary-release formats. Existing artifact identities and wire
  formats are unchanged
  ([\#90](https://github.com/JamesHWade/graft/issues/90)).
- [`graft_manifest()`](https://jameshwade.github.io/graft/reference/graft_manifest.md),
  [`graft_plan_replacement()`](https://jameshwade.github.io/graft/reference/graft_plan_replacement.md),
  and
  [`graft_replace()`](https://jameshwade.github.io/graft/reference/graft_plan_replacement.md)
  verify complete bounded store inventories and copy exact survivors
  into an empty quarantine store. An unexpected entry fails the
  inventory, including anything under `locks/` other than a stream’s
  lock file. Plans exclude declared dependents, affected selections, and
  whole affected decision histories; applications still own Forget
  approval, generation retirement, restore admission, and disposal
  ([\#48](https://github.com/JamesHWade/graft/issues/48)).
- [`graft_publish_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_publish_vocabulary.md)
  and
  [`graft_read_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_read_vocabulary.md)
  retain shared concepts, relationships, exact data-dict bindings,
  source bytes, and literal context across dictionary corrections. They
  return a typed `VocabularyRelease`
  ([\#76](https://github.com/JamesHWade/graft/issues/76),
  [\#90](https://github.com/JamesHWade/graft/issues/90)).
- [`graft_save()`](https://jameshwade.github.io/graft/reference/graft_save.md)
  accepts plain text or raw bytes and single dependency references;
  [`graft_save_file()`](https://jameshwade.github.io/graft/reference/graft_save_file.md)
  explicitly ingests a file.
  [`graft_read()`](https://jameshwade.github.io/graft/reference/graft_read.md)
  returns exact retained content as an `Artifact`
  ([\#90](https://github.com/JamesHWade/graft/issues/90)).
- [`graft_select()`](https://jameshwade.github.io/graft/reference/graft_select.md)
  and
  [`graft_read_selection()`](https://jameshwade.github.io/graft/reference/graft_read_selection.md)
  retain and verify bounded exact dependency closures as an
  `ArtifactSelection`
  ([\#72](https://github.com/JamesHWade/graft/issues/72),
  [\#90](https://github.com/JamesHWade/graft/issues/90)).
- [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  opens local stores with immutable revisions and verified exact reads.
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md)
  uses host-selected PostgreSQL scopes with transaction rollback and
  serialized scope writes
  ([\#47](https://github.com/JamesHWade/graft/issues/47),
  [\#71](https://github.com/JamesHWade/graft/issues/71),
  [\#90](https://github.com/JamesHWade/graft/issues/90)).
- [`graft_streams()`](https://jameshwade.github.io/graft/reference/graft_streams.md)
  lists the decision streams in a store with each stream’s current
  decision, so an application can show what it has kept without keeping
  its own catalog. It verifies every journal it reads, is bounded by
  stream count and aggregate metadata bytes, and works the same on local
  and PostgreSQL stores. It returns decisions only, never artifact
  content. Consumer contract 4.1.0
  ([\#96](https://github.com/JamesHWade/graft/issues/96)).
- [`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
  exposes current reviewed memory through a native read-only ellmer tool
  and optional shinychat result display, checking application
  eligibility on every invocation
  ([\#90](https://github.com/JamesHWade/graft/issues/90)).
- [`graft_with_store_lock()`](https://jameshwade.github.io/graft/reference/graft_with_store_lock.md)
  holds a local store’s lock while an application changes it. Every
  write holds the lock shared, and manifests, replacement plans and
  copies, backups, and restores hold it exclusively, so they can run
  while other processes write; a host forgetting an artifact holds it
  across the plan, the copy, and its switch to the replacement.
  [`graft_plan_replacement()`](https://jameshwade.github.io/graft/reference/graft_plan_replacement.md)
  accepts a plan with nothing to forget, which leaves out only
  unreferenced content from failed saves. Consumer contract 4.2.0
  ([\#96](https://github.com/JamesHWade/graft/issues/96)).
