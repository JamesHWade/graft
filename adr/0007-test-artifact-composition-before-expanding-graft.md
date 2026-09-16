# ADR 0007: Reduce Graft's proposed role to persistent artifacts and selected memory

Date: 2026-09-16

Status: proposed, supported by experiments #59–#62; implementation and migration
remain separate. This ADR is the recommendation for #63.

## Decision

Pursue a small, explicit artifact boundary that composes Commons and data-dict.
Its responsibilities are retained payload bytes, stable artifact identity,
immutable revisions, exact meaning/dependency references, and bounded selection
records. Hosts decide saving, approval, purpose, access and current eligibility.
Keep the vocabulary publisher separate and internal until actual reuse justifies
its own distribution.

**Reduce scope; retain the existing Graft consumer contract for now.** Graft is
one candidate metadata driver behind that artifact boundary. It is not required
by the vocabulary or Commons integration, and its name and current arrangement
have no preservation requirement. The manifest driver remains an executable
replacement candidate. New callers should not inherit Graft's graph, compiler,
agent tools or OKF projection solely to preserve artifacts.

Stop adding competing semantic execution or Commons-wrapper APIs. data-dict owns
the expression contract; Commons owns analytical execution and its own result
provenance. The concrete upstream mismatch found in #61 should be addressed at
that seam, not with another interpreter here.

For existing Tempest consumers, keep the working native revision/snapshot and
promotion-receipt contract until a real migration proves equivalence. New Rill
integration is not an already deployed Graft dependency and should use the chosen
artifact boundary subject to its existing product/access/erasure gates.

This decision deliberately does not designate the toy manifest implementation as
production storage or remove working Graft APIs. It chooses what to build and
compare next, with a specific retirement test below.

## Evidence

| Experiment | Runtime result | Architectural consequence |
| --- | --- | --- |
| #59 | Both metadata paths pass the same 104 persistence/reuse/failure assertions | Retained content and host policy are required; the current ledger is not required for this bounded lifecycle |
| #60 | 16 cases validate portable bindings and use the release in plain R and Commons constructors without a Graft store | Keep one publishing module; ontology alone does not earn a ledger or reasoner |
| #61 | 37 checks exercise real data-dict/Commons on the same Parquet bytes; R-language definition diverges | Shared YAML is not shared execution semantics; pursue a public resolved-export contract upstream |
| #62 | Both paths preserve 16-object output selections across processes and correction, using real Commons calculation, context and sandboxed R outputs | Commons can generate/consume artifacts but still needs an explicit preservation/approval owner |

Results and reproducible commands are indexed in
[`tools/experiments/README.md`](../tools/experiments/README.md). The independent
[countercase](../specs/2026-09-16-architecture-countercase.md) challenges immediate
retirement and records what would reverse this decision.

## Total composition cost

The same host/content module owns byte preservation, digest checks, dependency
closure, selection approval and policy for both paths. The manifest driver adds
immutable metadata files and a current map; the Graft driver substitutes native
plan/commit, discovery and bounded history. Both require the same vocabulary
publisher, upstream packages, Commons host integration and artifact extraction.
Neither gets free production lifecycle guarantees from its short adapter.

The manifest option avoids a Graft runtime dependency, but must earn recovery,
concurrency and migration behavior before displacing an existing consumer. Graft
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

## Current consumers and migration obligations

Source inspection of Tempest at
[`bfc32f6`](https://github.com/JamesHWade/tempest/blob/bfc32f6cd387ac64aa628301e110396b668d69a7/R/graft-schema.R)
finds a real promotion/knowledge integration. Receipts and checkpoints bind store,
batch, schema build, snapshot and native revision identities. Its historical
selection and reviewed correction behavior must remain available or be explicitly
mapped; exporting current rows alone is insufficient.

Rill at `7769879c8e8f11f5305df3ada81822269b154fa4` has no `graft` references in its
inspected `DESCRIPTION` or `R/` sources. Its design ADRs and open #51 define intended
integration, not shipped migration cost. These are source inspections, not new
Tempest/Rill runtime acceptance tests. Deployed store inventory, owner approval,
retention and data volumes remain unknown; no user stores were searched, opened
or modified by the experiments.

Before retirement, a bounded real Tempest migration must:

1. Produce accepted evidence, a no-change selection and a correction through
   Tempest's public promotion path; retain original receipts/checkpoints.
2. Export the complete required history, schema and snapshot references, evidence
   closure and payloads. Fail explicitly on unsupported export cases.
3. Import using preserved identities or an immutable mapping for every source
   identity; resolve old and corrected selections through the proposed adapter.
4. Compare exact contents, revision/dependency relationships and acceptance
   evidence, including withdrawal/tombstone behavior without implying Forget.
5. Reopen the unchanged source with its original receipts as rollback evidence.
   Keep it read-only until parity and deployment-specific migration are approved.

Retire Graft if that target passes the real consumer contract and production
lifecycle with less total complexity. Retain only the mechanisms a competing
implementation otherwise has to reconstruct. Migration work is an explicit
bounded test, not an indefinite argument for preserving unrelated features.

## Existing ADRs and release gates

ADRs 0001–0004 and existing public calculation APIs continue to describe current
behavior. The new direction proposes moving future canonical execution work
upstream; it does not silently supersede current Definition semantics or perform
a hard-cut migration. A later implementation ADR must name any replaced contract.

ADRs 0005/0006 and #47/#48 remain production requirements under both storage
options: Reader isolation, authorized erasure, independent recovery state and
backup admission. The fixtures cover trusted single-writer process restarts, not
power loss, concurrent publishers, cloud retention, live-chat cancellation or
production authorization. Passing them is not permission to deploy broad memory.

## Bounded next work

- #49: design and test content/metadata publication, orphan retention, idempotency
  and crash recovery in the chosen artifact module. Use the shared harness and
  retain both metadata candidates until the operational comparison is meaningful.
- #64: run a real Tempest migration-conformance experiment as specified above; use
  #50's existing evidence rather than recreating its completed product proof.
- #65: propose a minimal public Commons ingestion seam for validated typed data-dict
  exports, including dependencies, grain, dialect and the R-language counterexample.
- #66: propose a supported Commons output-artifact handoff for completed table/image
  content and provenance; do not make the fixture's JSON/tool protocol a host API.
- #39/#51/#41 must use the selected artifact contract while preserving their
  schema-history, Reader and independent-consumer obligations. #52 procedure
  execution remains a separate decision.
