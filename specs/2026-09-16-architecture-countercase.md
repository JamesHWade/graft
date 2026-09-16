# Architecture countercase: reduce the boundary before retiring the ledger

Independent review for [#63](https://github.com/JamesHWade/graft/issues/63),
September 16, 2026. This challenges both automatic preservation and automatic
retirement of Graft. It is decision input, not a second accepted ADR.

## Recommendation

**Reduce Graft's proposed responsibility to persistent artifacts and explicit
selection records. Preserve its existing Tempest contracts until an actual
migration proves equivalence.** The eventual package name is immaterial. These
experiments do not justify combining an ontology engine, another compiler,
Commons internals and a ledger into one package.

The required reusable boundary is now concrete: preserve payload bytes and exact
meaning/dependency references; retrieve historical revisions; save bounded
selection records; distinguish saved output from host-approved reuse. A small
module can own this boundary and compose with Commons and data-dict. Its storage
backend must earn its operational complexity. Neither a directory of JSON files
nor Graft automatically earns the production role from these fixtures.

The publisher remains one tested internal module. Move the canonical expression
seam upstream; do not implement a third compiler. Leave computation, contextual
retrieval and calculation provenance with Commons. Leave approval, access and
reuse purpose with hosts.

## What the experiments discriminate

| Evidence | Inference supported | Inference not supported |
| --- | --- | --- |
| #59 runs one artifact contract over both metadata adapters | Graft is not necessary for this bounded content/revision/selection behavior; retained bytes and policy are custom glue on both paths | JSON files replace transaction, snapshot, recovery and operational behavior for all real consumers |
| #60 validates two dictionaries and publishes context without a Graft store | Shared vocabulary and binding checks have an independent module boundary | A separately distributed ontology package or reasoner is necessary |
| #61 validates one input with data-dict and calculates through real Commons tools, with a language divergence | Reuse both upstream packages, preserve their distinct contracts, and pursue a public resolved-export seam | One authored YAML file means one execution semantics implementation |
| #62 uses public constructors and real dispatched tools with deterministic transport | A host can supply retained context/data and save generated artifacts through the same storage boundary | Free-running model quality, semantic truth, production access control or live-chat revocation are proved |
| Most artifact lifecycle code is shared outside the two metadata adapters | Compare all custom code and policies; neither existing package already owns the whole lifecycle | Counting only the short manifest adapter establishes total lifecycle cost |

The [artifact README](../tools/experiments/artifacts/README.md),
[vocabulary results](2026-09-16-vocabulary-experiment.md),
[semantic conformance results](2026-09-16-semantic-compatibility.md), and
[roundtrip host](../tools/experiments/roundtrip/host.R) are the local evidence.
The final ADR should use the completed runner results, rather than treating code
inspection as runtime verification.

## Strongest case for retirement

The two artifact compositions intentionally implement the same logical identity,
content revision, dependency closure and host selection behavior. Commons
consumption does not need Graft-specific graph objects. data-dict already owns
local schemas and expressions; the publisher handles cross-dictionary meaning
without opening a ledger. For a new, synthetic, single-writer workflow, Graft
therefore adds a dependency without demonstrating an otherwise unavailable
required behavior.

That is sufficient to stop expanding Graft merely because it exists. New artifact
interfaces should expose concepts the user needs, not force hosts to learn its
current record/plan/snapshot representation. If a replacement satisfies the
production lifecycle and the real migration contract with less total complexity,
retirement is the right result.

## Strongest case against immediate retirement

The prototype's revision hash is not a native Graft revision or acceptance event.
A successful replacement of this fixture's metadata adapter says little about a
consumer that records immutable store snapshots and reviewed commit evidence.

Tempest at `bfc32f6cd387ac64aa628301e110396b668d69a7` is such a consumer. Source
inspection of its [Graft integration](https://github.com/JamesHWade/tempest/blob/bfc32f6cd387ac64aa628301e110396b668d69a7/R/graft-schema.R)
shows that promotion receipts bind store identity, plan/batch identity, schema
build digest, immutable snapshot identity, native revision ID/number, action and
content digest. It reopens committed snapshots and verifies actual accepted
records against the reviewed plan. Exporting latest rows plus payload hashes
would discard part of that contract.

This is a migration obligation, not an argument that every new caller needs the
same representation. Rill at `7769879c8e8f11f5305df3ada81822269b154fa4` has no
`graft` references in its `DESCRIPTION` or `R/` directory in the inspected local
checkout. Its planned storage integration is therefore not evidence of an
already implemented Graft runtime dependency. Neither inspection establishes an
inventory of deployed user stores or production data volumes.

## What would make retirement reviewable

Before choosing a replacement for Tempest, run one bounded real-consumer migration
fixture:

1. Use Tempest's real promotion path to create accepted evidence, a no-change
   checkpoint and a correction. Preserve every receipt and selected basis.
2. Export the required records, historical revisions, schema/snapshot references,
   acceptance evidence and retained payloads. Record any unsupported export
   boundary explicitly; do not substitute latest records.
3. Import into the proposed target with either preserved native identities or an
   explicit, immutable mapping from every source identity to its target.
4. Reopen both original and corrected checkpoints through a consumer adapter;
   compare exact selected content, historical evidence and revision relationships.
   Verify that withdrawal and existing tombstone semantics do not become renewed
   authorization. This is not a claim to implement permanent Forget.
5. Demonstrate rollback by reopening the unchanged source with its original
   receipts. Retain the source read-only until parity is established; do not make
   destructive migration part of an architecture experiment.

If the target needs to recreate most of the snapshot/acceptance machinery to pass,
that is evidence for retaining or reducing the existing ledger. If the mapping is
small and faithful, it is evidence for replacement. Migration cost should be
counted, but it must not become an indefinite excuse to keep unrelated code.

## Remaining limits that could change the choice

The artifact fixture explicitly bounds stores to small trusted local inputs and a
single writer. It does not establish power-loss durability, concurrent writers,
authoritative cross-store transactions, crash recovery between metadata and
current-index publication, orphan retention/collection, backup restore after
Forget, or authenticated Reader isolation. Graft's existing transactions may help
some obligations but do not make external byte storage atomic. The manifest path
must not receive credit for guarantees it has not implemented either.

The roundtrip rebuilds a fresh agent from admitted inputs. That is a useful host
pattern, but current admission checks do not invalidate an already materialized
chat copy by themselves. Production withdrawal requires an explicit host lifetime
and cache policy; #47/#48 remain gates under every package arrangement.

The roundtrip supplies a concrete companion binding for the actual
`evidence.sample/value` dictionary, checks the dictionary digest against the
validated reference, and exercises the plain R sample importer. This closes the
structural connection between vocabulary and calculation input. Its grain,
conditions and unit meanings remain synthetic author claims; validation does not
establish their scientific truth or a general comparison/join policy.

**Practical decision:** retain the working consumer contract, sharply reduce the
new architectural scope, and let production lifecycle tests plus one real Tempest
migration determine whether the ledger remains. No attachment to the name or
current module arrangement is required.
