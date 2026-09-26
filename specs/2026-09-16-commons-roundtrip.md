# Commons artifact and selected-memory roundtrip

Experiment #62, September 16, 2026. See the
[runnable fixture](https://github.com/JamesHWade/graft/blob/6d7bd84129c3bb2800509d3489719e31bece1ac7/tools/experiments/roundtrip/README.md).

## Observed result

Both Graft and manifest metadata compositions pass the complete roundtrip:
30 testthat assertions across the two backends, plus fail-fast checks on actual
Commons results, binding/dictionary identity, validated input, table values,
PNG signatures and unchanged approval. Each output basis retains **16 exact
objects**, including the report/table/figure, producer evidence, original inputs,
and the complete vocabulary/binding/dictionary release bytes.

An unchanged consumer recovers identical content in a new process. A later
correction changes the computed total from 6 to 7; original report and dependency
bytes remain recoverable after the correction. An explicitly approved but stale
input selection is refused before Commons construction. A generated output is
stored while the existing input approval remains unchanged; the host separately
approves it for later use. Withdrawal denies consultation while historical
inspection still works. Revising a withdrawn input selection preserves its
policy bytes; restoring its original input revisions does not restore eligibility.

The underlying tools are real Commons and ellmer. Only the model's HTTP responses
are scripted, through public httr2 mocking. The calculation result is tagged A;
the JSON export and plot from the sandboxed R worker retain their B labels. The
host saves public `ContentImageInline` PNG data, exported JSON as Parquet, answer
text, and a separate provenance record with exact input selections and Commons
SQL/labels. It does not relabel storage or general retrieval as a trusted measure.

## Meaning is part of the same dependency closure

The integrated release extends #60's two laboratory dictionaries with an explicit
third binding for the actual calculated `evidence.sample` and `evidence.value`
columns. The sample importer checks the real detached data; the runtime dictionary
SHA must match the validated release reference. A synthetic quantity is assigned
its own term and arbitrary units, not silently identified as temperature.

Commons context retrieval returns the preserved report revision and vocabulary
release identity. The same Parquet bytes used for calculation pass explicit
data-dict value validation. The typed empty table also passes a real SQL count
query. This proves consistent structural binding and preservation, not scientific
truth or permission to join independently scoped datasets.

## What remains unproved

- A real model's analysis quality or factual correctness. The report and raw
  citation markup are scripted; the artifact record preserves them without
  claiming a rendered, independently verified citation or hosted OTEL trace.
- A generic stable Commons output-artifact API. The fixture uses public turn
  content but pinned model-facing schemas and explicit JSON export code. A
  supported upstream export contract would reduce host protocol assumptions.
- Revocation during an already running task or erasure of its materialized chat.
  The demonstrated host constructs a fresh agent after each policy/staleness
  check. Production task fencing, Reader authentication and Forget are still
  #47/#48/#51.
- Production storage. External bytes and metadata are separate publications;
  neither composition gains cross-store transactions from the roundtrip.

The first attempt inside Codex's outer sandbox could not initialize Commons'
macOS sandbox. Repeating the same offline fixture outside that outer sandbox
allowed Commons to establish its own OS sandbox; no unsafe fallback was enabled.
The dedicated Linux CI also requires the real sandbox and fails on worker errors.

The upstream package pins and local runtime versions are the same as #61. The
runner emits fresh `roundtrip.json` evidence; `observed.json` records the local
reviewed result without temporary paths or user data.
