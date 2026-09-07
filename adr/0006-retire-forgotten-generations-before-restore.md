---
status: proposed
---

# Retire forgotten generations before restore

For [#48](https://github.com/JamesHWade/graft/issues/48), propose a host-owned
Forget journal independent of knowledge backups, plus replacement of the
entire affected Reader's store generation. A retired generation can never be
served again. This is a storage/API proposal and offline protocol proof; Graft
has no supported permanent purge or backup/restore API yet. Rill's production
gate remains open.

This extends [the Reader isolation proposal](0005-isolate-reader-knowledge-stores.md).
It deliberately qualifies immutable-history expectations: Forget makes old
content unavailable, including content addressed by an old snapshot or reuse
basis. It does not silently reinterpret an old receipt against a new store.

## Inventory and ownership

The inventory follows the current implementation, not just public query output.

| Surface | Current copy and owner | Required treatment |
| --- | --- | --- |
| Accepted history | Graft `_graft_record_revisions` stores payload JSON, including private fields, old revisions, and digests; `_graft_record_heads` points at current revisions (`R/metadata.R`, `R/commit-executor.R`). | Remove every revision of selected records from the replacement; preserve allowed survivor history under an explicit migration contract. Removing a current projection is insufficient. |
| Metadata and provenance | Graft batches, observations, identifiers, origins, schema manifests, and change metadata can contain source identifiers or user-supplied strings. | Inspect all fields for content and dependencies. Do not assume provenance, definitions, schema descriptions, or hashes are harmless audit metadata. |
| Projections and indexes | Graft `_graft_current_records`, `_graft_projection_*`, relation projections, indexes and projection state (`R/projections.R`). | Rebuild from surviving authority in a new file. Include staging/temporary files and DuckDB WAL in disposal obligations. |
| Managed OKF and exports | A file store defaults to a sibling `.okf` tree (`R/store.R`); `R/okf-managed.R` synchronizes it. `R/okf.R` can export historical snapshots; Markdown/front matter and detached exports contain readable copies. | Remove the old managed tree and inventoried exports; regenerate only from survivors. Prevent historical export/import from reopening a retired generation. |
| Detached public views | `R/commons-adapter.R` materializes a separate Commons source and dictionary. Public means queryable under the contract, not public Internet data. | The consumer must invalidate/remove its copies, including returned calculation rows and dictionary prose. Graft cannot recall detached data by deleting its own rows. |
| Caches and in-flight work | Host search indexes, query results, embeddings, model context, and process memory may hold payloads. | Block new reads, stop runs, discard buffered results, invalidate affected caches, and recheck epoch at delivery. Already disclosed client/provider content cannot be recalled by this protocol. |
| Reuse bases and receipts | A minimal basis stores IDs/snapshot; host checkpoints or tool receipts may also retain rendered results, arguments, excerpts, or private IDs. | Inventory serialized content; purge payload-bearing copies. Keep only approved opaque audit identifiers. Old references resolve as unavailable, never to replacement revisions. |
| Private Documents and evidence | Rill owns captures, extracted text, annotations, Source Evidence anchors, and hydration authorization. Equal URLs do not imply shared ownership. | Rill computes private dependency closure and removes matching derivatives. Retain an independently owned Reader's copy. Source deletion may require cascading to accepted outcomes that quote it. |
| Conversations and accepted outcomes | Rill owns product semantics; shinychat presents durable Conversation history; Graft stores separately accepted Reader Memory/Reading Artifacts. | Deleting a Conversation alone leaves separately accepted outcomes. Forget of memory must identify its copied excerpts in retained Conversations separately, with a concrete preview and policy. |
| Diagnostics and external destinations | Deputy execution/checkpoints, host logs, and opt-in Logfire/provider copies have distinct owners and retention. | Record requested, acknowledged, pending, or retention-limited disposal separately. Do not claim completed external deletion from a local success. |
| Backups and storage remnants | Host database images, OKF archives, local snapshots, encrypted/offline backups, cloud replicas, filesystem/SSD remnants. | Deny retired images before opening; track disposal/key-retirement separately. Fresh replacement backup must be verified before service resumes. Physical secure erasure is outside this proof. |

Sources for Rill's distinctions are [ADR 0002](https://github.com/JamesHWade/rill/blob/main/docs/adr/0002-keep-reader-semantics-in-rill-and-accepted-knowledge-in-graft.md),
[ADR 0003](https://github.com/JamesHWade/rill/blob/main/docs/adr/0003-persist-conversations-and-accepted-reading-artifacts.md),
and its [domain glossary](https://github.com/JamesHWade/rill/blob/main/CONTEXT.md).

## Erasure boundary and authorization

Rill computes a closure over its own private content dependencies, not merely
foreign keys or string matches. The preview names the Reader, root records,
all revisions, dependent accepted artifacts, copied passages, external
obligations, and the effect on historical references. Authorize this exact
preview, action `forget`, accepted boundary, and current access revision.
Any intervening write or dependency change invalidates the preview. A generic
write grant, model request, Archive approval, or possession of a receipt is not
Forget authorization.

For the synthetic schema, forgetting an interpretation removes its support
record. Its source remains because another retained conclusion references it.
Forgetting that source instead removes both supported outcomes and their
support records; forgetting both outcomes also removes their unreferenced
private source. Real Rill dependency closure must cover historical references
and copied prose even after a current link was removed. Source ownership and
copy provenance determine this; a model cannot decide the erasure boundary.

A separately owned second Reader is outside the closure, even if IDs, URLs,
or content match. The host must not erase that Reader's copy to satisfy the
first Reader's request. This scoped guarantee must be clear in the preview.

## Store generations and historical reads

A generation is one closed, immutable database image with a store UUID,
accepted snapshot, schema identity, format version, Reader binding, Forget
epoch, and checksums for all bundled files. This is a backup/admission unit,
not a new Graft runtime abstraction.

Choose generation replacement for the first design rather than in-place row
purging. It bounds the files which may be admitted after Forget, avoids
claiming that projection deletion removes history, and can invalidate every
old handle by retiring its store UUID. Its cost is substantial: **all previous
snapshots for the affected Reader become unavailable**, including references
to retained records. The preview must disclose this scope. The independent
Reader keeps its original identity, history, and receipts.

The replacement needs retained record identities and allowed historical
values, but receives a new store UUID. Migration must record non-content
lineage without pretending replayed values are the original acceptance events.
No old receipt is rewritten, no old basis is silently upgraded, and no new
acceptance is attributed to the Reader without the disclosed migration policy.
A host may create a new basis after explicit selection of the surviving
knowledge. A future selective-erasure implementation that preserves unaffected
snapshots would require a different, thoroughly enforced history contract.

The prototype replays known synthetic surviving rows and one correction through
public Graft ingestion. It preserves those values, not original batch/revision
identities or acceptance times. It is not a general migration implementation;
public reads omit private fields and cannot be used as a lossless export.

## Protocol and recovery

1. Quiesce the affected Reader's writers and runs. Construct a complete preview
   from a pinned boundary and current dependency inventory; obtain exact
   action-specific approval.
2. Durably append the decision to an independent, monotonic host journal.
   Increment that Reader's Forget epoch and retire its old generation **before**
   deleting or rebuilding anything. Reads, cache hits, workers, imports, and
   restores require current journal state and fail closed if it is missing.
3. Build a replacement in a quarantined directory from allowed authority.
   Validate survivor history, private fields, schema, relationships, definitions,
   and provenance. Audit every logical table and derived file for excluded
   content. Keep the Reader blocked if any validation fails.
4. Remove inventoried local copies idempotently, verify absence, and record
   remaining external/offline obligations without payloads. Dispose of failed
   candidates too. Copy and verify a closed replacement backup before publication.
5. Atomically publish the certified image and its checksum/identity in the host
   registry at the current epoch. A read must validate registry identity both
   before access and before releasing collected results. Reconnects/restore use
   this same gate. Outstanding external disposal remains visible separately.

A crash after step 2 leaves access blocked. A crash during replacement or
cleanup resumes the same approved request, without allocating another epoch
or resurrecting the old store. A crash after publication returns the existing
result on retry. Reusing the request ID with a different preview is rejected.
Production needs transactional compare-and-swap, leases/fencing, durable writes,
and an independent journal disaster-recovery procedure; an in-memory flag or
an unverified journal restored alongside the old database cannot provide this.

Journal audit data should be limited to opaque Reader/store/request IDs, epoch,
status, timestamps, approved scope identifiers, and disposal acknowledgments.
Even IDs can be identifying: choose opaque random IDs, restrict access and
retention, and avoid excerpts, titles, URLs, raw errors, or payload digests in
long-lived audit records. Content checksums used to admit a live backup are
restricted operational metadata, not necessarily permanent audit fields.

## Backup admission and limitations

A backup records exact accepted boundary, store UUID, schema/compiler and
format versions, Reader binding, epoch, file checksums, and journal watermark.
The registry certifies the exact image; an attacker or stale worker changing a
sidecar epoch cannot rehabilitate an old database. An unknown format, mismatched
UUID/checksum/Reader, missing journal, pending decision, or retired generation
is refused before it can be served. A verified retained backup restores
corrections and historical reads exactly before Forget. After Forget, only a
newly certified replacement backup is admitted.

The initial policy refuses **every** older image, including a pre-Forget backup
that is otherwise intact. It does not automatically filter and serve the old
backup, nor silently accept rollback of later corrections. Salvaging surviving
data from a retired backup is a separate authorized, offline migration through
the full replacement validator. If no certified new backup exists, service
stays unavailable until recovery is verified.

The journal must survive independently of the backups it invalidates. Protect
its monotonic watermark through separate durable replication/backup and trusted
recovery. If both current journal and external freshness evidence are lost,
fail closed; checksums cannot prove journal freshness. This proof does not
establish resistance to a privileged operator rolling back both stores and
journal, concurrent writers, power loss, or tampered RDS files.

Encrypted offline backups may remain readable to anyone retaining their keys.
Denying restore into the application is a non-resurrection guarantee, not
erasure of those bytes. Key destruction helps only with proven per-scope keys
and complete key-copy retirement; shared backup keys cannot be destroyed
without affecting other Readers. Report local disposal and offline/external
retention obligations separately, and do not report permanent Forget complete
while required copies remain outside the promised retention policy.

DuckDB documents [space reclamation](https://duckdb.org/docs/current/operations_manual/footprint_of_duckdb/reclaiming_space)
and [checkpointing](https://duckdb.org/docs/current/sql/statements/checkpoint),
not secure erasure of filesystem/SSD/cloud remnants. Neither SQL deletion,
`VACUUM`, checkpointing, new-file copying, nor unlinking supplies that guarantee.
The test copies only closed databases and checks logical absence/file removal.

## Executable evidence and implementation tasks

`tests/testthat/test-forget-restore.R` runs against real synthetic Graft files,
snapshots, receipts, histories and public reads. Its test-only helper supplies a
single-writer journal and a known-data replacement builder. Fault hooks exercise
accepted, validated, partially removed, and published states; a fresh R process
checks the persisted denial decision. Placeholder files stand in for OKF,
cache, checkpoint and Conversation disposal obligations. They do **not** prove
actual OKF/export, Rill, provider, or filesystem erasure behavior. The original
backup deliberately remains readable through raw file access, but the host
restore gate refuses it. No real user data is touched.

Bounded follow-through, in dependency order:

1. **Graft replacement migration:** introduce validated value objects for an
   erasure selection, replacement manifest and migration report. Build a new
   store from retained authority, including private fields and allowed history;
   regenerate projections and managed OKF. Reject unsupported schema/provenance
   cases and verify all original and derived copies. Proposed internal shape:
   `prepare_replacement(store, selection, destination)` returns a candidate and
   an audit report. This spelling is illustrative, not an exported API.
2. **Rill authorization and journal:** own exact preview/approval, historical
   dependency closure, independent durable journal, fencing, run cancellation,
   cache invalidation and read/delivery/restore admission. Proposed host shape:
   `approve_forget(preview)` persists the decision; `resume_forget(request_id)`
   resumes it. Bind to actual Reader/Document/Agent Run records under #51.
3. **Storage operations:** implement closed-store bundles, versioned manifests,
   replacement-backup verification, atomic publication, journal recovery and
   local/external disposal acknowledgments. Exercise process kills, disk full,
   competing writers, corrupt/missing files and restoration on a clean host.
4. **Product acceptance:** verify Conversation deletion versus accepted outcomes,
   shared private sources, historical dependency changes, actual OKF/Commons and
   checkpoints, two authenticated Readers, and external retention messaging.
   Rill rollout stays gated until these production paths pass.

These tasks are the proposed handoff under #48, not completed implementations.
Review should settle the broad snapshot-retirement tradeoff before any public
API is added. No contract version or supported Graft behavior changes here.
