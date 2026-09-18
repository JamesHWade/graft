# ADR 0008: Keep shared artifact infrastructure in Graft

Date: 2026-09-18

Status: accepted direction; implementation proceeds in bounded slices.
Supersedes ADR 0007's proposed package ownership, not its experiment results.

## Decision

Graft is the shared home for persistent artifact infrastructure. Tempest and Rill
are end-use applications. They consume and test that infrastructure while owning
scientific and Reader semantics, user experience, approval and access policy.
Do not first put a reusable storage engine into either application and later
extract it.

Replace Graft's current graph/compiler architecture with a small artifact module.
The experiments prove that architecture is unnecessary for the bounded workflow;
they do not prove shared infrastructure belongs in an application. The package
name does not require preserving old implementations or public interfaces.
Backwards compatibility is not required.

## Interface and ownership

Graft preserves opaque payload bytes, stable artifact identity, immutable
revisions, exact dependencies and bounded selections. It verifies retained content
on resolution and supplies publication/recovery and decision-recording mechanisms.
It never deserializes arbitrary R objects or executes preserved content on read.

Applications decide who can save, approve, consult, withdraw or erase content,
for which purpose and during which task. They pass explicit decisions to reusable
Graft mechanisms. Recording a selection is distinct from approving its use;
recording acceptance does not establish truth or access authority.

Commons owns analytical execution and context retrieval. data-dict owns local
contracts, constraints and expressions. Shared concepts and relationships belong
to a small vocabulary publishing module, separate internally from storage and
using public upstream validation/export. Graft can preserve its releases and
qualified bindings without another expression interpreter or ontology reasoner.

Tempest retains evidence validation and research promotion. Rill retains Reader
identity, interpretation/preference semantics, Archive and Forget policy. Both
supply real consumer integration tests; neither owns generic agent infrastructure.

## First delivery stack

1. Record this ownership in domain docs, site content and roadmap #34.
2. #71: public local store creation/opening, immutable byte preservation, verified
   exact reads, idempotent retries and handled publication failures.
3. #72: exact dependency references and immutable complete selections with bounded
   traversal, preserved old revisions and corruption rejection.

The first storage profile is trusted local files with one writer. Publish content
before metadata; return a reference only after verification. A process interruption
may retain unused bytes but must not produce a successful incomplete publication.
Retain orphans for explicit recovery work. Do not claim power-loss durability,
concurrent publication, access enforcement or permanent erasure from this slice.

#73 adds host decision recording, expected-predecessor protection and withdrawal.
#49 retains operational recovery and real-consumer requirements. #50/#51 integrate
applications through the shared public interface. #74 removes obsolete native
integrations and dependencies once replacement behavior is demonstrated. #75
promotes portable vocabulary publishing; #65/#66 cover upstream Commons seams.
#47/#48 remain production access and erasure/restore requirements.

## Consequences

Keep Graft's interface small enough that applications need not know its file
layout or publication protocol. One local implementation is sufficient initially;
a generic backend plugin framework needs a concrete second requirement.

Old graph/compiler APIs remain until the removal slice. Documentation must label
the implemented artifact functions separately from future decision and recovery
work. Preserve the seven offline experiments as comparative evidence; do not
rewrite historical conclusions to imply that their prototypes were shipped APIs.
