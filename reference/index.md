# Package index

## Everyday workflow

- [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  : Preserve immutable artifact content
- [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md)
  : Open a transaction-scoped PostgreSQL artifact store
- [`graft_save()`](https://jameshwade.github.io/graft/reference/graft_save.md)
  : Save text or raw bytes as an immutable artifact
- [`graft_save_file()`](https://jameshwade.github.io/graft/reference/graft_save_file.md)
  : Save a bounded regular file as an immutable artifact
- [`graft_read()`](https://jameshwade.github.io/graft/reference/graft_read.md)
  : Read one exact immutable artifact
- [`graft_select()`](https://jameshwade.github.io/graft/reference/graft_select.md)
  : Capture and verify an exact dependency selection
- [`graft_read_selection()`](https://jameshwade.github.io/graft/reference/graft_read_selection.md)
  : Read one exact retained dependency selection
- [`graft_accept()`](https://jameshwade.github.io/graft/reference/graft_accept.md)
  : Record an acceptance of exact retained evidence
- [`graft_withdraw()`](https://jameshwade.github.io/graft/reference/graft_withdraw.md)
  : Withdraw the current acceptance for a decision stream
- [`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md)
  : Recall the current accepted evidence for a stream
- [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
  : Read the chronological decision journal for one stream
- [`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
  : Expose reviewed content through a fixed read-only ellmer tool

## Vocabulary and operations

- [`graft_publish_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_publish_vocabulary.md)
  : Publish a validated shared vocabulary release
- [`graft_read_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_read_vocabulary.md)
  : Read a retained vocabulary release
- [`graft_backup()`](https://jameshwade.github.io/graft/reference/graft_backup.md)
  : Create a closed artifact-store backup
- [`graft_verify_backup()`](https://jameshwade.github.io/graft/reference/graft_verify_backup.md)
  : Verify a closed artifact-store backup
- [`graft_restore()`](https://jameshwade.github.io/graft/reference/graft_restore.md)
  : Restore a verified backup into an empty artifact store
- [`graft_manifest()`](https://jameshwade.github.io/graft/reference/graft_manifest.md)
  : Inventory a complete artifact store
- [`graft_plan_replacement()`](https://jameshwade.github.io/graft/reference/graft_plan_replacement.md)
  [`graft_replace()`](https://jameshwade.github.io/graft/reference/graft_plan_replacement.md)
  : Plan and build a bounded artifact-store replacement

## Public S7 classes

- [`ArtifactStore()`](https://jameshwade.github.io/graft/reference/ArtifactStore.md)
  : Abstract artifact store
- [`LocalArtifactStore()`](https://jameshwade.github.io/graft/reference/LocalArtifactStore.md)
  : Local artifact store
- [`PostgresArtifactStore()`](https://jameshwade.github.io/graft/reference/PostgresArtifactStore.md)
  : PostgreSQL artifact store
- [`ArtifactRef()`](https://jameshwade.github.io/graft/reference/ArtifactRef.md)
  : An exact immutable artifact reference
- [`Artifact()`](https://jameshwade.github.io/graft/reference/Artifact.md)
  : Materialized immutable artifact content
- [`ArtifactSelection()`](https://jameshwade.github.io/graft/reference/ArtifactSelection.md)
  : A verified artifact dependency selection
- [`Decision()`](https://jameshwade.github.io/graft/reference/Decision.md)
  : A host decision recorded in an artifact stream
- [`Recall()`](https://jameshwade.github.io/graft/reference/Recall.md) :
  The result of a current reviewed-artifact lookup
- [`VocabularyRelease()`](https://jameshwade.github.io/graft/reference/VocabularyRelease.md)
  : A retained shared vocabulary release

## Contract

- [`graft_contract_version()`](https://jameshwade.github.io/graft/reference/graft_contract_version.md)
  : Report Graft's artifact and vocabulary contracts
