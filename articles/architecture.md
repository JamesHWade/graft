# Architecture

## Ownership

| Component | Owns |
|----|----|
| Commons | Live analysis and tools supplied by the application |
| Data-dict | Data description and dictionary semantics |
| ellmer | Model conversations and tool execution |
| shinychat | Chat interface and tool-result presentation |
| Graft | Exact artifacts, selections, decision history, vocabulary releases |
| Tempest | Research evidence, verification, reports, and research admission |
| Rill | Reader experience, access, approval, and retention policy |

## Stored contracts

Each artifact revision records its identity, media type, bytes, and
exact dependencies. `ArtifactRef`, `Artifact`, and `ArtifactSelection`
expose those values. Their S7 properties describe stored data; they do
not grant authorization. A decision stream records the application’s
explicit acceptance and withdrawal decisions for one subject and
purpose. `Decision` and `Recall` values expose the predecessor, current
head, purpose, and materialized artifacts. A review can add a decision
while leaving the selection unchanged.

Reading a historical artifact and reading currently accepted content use
different paths.
[`graft_read()`](https://jameshwade.github.io/graft/reference/graft_read.md)
can read an exact old artifact after a correction.
[`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md)
also requires the exact current accepted event, a matching purpose, and
current eligibility from the application.

Vocabulary releases are stored as artifacts. Each release keeps
concepts, relationships, field bindings, dictionary source bytes,
canonical exports, and literal context together. It provides a shared
vocabulary; it does not run an ontology reasoner.

## Persistence boundary

The public `ArtifactStore` S7 class has `LocalArtifactStore` and
`PostgresArtifactStore` implementations. Graft supports bounded
immutable local files; a per-stream file lock serializes decisions from
several processes, as an advisory lock does for a PostgreSQL scope. Its
PostgreSQL scopes run inside transactions owned by the application.
Normal reads verify digests and predecessor identity, ignore abandoned
staging, and allow identical retries. A complete manifest must account
for every entry, so abandoned staging and unknown objects are rejected.
Replacement plans copy the exact artifacts remaining after exclusions
into empty quarantine stores and verify the full image. The store does
not provide distributed transactions, power-loss guarantees,
authentication, or permanent deletion.

A closed directory backup retains the complete logical image, including
orphan content and every historical decision. Verification compares the
canonical bundle descriptor and all stored objects with an externally
retained identity receipt. Restore copies into an empty quarantine
target and checks both images again. See [Back up and restore an
artifact
store](https://jameshwade.github.io/graft/articles/artifact-backups.md).

Applications retire generations and use an independent durable journal
to decide whether a backup may be restored. A valid content checksum
does not authorize an old backup. See [Verify a replacement artifact
store](https://jameshwade.github.io/graft/articles/artifact-recovery.md).

Applications depend on these artifact semantics rather than graph tables
or a compiler, so the persistence layer can be replaced. Any future
engine must preserve exact retained identities and history. Graft has no
public pluggable-backend interface today.

## Native graph retirement

The graph/compiler APIs and their DuckDB, Python, LinkML, and
graph-adapter dependencies are retired. Consumer contract 4 uses S7
stores and values through a task-oriented public API. Graft has no
compatibility layer, and the retained artifact formats are unchanged.
Source history, earlier ADRs, and experiment observations describe the
previous architecture. Their native examples are historical context, not
supported recipes for current Graft.
