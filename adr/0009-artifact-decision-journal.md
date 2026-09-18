# ADR 0009: Record host decisions in bounded append-only journals

Date: 2026-09-18

Status: implemented for the trusted local, single-writer profile.

## Decision

Graft records acceptance and withdrawal through `graft_artifact_decide()`,
inspects decision metadata through `graft_artifact_read_decision()`, and verifies
current consultation through `graft_artifact_reuse()`. Applications supply the
subject stream, operation key, expected predecessor, exact selection, action,
actor, reason and purpose. An explicit accept action is their approval declaration;
Graft neither authenticates actors nor determines scientific validity or consent.

Candidate artifact references, selection digests, acceptance event digests and
current consultation eligibility are distinct. A new unchanged review appends a
new event with the same selection. A correction selects different exact content.
An identical retry returns the original event, including after withdrawal; it
never advances the head. Changed committed requests under the same key fail.
Reacceptance after withdrawal requires a new explicit request and current
predecessor. Keys are scoped to a decision stream and bind committed requests.

## Publication and recovery

Each journal is a directory keyed by the normalized stream identity. One complete
immutable file contains the request, format and sequence; its filename includes
its sequence and content digest. Same-directory staging and rename publish that
file as the commit point. There is no separately mutable head or idempotency index.
Reopening verifies contiguous sequence numbers, hashes, request shapes, unique
keys and predecessor/withdrawal transitions. Staging is ignored, never promoted.

A failure before publication has no committed decision. A failure after
publication can lose its response but an identical retry finds the original
record. A stale uncommitted request cannot publish after the head advances.
History reads and appends have explicit record-count and aggregate metadata-byte
limits. Selection verification has separate artifact-count and metadata limits,
plus the artifact store's payload and revision bounds.

The journal is trusted local storage with one writer. Expected predecessors
protect sequential review, not concurrent compare-and-swap. Digests detect
accidental changes; they are not signatures or protection against rewriting the
whole directory. Power-loss durability, backups, multi-writer coordination and
permanent erasure remain #49/#47/#48.

## Inspection and consultation

Inspection verifies decision history without requiring payload availability.
Withdrawal must remain possible when selected content is missing or corrupt.
New acceptance and current consultation verify the complete exact selection.
Consultation additionally requires explicit current host eligibility, the exact
current accepted event, and its recorded purpose. Graft rechecks the head after
selection verification. This is a point-in-time observation, not a lasting permit.

Applications enforce access on every route, including low-level artifact reads
and historical inspection. Their domain-specific candidate validation and UI
remain outside this module. Tempest and Rill integrate through #50 and #51.

## Alternatives

A mutable whole-journal file makes replacement and recovery less portable.
Separate event, key-reservation and head files introduce additional commit states.
A configurable request envelope or separate journal handle adds caller concepts
without a second storage implementation. The initial module uses three explicit
functions over the existing artifact store and small internal filesystem seams.
