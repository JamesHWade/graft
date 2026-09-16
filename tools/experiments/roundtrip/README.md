# Commons artifact and memory roundtrip (#62)

Run `Rscript tools/experiments/roundtrip/run.R` from the repository root after
preparing the environment with [`setup.R`](../README.md#run) and setting
`GRAFT_EXPERIMENT_HOME` to that directory. The standalone runner checks setup's
CLI attestation, the package/source snapshot and FTS installation before Commons runs.
No model credentials or
network are used. Commons' own OS sandbox must be available for `run_r`; failures
are errors, never silently skipped or replaced with unsafe execution.

For each metadata backend, independent R processes:

1. Save the #59 source artifacts and explicitly approve an input selection.
2. Validate/preserve a release extending #60 with bindings for the actual
   `evidence.sample` and `evidence.value` columns used in the calculation. The
   synthetic quantity has arbitrary units and its own term, not a temperature
   equivalence. Validate the same Parquet bytes through data-dict.
3. Construct real Commons data/context layers, including a typed empty table.
   Script only the model's HTTP responses through public httr2 mocking.
4. Retrieve the saved report and vocabulary context, calculate through a
   data-dict metric, export the result through the sandboxed R worker as JSON,
   render a PNG, and generate an answer with raw citation markup.
5. Save report, Parquet result, PNG and execution provenance through the host.
   Graft/manifest identity and exact dependency evidence remain separate from
   Commons calculation/citation evidence. Saving leaves approval unchanged.
6. Approve the output, terminate, reopen, retain the complete selection on an
   unchanged run, revise inputs and generate a new result. Recover the original
   selected bytes after the new result exists.

The runner asserts both original total 6 and revised total 7, exact older bytes,
real PNG signature, typed-empty result, source revision visibility, calculation
label A versus R-worker label B, policy withdrawal and fresh-process identities.
It withdraws the prior input selection before revision and verifies that its
policy bytes remain unchanged. Restoring the original inputs clears staleness
but does not restore that selection's eligibility.
The model's answer and citation are scripted protocol data, not evaluated model
quality or independently verified factual support. No hosted OpenTelemetry
trajectory service, rendered citation UI or cloud artifact store is involved.

## Important boundaries

The public constructors configure Commons. Version-specific model-facing tool
names/arguments are fixture data, not a new host integration API. The host reads
public ellmer tool-result content and preserves observed labels/SQL/citation text.
The JSON table export is an explicit fixture protocol; the PNG is extracted from
public `ContentImageInline` content. A stable generic output-artifact export seam
would need an upstream contract before production reliance.

The host checks current eligibility and stale dependencies before every new
Commons construction. It rebuilds context instead of reusing cached chat copies.
This proves a fresh-agent boundary, not cancellation of an already-running task,
Reader authentication, deletion of earlier chat bytes, or cross-Reader isolation.
Those remain #47/#48/#51. Missing content/binding failure behavior is additionally
covered by the reused #59/#60 suites; neither constructor success nor a saved
receipt grants authorization or proves correctness.
