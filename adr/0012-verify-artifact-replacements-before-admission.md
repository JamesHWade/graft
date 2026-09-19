# Verify artifact replacements before admission

Status: accepted for the bounded artifact replacement implementation; production
Forget and restore admission remain gated by #48.

## Context

ADR 0006 established the application protocol: retire an affected Reader's store
generation in an independent journal before publishing its replacement. Its
native graph experiments no longer exercise the installed artifact backend.
This decision supplies the artifact mechanics and supersedes the old graph
inventory and replay recipe. The journal, fencing, and disposal obligations in
ADR 0006 still apply.

Graft cannot infer that an opaque report copied private prose, that an artifact
ID contains a person's name, or that deleting a Conversation should also remove
an independently accepted Memory. Applications supply those meanings and the
additional erasure roots, including every historical revision of a logical
record covered by the approved Forget action. One exact root does not implicitly
select all revisions with the same artifact ID. A scope is a storage namespace,
not authentication.

## Decision

Expose three bounded operations:

1. `graft_artifact_manifest()` verifies and inventories the complete logical
   object set of one local store or PostgreSQL scope.
2. `graft_artifact_replacement_plan()` previews the survivors after excluding
   explicit exact revisions and their transitive dependents, affected selections,
   and entire affected decision streams. Hosts can also exclude streams directly.
3. `graft_artifact_replace()` copies those exact survivors to an empty quarantine
   store and verifies both the source and the resulting manifest before returning.

These operations never delete source content, publish an application generation,
change acceptance, or authorize a restore. A manifest is a content checksum, not a
signature, access decision, freshness proof, or erasure certificate.

### Complete inventory

The manifest includes every content, revision, selection, and decision object,
with its storage key, byte count, and digest. Ordering is deterministic across
backends. The store marker is validated separately. Enumeration and byte budgets
apply to the whole scope. Unknown entries, abandoned staging, symbolic links,
malformed records, broken dependencies, and incomplete journals fail closed.
Even an unavailable selection on an old withdrawal prevents certification.

Well-formed orphan content is inventoried, then omitted from a replacement.
Content used by any surviving revision is retained, even when an excluded
revision uses identical bytes. This is not proof that the remaining bytes are
appropriate: the host must identify every private copy that must be removed.
Vocabulary sources, canonical dictionary exports, bindings, and literal context
are ordinary exact artifacts; their declared dependencies govern exclusion.

### History is never rewritten

If any historical decision refers to an excluded selection, exclude the entire
stream. Keeping its latest corrected head would retain private history; removing
individual records would fabricate a different chain. An independent surviving
stream keeps its original bytes and decision identities. A host that wants to
accept surviving material from an excluded stream performs a fresh review.

Exact survivor identities are unchanged. They are not permission to resolve an
old generation-qualified reference in a new generation. The application must
report references to retired generations as unavailable, including old references
to content that survived. Raw Graft reads do not enforce this boundary.

### Quarantine and failure

The source must be quiescent. Local files still assume trusted storage and one
writer; repeated checks do not supply a filesystem snapshot or a power-loss
commit protocol. PostgreSQL stores require host-owned READ COMMITTED transactions
and acquire scope locks. Cross-database or filesystem/database transfers are not
atomic transactions. Hosts must order scope locks consistently across operations.

Execution recomputes the plan from the source before writing, rejecting changed
or edited plans. The target must contain no objects. A failure can leave a partial
candidate; it must remain quarantined. Retry into a fresh empty target. No cleanup
or deletion occurs automatically. A successful return verifies an exact logical
image, not filesystem flushes, committed database transactions, copied external
files, or application publication.

## Application and operations follow-through

The production protocol remains:

1. Inventory revisions, declared and copied derivatives, indexes, provider
   context, exports, Commons working files, reuse checkpoints, and external copies.
   Separate Conversation deletion from accepted Memory and Artifacts.
2. Bind a preview to authenticated Reader, current access revision, generation,
   exact manifest, requested action, and explicit approval. Fence writes and work.
3. Durably retire the old generation in a monotonic independent Forget journal.
   Missing, stale, or rolled-back journal state must deny reads and restore.
4. Register and build a quarantined replacement; verify a closed backup and
   application records, invalidate caches, then atomically publish its generation.
5. Check admission again before delivery. Retry interrupted work using the durable
   request record. Track local and external disposal separately from publication.

The journal must survive independently of the content backup. A checksum-matching
old backup is still inadmissible. An unavailable journal cannot be repaired by
trusting metadata inside that backup. All earlier affected-Reader generations
stay retired; a different Reader with shared source bytes remains independent.

Offline or encrypted copies with available keys may still disclose the original
content. SQL deletion, file unlinking, and restore denial do not establish physical
secure erasure. Retention acknowledgments and key disposal require deployment-
specific evidence. The synthetic tests prove only the mechanics they execute;
#48 stays open until the actual Rill workflow and durable recovery are verified.

Follow-through is tracked in [Rill #106](https://github.com/JamesHWade/rill/issues/106)
and [Graft #86](https://github.com/JamesHWade/graft/issues/86).
