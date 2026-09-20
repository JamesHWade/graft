# Graft

Graft governs knowledge proposed, reviewed, and accepted for use by people and
agents.

## Shared artifact direction

ADR 0008 places shared artifact infrastructure in Graft. Tempest and Rill are
applications consuming it; they own domain semantics and product policy.

**Artifact**: Preserved opaque content and its descriptive metadata.

**Artifact reference**: A stable artifact identity paired with an exact immutable
revision. A reference is not an approval or a mutable latest pointer.

**Artifact selection**: Explicit roots and their complete bounded closure of exact
artifact dependencies, retained for later inspection and reuse under host policy.

**Decision record**: A retained record of an explicit host decision. Graft supplies
shared recording mechanisms; the application supplies approval, purpose, actor
and access policy. Recording a decision is not authentication or factual proof.

**Candidate**: A host-owned proposal represented by exact artifact references.
Preserving a candidate or selecting its dependencies does not accept it.

**Decision stream**: A host-chosen subject identity with one ordered decision
history and one current head. A stream is independent of an artifact identity.

**Acceptance event**: A decision record with action `accept`, identifying an exact
selection, predecessor, request key, actor, reason and purpose. New unchanged
reviews retain distinct event identities. Keys bind committed requests, not
consultation eligibility.

**Current artifact consultation**: The host currently permits the requested
purpose, the recorded acceptance is still the stream's current head, and Graft
has verified and materialized the complete selection. The result is a point-in-time check, not an
access token. History remains inspectable after correction or withdrawal.

## Shared vocabulary

A vocabulary release binds concepts and relationships to exact data-dict fields.
Its retained selection includes original sources, canonical dictionary exports,
validated bindings, and literal data context. Reading a release is independent
of the publishing CLI. Relationship semantics do not grant executable authority.

## Current implementation

Consumer contract 4 uses task-oriented verbs and S7 stores and values while
retaining artifact formats 1 and vocabulary release format 1. Exact reading is
separate from current accepted recall; see ADR 0014.
Native graph stores, compiler manifests, commit plans, snapshots, calculations,
and managed OKF working trees are retired. Earlier ADRs remain historical.
See ADR 0010 for the current cut and consumer responsibilities.

## Persistence scopes

Local artifact stores support trusted files and one writer. PostgreSQL stores
use the same bytes and digests inside a host-owned transaction, with a host-bound
scope and a transaction lock per scope. Every retained object belongs to its
scope; equal content in different scopes does not share a retained row.

The scope is not authentication. Rill binds it from the active authenticated
Reader and rechecks authority for inspection and reuse. Graft does not own
Reader identities, Document access, approval meaning, or permanent Forget.
See ADR 0011 for the PostgreSQL boundary.

## Artifact replacement and Forget

Graft provides complete bounded artifact manifests and non-destructive
replacement plans for local stores and PostgreSQL scopes. Exclusions follow exact
reverse dependencies, affected selections, and whole historical decision streams.
Survivors retain their exact bytes and identities. Failed targets remain quarantined;
retry with a fresh empty target. ADR 0012 supersedes the native graph recovery recipe.

Hosts supply additional private-copy and metadata roots, authorize Forget, retire
generations in an independent durable journal, reject old backups, invalidate
contexts/caches, and arrange disposal. No source deletion or production restore
admission ships with these mechanics. Graft #48 remains the rollout gate.

Versioned directory backups contain a complete
artifact image and canonical descriptor. An independently retained receipt binds
scope, generation, descriptor digest, and manifest digest. Verification and
restore enforce caller limits and require exact identity; they do not establish
registry freshness or admission. Backup staging is renamed only after complete
verification. Local power-loss durability, PostgreSQL commit, atomic generation
publication, and independent journal recovery remain open under #86 and #48.
See ADR 0013 and the artifact-backups guide.
