# Persistent artifact experiment

Experiment #59, September 16, 2026. The code is in
[`tools/experiments/artifacts`](../tools/experiments/artifacts/README.md).

## Observed result

Both metadata compositions pass a shared suite with **104 assertions total**, using real Markdown,
Parquet and PNG content. Producer, unchanged consumer and correction consumer
run in separate terminated R processes. They reopen only persisted JSON
identifiers and local stores; no live connection or RDS checkpoint crosses the
boundary. The complete five-artifact selection survives unchanged runs and
later source/report revisions. The stored draft is absent from that selection.

The test also covers purpose-specific approval, withdrawal versus inspection,
bounded previews, missing/corrupt content, transitive missing/corrupt dependencies,
stale proposals, capacity rejection before publication, interrupted publication,
lost acknowledgments and identical retry. Independent review found missing
transitive checks and asymmetric capacity enforcement; both now have regression
coverage on both backends.

| Responsibility | Manifest composition | Graft composition |
| --- | --- | --- |
| Actual retained bytes | Shared host content store | Same host content store |
| Metadata revisions | Immutable JSON manifests and current map | Public Graft plan/commit and history |
| Stable artifact revision | Fixture metadata SHA-256 | Same SHA-256 plus native Graft revision/commit evidence |
| Exact dependency closure | Shared host logic | Same host logic |
| Approval, purpose, eligibility | Explicit host selection/policy | Same host selection/policy |
| Cross-store transaction | Not supplied | Not supplied |
| Production Reader authorization and Forget | Not supplied | Not supplied by this experiment |

## What this establishes

Persistent artifacts do not require the current Graft ledger for this bounded
single-writer workload. They do require an explicit content and lifecycle owner:
Commons/data-dict alone did not perform the tested preservation and approval
operations. Most new behavior is shared glue, so compare the full composition
rather than only the backend adapter.

Graft adds independently useful native metadata history/commit evidence, but this
harness does not reproduce Tempest's complete existing receipt/snapshot contract
in the manifest path. It is not a migration proof or a production comparison.
See the [architecture decision](../adr/0007-test-artifact-composition-before-expanding-graft.md).

## Runtime and limits

The Graft package was installed from main
[`25ed779`](https://github.com/JamesHWade/graft/tree/25ed779aa34cd888da3212eec437ee2a64bfcca0).
The recorded local run used R 4.6.1 and DuckDB 1.5.5. Source and environment pins
for the integrated suite are in `tools/experiments/pins.json`; the runner records
actual runtime versions separately. No public package code or existing store was
changed.

Atomic rename is tested as process-visible publication on the local filesystem.
The experiment does not establish power-loss durability, simultaneous writers,
cloud object retention, physical erasure or backup recovery. Bytes and metadata
have separate commit boundaries. Orphan bytes are retained for retry; safe
collection and production recovery remain #49. Current lists and closures are
bounded at 50 objects, content at 1 MiB, Graft history search at 100 revisions.
These limits fail explicitly instead of silently advancing to current content.
