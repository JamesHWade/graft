# Tempest research acceptance cycle

Run from the repository root after `tools/experiments/setup.R`:

```sh
GRAFT_EXPERIMENT_HOME=/tmp/graft-experiment-dependencies \
GRAFT_EXPERIMENT_OUTPUT=/tmp/graft-cycle-evidence \
Rscript tools/experiments/tempest-cycle/run.R
```

Use a fresh output directory. The full suite runs this seventh experiment after
migration and reuse; this runner can also run independently.

`host.R` is a trusted single-writer experiment, not a public storage API. It reads
independently pinned completed Tempest proposals, stages immutable candidates,
and records explicit host acceptance. It checks current eligibility before public
Tempest admission and saved-session resume. Correction and withdrawal change
eligibility without rewriting historical selections. Idempotent retry returns the
old decision without making it current again.

Both metadata drivers run the same lifecycle and failure tests in independent
processes. The manifest producer and consumer have Graft unavailable. Raw bundles,
reports, Source bodies and evidence records are compared against the source
fixture. The runner writes `tempest-cycle/results.json`; `observed.json` records
the reviewed run. See the [result report](../../../specs/2026-09-17-tempest-acceptance-cycle.md)
for the ownership, retirement recommendation and limits.
