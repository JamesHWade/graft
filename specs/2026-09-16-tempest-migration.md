# Tempest checkpoint migration result

The [September 17 follow-up](2026-09-17-tempest-reuse.md) closes the artifact input
and saved-session reuse gap described below. This page records the original
migration result; future artifact acceptance and lifecycle work remain open.

Experiment #64, September 16, 2026. The [runnable fixture](https://github.com/JamesHWade/graft/blob/6d7bd84129c3bb2800509d3489719e31bece1ac7/tools/experiments/tempest-migration/README.md)
uses Tempest at `3cfe220577bdce61ee3b94684cc4ffdf5e1fdb83` and the complete pinned
environment shared by the artifact experiments.

## Decision

**Reduce scope and redesign the Tempest input boundary.** Historical content is
portable. The current constructor requires a Graft view, but this project is
pre-production: backwards compatibility is not a requirement, and the constructor
can change. Its rejection of the portable view is an integration task, not
evidence that Graft must survive. Judge the replacement by required artifact and
research behavior and total complexity.

Calling `tempest_knowledge()` with the portable result produces the expected
`tempest_knowledge_error`: the input must be a valid pinned Graft view. The
experiment does not bypass that check, construct an internal `TempestKnowledge`,
or relabel an artifact digest as a native snapshot.

## Executed evidence

The [recorded local run](https://github.com/JamesHWade/graft/blob/6d7bd84129c3bb2800509d3489719e31bece1ac7/tools/experiments/tempest-migration/observed.json)
passes **121 assertions**, plus source-integrity and rollback guards.
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
| Rollback | All three original receipts validate against native snapshots and revisions; both report selections are rebuilt from their receipts; reports, resources, snapshots, and the source directory digest match |

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

An independent public read at the final snapshot records the expected head of
every exported record. Validation compares each head with the terminal retained
revision, so dropping a later supersession fails even when receipts still resolve.
Export format 2 requires these heads; regenerate earlier experimental exports.

Native revision IDs map to exact artifact references. Their payloads retain the
native IDs; the root depends on every imported revision. Each receipt must cover exactly the source bundle records, resolved by their
Tempest promotion keys at the acceptance boundary. Each checkpoint must select
all evidence records from its own receipt. Truncations, duplicate substitutions,
missing predecessors or evidence links, cross-store snapshots, changed schema
bytes, and corrupt content fail explicitly.

Both the original schema file and normalized runtime manifest are retained; their
fingerprints differ under Graft's current loader. Original promotion bundle bytes
are checked against their manifests. Native POSIX timestamps use tagged hexadecimal
epoch values so JSON preserves fractional seconds. Tempest's new retrieval time
is a read event; resource comparisons retain content, identity, and revision
metadata without requiring two reads to have the same timestamp.

## Implementation cost and missing machinery

The producer/rollback fixture, migration adapter, and runner contain 304, 454,
and 94 physical lines respectively, including comments and blank lines. Shared
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

#64 now tracks the redesigned consumer: historical-read parity is proved for this
fixture, while working Tempest ingestion and required deletion/withdrawal behavior
remain unproved. The next step is a minimal artifact input contract in Tempest,
tested against the same reference output. Breaking current APIs is acceptable;
preservation of the old constructor is not a gate. There is no evidence here to expand
Graft's semantic compiler or Commons wrapper.
