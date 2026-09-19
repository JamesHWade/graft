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
purpose, the requested event is still the stream's accepted head, and Graft has
verified the complete selection. The result is a point-in-time check, not an
access token. History remains inspectable after correction or withdrawal.

## Shared vocabulary

A vocabulary release binds concepts and relationships to exact data-dict fields.
Its retained selection includes original sources, canonical dictionary exports,
validated bindings, and literal data context. Reading a release is independent
of the publishing CLI. Relationship semantics do not grant executable authority.

## Current implementation

Consumer contract 3 retains artifact formats 1 and vocabulary release format 1.
Native graph stores, compiler manifests, commit plans, snapshots, calculations,
and managed OKF working trees are retired. Earlier ADRs remain historical.
See ADR 0010 for the current cut and consumer responsibilities.
