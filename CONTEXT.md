# Graft

Graft governs reviewed knowledge and persistent artifacts for R applications
and agents. Applications own domain semantics, authentication, authorization,
and approval policy; Graft preserves exact immutable artifacts, selections,
decision history, and shared vocabulary releases.

## Language

**Artifact**:
Preserved opaque content and its descriptive metadata, stored immutably at a
content-addressed revision.
_Avoid_: Mutable record, chat memory

**Artifact reference**:
A stable logical artifact identity paired with an exact immutable revision. A
reference is neither an approval nor a mutable latest pointer.
_Avoid_: Latest pointer, approved link

**Artifact selection**:
Explicit root references and their complete verified closure of exact artifact
dependencies, retained together for inspection and reuse under host policy.
_Avoid_: Folder, bundle

**Candidate**:
A host-owned proposal represented by exact artifact references. Preserving a
candidate or selecting its dependencies does not accept it.
_Avoid_: Accepted artifact, approved draft

**Output handoff**:
A producer's explicit delivery of completed content and producer evidence to a
host for preservation as a candidate. Producer completion, evidence labels, and
preservation do not establish host acceptance or permission to reuse.
_Avoid_: Trusted artifact, automatic acceptance

**Decision stream**:
A host-chosen subject identity with one ordered decision history and one
current head. A stream is independent of an artifact identity.
_Avoid_: Artifact history, channel

**Decision record**:
A retained record of an explicit host decision (`accept` or `withdraw`) binding
an exact selection, predecessor, request key, actor, reason, and purpose.
Recording a decision is neither authentication nor factual proof.
_Avoid_: Permission token, fact check

**Acceptance event**:
A decision record with action `accept`. Re-reviewing an unchanged selection
under a new request key records a distinct event identity.
_Avoid_: Approval badge

**Withdrawal**:
A decision record with action `withdraw` that stops current consultation of a
stream while leaving historical decisions and artifacts inspectable.
_Avoid_: Erasure, deletion

**Current consultation**:
A point-in-time check confirming that the host currently permits the requested
purpose, the stream's current head is an acceptance for that purpose, and every
selected artifact verifies intact. It is not a reusable access token.
_Avoid_: Read permission, cached memory

**Vocabulary release**:
An immutable artifact selection binding shared concepts and relationships to
exact data-dict fields, together with pinned dictionary sources, canonical
exports, and generated Markdown context.
_Avoid_: Ontology reasoner, live schema
