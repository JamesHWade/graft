# Commons and data-dict conformance experiment

Run from the repository root using the shared setup and its attested environment:

```sh
export GRAFT_EXPERIMENT_HOME=/tmp/graft-experiment-dependencies
Rscript tools/experiments/setup.R
Rscript tools/experiments/semantic-compatibility/run.R
```

Every runner verifies installed source pins and the CLI digest in setup's attestation.
The run is offline and credential-free. It writes a fresh temporary evidence
folder, or `GRAFT_SEMANTIC_OUTPUT` when explicitly supplied, containing immutable
Parquet inputs, validation reports, resolved exports, real Commons tool results,
and a JSON summary. The negative-value fixture is a separate file; the validated
input hash is checked after the calculations. No existing Graft store is opened.

## Dependency preparation

Use [`setup.R`](../README.md#run) to install and attest the isolated environment.
The tested runtime used R 4.6.1, DuckDB 1.5.5, and these source pins:

| Package | Repository and path | Commit | Version |
| --- | --- | --- | --- |
| Commons | posit-dev/commons, `pkg-r` | 726a2ed459c2b7c7aebc29539895f04873276b4f | 0.1.0.9000 |
| datadict | tidyverse/data-dict, `r` | 0161d460b6eb70d337028f8eddbf2f443bcb8f67 | 0.1.0 |
| data-dict CLI | same checkout | same commit | 0.0.3 |
| ellmer | tidyverse/ellmer, root | b6a8bbd4ced3922cf9397b392db6a3259ce19478 | 0.5.0.9000 |
| shinychat | posit-dev/shinychat, `pkg-r` | 88f7625846b096b6e0b2f88358969b854602e022 | 0.5.0.9000 |

Setup builds the CLI with `cargo build --release --locked -p data-dict-cli` and
records its digest; the runner rejects different bytes even at the same version.
The runtime summary records the directly exercised package versions. macOS here
required selecting the installed Command Line Tools for that process via
`DEVELOPER_DIR=/Library/Developer/CommandLineTools`. No system setting was changed.
A CRAN magick 2.9.1 binary supplied Commons' otherwise missing import. Package
installation/downloads require network; the experiment itself does not.

`model.R` supplies a deterministic model by mocking only HTTP transport through
`httr2::with_mocked_responses()`. Requests travel through a real public ellmer
client and Commons agent. The fixture speaks the pinned model-facing tool schema;
this is version-specific test data, not a proposed supported host tool API. It
never calls private tool constructors or modifies an R6 object's internals.

`observed.json` is the recorded result of the reviewed run. Rerunning produces
fresh evidence and checks; it does not compare wall-clock or temporary paths.
