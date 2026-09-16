# Tempest checkpoint migration result

Experiment #64, September 16, 2026. The [runnable fixture](../tools/experiments/tempest-migration/README.md)
uses Tempest at `3cfe220577bdce61ee3b94684cc4ffdf5e1fdb83` and the complete pinned
environment shared by the artifact experiments.

## Decision

**Reduce scope and retain Graft for the existing Tempest integration.** Historical
content is portable, but the competing reader does not satisfy Tempest's current
public knowledge-admission contract. This result supports a small artifact
boundary; it does not justify retiring Graft or migrating user stores now.

Calling `tempest_knowledge()` with the portable result produces the expected
`tempest_knowledge_error`: the input must be a valid pinned Graft view. The
experiment does not bypass that check, construct an internal `TempestKnowledge`,
or relabel an artifact digest as a native snapshot.

## Executed evidence

The [recorded local run](../tools/experiments/tempest-migration/observed.json)
passes **43 assertions**, plus source-integrity and rollback guards.
The complete experiment is also part of the Linux CI suite.

| Evidence | Result |
| --- | --- |
| Public promotion | Both shipped completed-product bundles pass loading, planning, commit, and receipt verification |
| Unchanged acceptance | A new receipt retains the original four-record selection without new record revisions |
| Accepted history | 11 native revisions, including the original claim's reviewed supersession |
| Acceptance evidence | Three original receipts and both original promotion bundles/manifests retained |
| Exact evidence | Four Claim/ClaimSupport/EvidenceSpan/Source resources at each checkpoint |
| Target | 12 artifacts: 11 revision payloads and a root with identity mapping, receipts, snapshots, schemas, reports, and evidence |
| Independent reader | Fresh process with jsonlite, digest, and rlang; neither Graft nor Tempest available |
| Native admission | Explicitly rejected by Tempest's public constructor |
| Withdrawal | Revoked selection stays ineligible; importing into a nonempty target cannot rewrite its policy |
| Rollback | Both native checkpoints reopen read-only; reports, resources, snapshots, and the source directory digest match |

The first report says the synthetic pilot recovered 82%; the correction says
62%. Both reports and exact evidence selections survive. The old Claim remains
`active` at its original snapshot and `superseded` in its later revision, with
its predecessor, batch, schema, and acceptance order preserved.

## Preserved identities and bytes

The transfer retains store identity and format, schema identity, snapshots and
accepted boundaries, batch IDs, revision IDs/numbers, predecessor links, plan
IDs/digests, bundle IDs, and receipt IDs. It exports the complete required public
history for the records covered by the selected receipts. This is not a general
export of every record in an arbitrary source store.

Native revision IDs map to exact artifact references. Their payloads retain the
native IDs; the root depends on every imported revision. Missing receipt coverage,
predecessors or evidence links, cross-store snapshots, changed schema bytes, and
corrupt content fail explicitly.

Both the original schema file and normalized runtime manifest are retained; their
fingerprints differ under Graft's current loader. Original promotion bundle bytes
are checked against their manifests. Native POSIX timestamps use tagged hexadecimal
epoch values so JSON preserves fractional seconds. Tempest's new retrieval time
is a read event; resource comparisons retain content, identity, and revision
metadata without requiring two reads to have the same timestamp.

## Implementation cost and missing machinery

The producer/rollback fixture, migration adapter, and runner contain 231, 337,
and 91 physical lines respectively, including comments and blank lines. Shared
content and metadata-driver modules add 425 lines. Tests, provisioning, and
upstream packages are additional. This is an inventory, not a latency, storage,
maintenance, or production-cost benchmark.

Normal target reads need three packages; source production still needs Tempest
and Graft. The full experiment snapshot expands from 96 to 101 packages with
Tempest, Deputy, dsprrr, Rapp, and yaml12. All pinned development packages receive
source and installed-payload attestation.

A replacement still needs a public Tempest ingestion contract, a writer and
acceptance model for future research, broader schema/history export, interrupted
publication recovery, safe orphan handling, concurrent access, authorization,
active-task revocation, erasure, and backup admission. An interrupted import can
leave an incomplete target; this prototype requires a new empty destination and
implements no production cleanup or recovery protocol.

## Unsupported cases and next step

The profile rejects deletion/tombstone operations. Graft has no public general
deletion API for this producer; no direct SQL mutation or forged receipt was used
to imply a completed Tempest deletion journey. Target withdrawal and native
supersession are tested separately.

The promotion bundles retain source metadata and excerpts, not complete external
web bodies. ProgramArtifact records contain identities, not executable payloads.
Those unavailable bytes are an explicit export limitation; hashes do not recreate
them. The host supplies a trusted handoff digest; retained receipts do not
authenticate an untrusted export or create new acceptance events.

#64 remains the migration gate: historical-read parity is proved for this fixture,
while public consumer admission, deletion coverage, and production replacement
remain unproved. The next useful step is a minimal public Tempest ingestion seam,
tested against the same reference output. There is no evidence here to expand
Graft's semantic compiler or Commons wrapper.
