# ADR 0007: Replace Graft with an explicit artifact composition

Date: 2026-09-16

Status: recommendation updated after the direct acceptance experiment in #64.
Retire the current graph/compiler architecture from the proposed artifact
composition; package removal and replacement implementation remain separate.
This ADR is the recommendation for #63.

## Decision

Pursue a small, explicit artifact boundary that composes Commons and data-dict.
Its responsibilities are retained payload bytes, stable artifact identity,
immutable revisions, exact meaning/dependency references, and bounded selection
records. Hosts decide saving, approval, purpose, access and current eligibility.
Keep the vocabulary publisher separate and internal until actual reuse justifies
its own distribution.

**Retire the current graph/compiler architecture from the artifact composition.**
The direct acceptance experiment now completes the tested consumer lifecycle
without Graft at either end. Preserve the artifact responsibilities in an explicit
host/module and remove obsolete integrations directly. This decision does not
remove existing APIs in the experiment PR.
This project is pre-production. Backwards compatibility with current Graft or
Tempest APIs is not a requirement and does not justify retaining Graft. Graft was
one of the compared metadata drivers behind that artifact boundary. It is not required
by the vocabulary or Commons integration, and its name and current arrangement
have no preservation requirement. The manifest driver remains an executable
replacement candidate. New callers should not inherit Graft's graph, compiler,
agent tools or OKF projection solely to preserve artifacts.

Stop adding competing semantic execution or Commons-wrapper APIs. data-dict owns
the expression contract; Commons owns analytical execution and its own result
provenance. The concrete upstream mismatch found in #61 should be addressed at
that seam, not with another interpreter here.

Tempest now has a public artifact input contract. Future integration can remove
native constructors and receipt representations directly. Preserve the
required research evidence, provenance, corrections, and selected history through
the new design. Rill should use the chosen artifact boundary subject to its
product/access/erasure requirements.

This decision does not designate the toy manifest implementation as production
storage or remove working Graft APIs. It chooses a replacement direction from
the bounded retirement evidence below; implementation remains a separate step.

## Evidence

| Experiment | Runtime result | Architectural consequence |
| --- | --- | --- |
| #59 | Both metadata paths pass a shared persistence/reuse/failure suite, with 120 assertions total | Retained content and host policy are required; the current ledger is not required for this bounded lifecycle |
| #60 | 18 cases validate portable bindings and use the release in plain R and Commons constructors without a Graft store | Keep one publishing module; ontology alone does not earn a ledger or reasoner |
| #61 | 38 checks exercise real data-dict/Commons on the same Parquet bytes; R-language definition diverges | Shared YAML is not shared execution semantics; pursue a public resolved-export contract upstream |
| #62 | Both paths preserve 16-object output selections across processes and correction, using real Commons calculation, context and sandboxed R outputs | Commons can generate/consume artifacts but still needs an explicit preservation/approval owner |
| #64 | Native history survives migration; public artifact input, direct acceptance, correction and withdrawal work without Graft installed in either producer or consumer | The bounded consumer lifecycle has a replacement path; implement the artifact boundary and remove obsolete native integrations |

Results and reproducible commands are indexed in
[`tools/experiments/README.md`](../tools/experiments/README.md). The independent
[countercase](../specs/2026-09-16-architecture-countercase.md) challenges immediate
retirement and records what would reverse this decision. Its compatibility
concerns are superseded by the pre-production policy in this ADR.

## Total composition cost

The same host/content module owns byte preservation, digest checks, dependency
closure, selection approval and policy for both paths. The manifest driver adds
immutable metadata files and a current map; the Graft driver substitutes native
plan/commit, discovery and bounded history. Both require the same vocabulary
publisher, upstream packages, Commons host integration and artifact extraction.
Neither gets free production lifecycle guarantees from its short adapter.

The manifest option avoids a Graft runtime dependency, but must earn recovery,
concurrency and evidence-preservation behavior when those are required by the
intended application. Preserving an old API is not part of that comparison. Graft
already owns native metadata transactions and accepted history, but external
bytes remain outside that transaction. Adding a second content store does not
make their joint publication atomic. The experiment does not measure production
latency, scale or storage cost; code length is not an operational comparison.

Our fixture artifact revision is a digest of serialized metadata. It is not an
acceptance event, store snapshot or native Graft revision ID. Equating those
identities would make the replacement appear cheaper by dropping requirements.

## Ownership after the decision

| Concern | Owner |
| --- | --- |
| Local schema, types, constraints, expressions | data-dict |
| Concept identity, qualified bindings, consistent release/context output | One internal vocabulary publisher using upstream validation/export |
| Content bytes, artifact revisions and exact dependency/selection records | Small artifact module; compare Graft and manifest metadata drivers |
| Context search, calculations, sandboxed analysis, calculation/citation evidence | Commons |
| Save versus approve, reuse purpose, authorization, task lifetime, revocation | Host application |
| Scientific evidence and promotion contracts | Tempest |
| Reader identity, Documents, Memory, Reading Artifacts, Archive and Forget | Rill |

