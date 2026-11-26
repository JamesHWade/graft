# Package index

## Store and save

- [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  : Create or reopen a local artifact store
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

## Review and recall

- [`graft_accept()`](https://jameshwade.github.io/graft/reference/graft_accept.md)
  : Record acceptance of exact retained evidence
- [`graft_withdraw()`](https://jameshwade.github.io/graft/reference/graft_withdraw.md)
  : Withdraw the current acceptance for a decision stream
- [`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md)
  : Read the evidence currently accepted for a stream
- [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
  : Read the chronological decision journal for one stream
- [`graft_streams()`](https://jameshwade.github.io/graft/reference/graft_streams.md)
  : List decision streams and their current decisions
- [`graft_tool()`](https://jameshwade.github.io/graft/reference/graft_tool.md)
  : Create a fixed read-only ellmer tool for reviewed content

## Shared vocabulary

- [`graft_publish_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_publish_vocabulary.md)
  : Publish a validated shared vocabulary release
- [`graft_read_vocabulary()`](https://jameshwade.github.io/graft/reference/graft_read_vocabulary.md)
  : Read a retained vocabulary release

## S7 classes

- [`ArtifactStore()`](https://jameshwade.github.io/graft/reference/ArtifactStore.md)
  : Abstract artifact store
- [`LocalArtifactStore()`](https://jameshwade.github.io/graft/reference/LocalArtifactStore.md)
  : Local artifact store
- [`PostgresArtifactStore()`](https://jameshwade.github.io/graft/reference/PostgresArtifactStore.md)
  : PostgreSQL artifact store
- [`ArtifactRef()`](https://jameshwade.github.io/graft/reference/ArtifactRef.md)
  : An exact immutable artifact reference
- [`Artifact()`](https://jameshwade.github.io/graft/reference/Artifact.md)
  : An immutable artifact with its content loaded
- [`ArtifactSelection()`](https://jameshwade.github.io/graft/reference/ArtifactSelection.md)
  : A verified artifact dependency selection
- [`Decision()`](https://jameshwade.github.io/graft/reference/Decision.md)
  : A host decision recorded in an artifact stream
- [`Recall()`](https://jameshwade.github.io/graft/reference/Recall.md) :
  A result from a current reviewed-artifact lookup
- [`VocabularyRelease()`](https://jameshwade.github.io/graft/reference/VocabularyRelease.md)
  : A retained shared vocabulary release
