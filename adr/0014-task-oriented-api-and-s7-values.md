# Use task-oriented verbs and S7 values

Status: Accepted for implementation in #90

## Context

The artifact interface exposes byte encoding, selection construction, decision
journal fields, and multi-step retrieval before a caller can save a reviewed
note for another conversation. Shortening function names alone would preserve
that burden. Graft is pre-production and does not need compatibility wrappers.

## Decision

Use task-oriented public verbs with S7 store handles and values. Everyday work
uses `graft_store()`, `graft_save()`, `graft_read()`, `graft_accept()`,
`graft_withdraw()`, `graft_recall()`, and `graft_history()`. Keep explicit advanced
selection, vocabulary, backup, and replacement operations.

`graft_save(store, x, id, ...)` accepts scalar text or raw bytes. Text is encoded
as UTF-8; strings are never guessed to be file paths. `graft_save_file()` is the
explicit bounded file operation. Saving returns an exact `ArtifactRef`; saving
new content under the same logical identity creates another immutable revision.
A single reference is accepted wherever one dependency or root is sufficient.

An exact read returns an `Artifact` with useful content, exact bytes and evidence
references. It never follows a current decision. `graft_recall()` is a separate
operation that checks current host eligibility, purpose, decision head and the
complete selection, then returns materialized content. Missing and withdrawn
subjects have explicit result statuses and no payload. A withdrawn result retains
its verified withdrawal decision so the host can display and capture that
predecessor; a missing result has no decision. Purpose matching applies to
withdrawn results too. Corrupt, stale or
ineligible reads fail without substituting other evidence.

Acceptance can take one artifact reference directly and construct its selection
internally. The host still supplies the reviewed predecessor, stable request key,
actor, reason and purpose. No operation automatically rebases a stale review.
A replayed historical acceptance cannot be reported as current success. A
withdrawal records a decision and retains inspectable history; it is not erasure.

`ArtifactStore` has local and PostgreSQL S7 implementations. Backend reads and
writes dispatch at the storage seam. `ArtifactRef`, `Artifact`,
`ArtifactSelection`, `Decision`, `Recall`, and `VocabularyRelease` make public
results explicit. `Decision@selection` is the exact selection digest, so journal
history can be inspected without loading payloads. Selection members are exact
references; recall members are materialized artifacts. S7 validation establishes shape, not authority or deep
immutability. IO boundaries revalidate live resources and stored evidence.

Private persistence records remain canonical plain data. Wire formats and
content identities do not depend on S7 serialization. The public consumer API
becomes contract 4.0.0; old artifact-prefixed exports are removed directly.

Optional agent integration returns ordinary ellmer tools and tool results, with
shinychat display metadata where available. The read-only memory tool fixes the
subject and purpose in application code and invokes an application eligibility
callback on each call. It never exposes live store handles to the model. Data-dict
continues to own dictionary meaning, Commons owns analytical execution, and apps
own review meaning, identity, access, retention and transaction commit.

## Alternatives considered

A three-verb interface would move complexity into action flags or overloaded
request objects. A fully explicit object-builder interface would make every
caller construct several intermediate values. We choose familiar verbs backed
by typed results, while retaining explicit predecessor and retry controls.

## Consequences and acceptance

The migration is breaking and downstream applications need deliberate adoption.
Administrative receipts, manifests and replacement plans remain explicit
operational documents. No conversation-history store or permanent Forget API is
implied by this change.

Acceptance is demonstrated by three workflows: save/reopen/correct an exact
report; accept/recall/correct/withdraw project memory; and publish/reopen a pinned
vocabulary release without re-running data-dict. Existing local and PostgreSQL
integrity, bounds, journal, backup and recovery regressions remain required.
