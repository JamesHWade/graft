# Tempest artifact input and cross-run reuse

Experiment #64, September 17, 2026. This follows the
[historical migration experiment](2026-09-16-tempest-migration.md) and uses the
exact sources in [pins.json](../tools/experiments/pins.json). Tempest
[`6d3386c`](https://github.com/JamesHWade/tempest/tree/6d3386cbbe22fdc0c1539c436e3ab2f4660567f3)
is the implementation in [PR #71](https://github.com/JamesHWade/tempest/pull/71).

The [recorded run](../tools/experiments/tempest-reuse/observed.json) passed all
28 reuse assertions; the complete six-experiment suite also passed, including
121 migration assertions and the source-integrity/rollback guards.

## Result and decision

Tempest can admit retained artifact evidence through a public input contract and
preserve it across saved-session reuse without Graft installed. The original
82% evidence, unchanged selection and corrected 62% evidence remain distinct.
Each input includes four exact Claim/ClaimSupport/EvidenceSpan/Source records,
content digests, dependency revisions, original receipts and native identity maps.
JSON object members are canonicalized; receipt values and array order remain exact.

This removes the Graft-only input boundary as a reason to retain Graft.
The decision remains **reduce scope while testing replacement**. Graft is still
the native producer in this fixture; future research acceptance into the artifact
store has not been implemented. This is not a completed retirement decision.

## Ownership

| Component | Responsibility |
| --- | --- |
| Host | Resolve exact retained bytes; check access, purpose and current eligibility; select revisions; enforce policy again before resume |
| Tempest | Validate content digests and dependency closure; interpret evidence; retain the input alongside run state |
| Artifact storage | Preserve content and immutable revision references |
| Commons and data-dict | Analytical execution and local data contracts; unchanged by this slice |

`tempest_artifact_knowledge(selection, contents)` creates a public research input.
It grants no approval or executable authority. The input contains no native Graft
view, and Tempest stores its complete selection separately from a Graft snapshot.
Provenance describes the source; a content digest does not authenticate a host or
prove that an assertion is true.

## Executed boundary

The [runner](../tools/experiments/tempest-reuse/run.R) starts a fresh process with
Tempest and required dependencies, explicitly checks that Graft cannot be loaded,
and creates three sessions using public constructors. Each is saved and resumed
after a fresh host eligibility check. The resumed session is saved again, and its
public sources and retained selection must match exactly. Host tests reject
wrong-purpose and withdrawn selections before admission and resume, including
withdrawal after a session was saved. A mismatched saved selection also fails.
Constructor tests reject
incomplete content, changed bytes and substituted dependency revisions.

No model is called. The experiment proves admission and saved-session reuse of
existing evidence. It does not claim newly generated research, future acceptance,
active-task revocation, erasure, concurrent publication or production recovery.
The previous migration checks continue to cover native history and rollback.

## Added machinery

This slice adds 112 lines of host translation/session exercise and a 128-line
runner, including comments and blank lines. Tempest's input module is 289 lines,
plus integration changes to its existing workspace and persistence paths. Tests,
documentation and the previously inventoried migration/storage implementation are
additional. These counts describe code size, not production cost or performance.
No new compiler, Commons facade or separate storage abstraction was introduced.

## Next experiment

Complete one research-to-artifact acceptance cycle: accept a new result, reuse it,
accept a correction, withdraw it, and verify that new consultation stops while
permitted historical inspection remains exact. Compare the remaining host and
storage mechanisms against Graft before choosing to retain or remove it.
