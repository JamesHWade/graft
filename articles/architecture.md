# Architecture

## Ownership

| Component | Owns |
|----|----|
| Commons | Live analysis and tools supplied by the application |
| Data-dict | Data description and dictionary semantics |
| Graft | Exact artifacts, selections, decision history, vocabulary releases |
| Tempest | Research evidence, verification, reports, and research admission |
| Rill | Reader experience, access, approval, and retention policy |

## Stored contracts

An artifact revision binds its identity, media type, bytes, and exact
dependencies. A selection binds explicit roots to the verified
dependency closure. A decision stream records explicit host accepts and
withdrawals for one subject and purpose. An unchanged review can add a
decision without changing the selection.

Historical inspection and current consultation are separate. Inspection
can read an old accepted selection after correction. Consultation also
requires the exact current accepted event, purpose match, and current
host eligibility.

Vocabulary releases are artifacts: concepts, relationships, field
bindings, dictionary source bytes, canonical exports, and literal
context are retained together. They provide a shared vocabulary, not an
executable ontology reasoner.

## Persistence boundary

Graft supports bounded immutable local files with one writer and
PostgreSQL scopes inside host-owned transactions. Normal reads verify
digests and predecessor identity, ignore abandoned staging, and support
identical retries. Complete manifests require every entry to be
accounted for, rejecting abandoned staging and unknown objects.
Replacement plans copy exact survivors to empty quarantine stores and
verify the whole image. They do not provide distributed transactions,
power-loss guarantees, authentication, or permanent deletion.

Applications retire generations and enforce restore admission using an
independent durable journal. A valid content checksum does not authorize
an old backup. See [Verify a replacement artifact
store](https://jameshwade.github.io/graft/articles/artifact-recovery.md).

Replaceable persistence means applications depend on these artifact
semantics, not graph tables or a compiler. A future engine must preserve
exact retained identities and history. No public pluggable-backend
interface exists today.

## Native graph retirement

Consumer contract 3 removes graph/compiler APIs and their DuckDB,
Python, LinkML, S7, and graph-adapter dependencies. There is no
compatibility layer. The retained artifact formats are unchanged. The
source history, earlier ADRs, and experiment observations record the
previous architecture; their native examples are not supported recipes
for current Graft.
