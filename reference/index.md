# Package index

## Retain exact artifacts

- [`graft_artifact_store()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md)
  [`graft_artifact_save()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md)
  [`graft_artifact_read()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md)
  : Preserve immutable artifact content
- [`graft_artifact_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_artifact_store_postgres.md)
  : Open a transaction-scoped PostgreSQL artifact store
- [`graft_artifact_select()`](https://jameshwade.github.io/graft/reference/graft_artifact_select.md)
  [`graft_artifact_read_selection()`](https://jameshwade.github.io/graft/reference/graft_artifact_select.md)
  : Preserve an exact artifact selection

## Verify replacements and backups

- [`graft_artifact_backup()`](https://jameshwade.github.io/graft/reference/graft_artifact_backup.md)
  : Create a closed artifact-store backup
- [`graft_artifact_backup_verify()`](https://jameshwade.github.io/graft/reference/graft_artifact_backup_verify.md)
  : Verify a closed artifact-store backup
- [`graft_artifact_restore()`](https://jameshwade.github.io/graft/reference/graft_artifact_restore.md)
  : Restore a verified backup into an empty artifact store
- [`graft_artifact_manifest()`](https://jameshwade.github.io/graft/reference/graft_artifact_manifest.md)
  : Inventory a complete artifact store
- [`graft_artifact_replacement_plan()`](https://jameshwade.github.io/graft/reference/graft_artifact_replacement_plan.md)
  [`graft_artifact_replace()`](https://jameshwade.github.io/graft/reference/graft_artifact_replacement_plan.md)
  : Plan and build a bounded artifact-store replacement

## Record host decisions

- [`graft_artifact_decide()`](https://jameshwade.github.io/graft/reference/graft_artifact_decide.md)
  [`graft_artifact_read_decision()`](https://jameshwade.github.io/graft/reference/graft_artifact_decide.md)
  [`graft_artifact_reuse()`](https://jameshwade.github.io/graft/reference/graft_artifact_decide.md)
  : Record host decisions about exact artifact selections

## Share vocabulary

- [`graft_vocabulary_publish()`](https://jameshwade.github.io/graft/reference/graft_vocabulary_publish.md)
  [`graft_vocabulary_read()`](https://jameshwade.github.io/graft/reference/graft_vocabulary_publish.md)
  : Publish and read a shared vocabulary release

## Consumer contract

- [`graft_contract_version()`](https://jameshwade.github.io/graft/reference/graft_contract_version.md)
  : Report Graft's artifact and vocabulary contracts
