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

An artifact revision binds its identity, media type, bytes, and exact
dependencies. `ArtifactRef`, `Artifact`, and `ArtifactSelection` make
those values explicit; their S7 properties describe retained data, not
authorization. A decision stream records explicit host accepts and
withdrawals for one subject and purpose. `Decision` and `Recall` values
make the predecessor, current head, purpose, and materialized artifacts
inspectable. An unchanged review can add a decision without changing the
selection.

Historical inspection and current consultation are separate.
[`graft_read()`](https://jameshwade.github.io/graft/reference/graft_read.md)
can read an exact old artifact after correction.
[`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md)
also requires the exact current accepted event, purpose match, and
current host eligibility.

Vocabulary releases are artifacts: concepts, relationships, field
bindings, dictionary source bytes, canonical exports, and literal
context are retained together. They provide a shared vocabulary, not an
executable ontology reasoner.

## Persistence boundary

The public `ArtifactStore` S7 class has `LocalArtifactStore` and
`PostgresArtifactStore` implementations. Graft supports bounded
immutable local files with one writer and PostgreSQL scopes inside
host-owned transactions. Normal reads verify digests and predecessor
identity, ignore abandoned staging, and support identical retries.
Complete manifests require every entry to be accounted for, rejecting
abandoned staging and unknown objects. Replacement plans copy exact
survivors to empty quarantine stores and verify the whole image. They do
not provide distributed transactions, power-loss guarantees,
authentication, or permanent deletion.

Closed directory backups retain the complete logical image, including
orphan content and every historical decision. Verification compares a
canonical bundle descriptor and all stored objects to an externally
retained identity receipt. Restore copies into an empty quarantine
target and checks both images again. See [Back up and restore an
artifact
store](https://jameshwade.github.io/graft/articles/artifact-backups.md).

Applications retire generations and enforce restore admission using an
independent durable journal. A valid content checksum does not authorize
an old backup. See [Verify a replacement artifact
store](https://jameshwade.github.io/graft/articles/artifact-recovery.md).

Replaceable persistence means applications depend on these artifact
semantics, not graph tables or a compiler. A future engine must preserve
exact retained identities and history. No public pluggable-backend
interface exists today.

## Native graph retirement

The graph/compiler APIs and their DuckDB, Python, LinkML, and
graph-adapter dependencies remain retired. Consumer contract 4 adds S7
stores and values with a task-oriented public API. There is no
compatibility layer. The retained artifact formats are unchanged. The
source history, earlier ADRs, and experiment observations record the
previous architecture; their native examples are historical context, not
supported recipes for current Graft.
