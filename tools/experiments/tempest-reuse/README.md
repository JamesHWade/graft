# Tempest artifact input and reuse

Run from the repository root after `tools/experiments/setup.R`:

```sh
GRAFT_EXPERIMENT_OUTPUT=/tmp/graft-reuse-evidence Rscript tools/experiments/run.R
```

The full runner produces the native migration fixture before this consumer step.
For a standalone rerun, use a fresh output directory and run
`tempest-migration/run.R` followed by `tempest-reuse/run.R` with the same
`GRAFT_EXPERIMENT_HOME` and `GRAFT_EXPERIMENT_OUTPUT`.

The host checks purpose and current eligibility, resolves the initial or corrected
four-record selection, and supplies exact text and artifact revision references to
Tempest's public `tempest_artifact_knowledge()` constructor. Original native
snapshots, receipts and revision mappings are inert provenance.

A fresh consumer process has Tempest and its required dependencies but no Graft
installation. It creates initial, unchanged and corrected sessions through public
APIs, saves and resumes each, then checks the public source table and retained
selection. No model request is made. The fixture demonstrates input admission and
saved-session reuse, not a newly generated report or future artifact acceptance.

Tests reject missing content, changed bytes and dependency revision substitutions.
Host checks reject the wrong purpose and withdrawn selection while historical
inspection remains available. These checks run before admission; active-run
revocation and production storage recovery are outside this experiment.

`results.json` records assertions and exact package pins. Session bundles remain
in the output directory. [Interpretation](../../../specs/2026-09-17-tempest-reuse.md).