A vocabulary term does not authorize a join or access. A saved draft does not
become approved memory. A calculation label or retained citation does not prove
an interpretation correct. A search cache is a rebuildable view over artifacts.

## Current consumers and evidence preservation

The original migration experiment used Tempest `3cfe220`. The current suite pins
[`6d3386c`](https://github.com/JamesHWade/tempest/tree/6d3386cbbe22fdc0c1539c436e3ab2f4660567f3)
from [Tempest #71](https://github.com/JamesHWade/tempest/pull/71), including the
public artifact input. Receipts and checkpoints bind store,
batch, schema build, snapshot and native revision identities. Its historical
selection and reviewed correction behavior must remain available or be explicitly
mapped; exporting current rows alone is insufficient.

Rill at `7769879c8e8f11f5305df3ada81822269b154fa4` has no `graft` references in its
inspected `DESCRIPTION` or `R/` sources. Its design ADRs and open #51 define intended
integration, not shipped migration cost. That Rill finding is an earlier source
inspection, not a new Rill runtime acceptance test. The project is pre-production;
these experiments use synthetic data and do not establish a deployed migration
obligation. No user stores were searched, opened, or modified.

The bounded Tempest experiment checks the following evidence-preservation
properties. These do not require retaining the old public API:

1. Produce accepted evidence, a no-change selection and a correction through
   Tempest's public promotion path; retain original receipts/checkpoints.
2. Export the complete required history, schema and snapshot references, evidence
   closure and payloads. Fail explicitly on unsupported export cases.
3. Import using preserved identities or an immutable mapping for every source
   identity; resolve old and corrected selections through the proposed adapter.
4. Compare exact contents, revision/dependency relationships and acceptance
   evidence, including withdrawal/tombstone behavior without implying Forget.
5. Reopen the unchanged source with its original receipts as rollback evidence.
   This is an independent fidelity check, not a compatibility commitment.

The [#64 result](../specs/2026-09-16-tempest-migration.md) establishes historical
read parity and unchanged-source rollback for the synthetic consumer fixture.
The original Graft constructor rejects the portable view. The follow-up
[artifact input experiment](../specs/2026-09-17-tempest-reuse.md) adds a public
constructor and proves saved-session reuse without Graft installed. The [direct acceptance experiment](../specs/2026-09-17-tempest-acceptance-cycle.md)
now demonstrates new host acceptance of completed proposals, unchanged reviews,
correction and withdrawal on both drivers. It preserves complete bundle files,
source bodies, reports and exact evidence dependencies. Its manifest acceptance
and consultation processes have no Graft installation. It uses shipped synthetic
research and makes no new model requests.

The bounded comparison supports retiring Graft from this composition: the same
host/content responsibilities work without its graph/compiler/runtime dependency.
The result report counts the remaining machinery and notes the untested option
of moving host policy into native transactions; it makes no performance claim. Production lifecycle controls must be ready before
production deployment; they do not require keeping an old API. Retain only the mechanisms a competing
implementation otherwise has to reconstruct. Migration work is an explicit
bounded test, not an indefinite argument for preserving unrelated features.

## Existing ADRs and release gates

ADRs 0001–0004 and existing public calculation APIs continue to describe current
behavior. The new direction proposes moving future canonical execution work
upstream; it does not silently supersede current Definition semantics or perform
the breaking changes. Implementation should document replaced contracts and
update callers directly, without compatibility shims solely for old APIs.

ADRs 0005/0006 and #47/#48 remain production requirements under both storage
options: Reader isolation, authorized erasure, independent recovery state and
backup admission. The fixtures cover trusted single-writer process restarts, not
power loss, concurrent publishers, cloud retention, live-chat cancellation or
production authorization. Passing them is not permission to deploy broad memory.

## Bounded next work

- #49: design and test content/metadata publication, orphan retention, idempotency
  and crash recovery in the chosen artifact module. Use the shared harness and
  retain both metadata candidates until the operational comparison is meaningful.
- #64: record the completed bounded migration, reuse and direct-acceptance
  evidence and the retirement recommendation; preserve #50's original acceptance
  evidence. Package removal is implementation work, not part of the experiment.
- #65: propose a minimal public Commons ingestion seam for validated typed data-dict
  exports, including dependencies, grain, dialect and the R-language counterexample.
- #66: propose a supported Commons output-artifact handoff for completed table/image
  content and provenance; do not make the fixture's JSON/tool protocol a host API.
- #39/#51/#41 must use the selected artifact contract while preserving their
  schema-history, Reader and independent-consumer obligations. #52 procedure
  execution remains a separate decision.
