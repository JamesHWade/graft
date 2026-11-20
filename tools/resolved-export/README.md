# Resolved-export ingestion conformance

Source-only evidence for [Graft #65](https://github.com/JamesHWade/graft/issues/65).
Read the [upstream proposal](../../specs/2026-11-19-resolved-export-ingestion.md)
for ownership, missing producer metadata, and the proposed public boundary.
These helpers are not Graft package exports or an implemented Commons API.

The fixture keeps current upstream execution separate from a **nonexecuting**
proposed contract. It contains no expression parser, SQL substitution engine,
model client, provider request, or production-store operation.

## Prepare an isolated environment

Requirements: R 4.3 or later, Rust/Cargo 1.92.0, platform build tools, and the R
dependencies below. A one-time dependency installation can use a temporary
library; `pak` must already be available to this installation command.

```sh
export GRAFT_RESOLVED_LIB=/tmp/graft-resolved-library
Rscript --vanilla - <<'R'
lib <- Sys.getenv("GRAFT_RESOLVED_LIB")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
pak::pkg_install(c(
  "commons=posit-dev/commons/pkg-r@03349a71ef3b64c80c6cd53f215ea870db2851a8",
  "datadict=tidyverse/data-dict/r@0161d460b6eb70d337028f8eddbf2f443bcb8f67",
  "ellmer@0.5.1", "duckdb@2.0.0",
  "any::testthat", "any::pkgload", "any::digest", "any::jsonlite",
  "any::yaml", "any::withr", "any::processx"
), lib = lib, ask = FALSE)
R

# Network/build step: verify immutable archives and compile the pinned CLI.
R_LIBS="$GRAFT_RESOLVED_LIB" Rscript --vanilla \
  tools/resolved-export/prepare.R /tmp/graft-resolved-cache

# Offline execution. Omit --output for a fresh automatically named directory.
R_LIBS="$GRAFT_RESOLVED_LIB" Rscript --vanilla \
  tools/resolved-export/run.R --cache /tmp/graft-resolved-cache
```

An optional `--output EMPTY_DIRECTORY` retains evidence at a chosen location.
The runner refuses a nonempty output directory so an old success record cannot
be confused with a new run. The dedicated
[`resolved-export.yaml`](../../.github/workflows/resolved-export.yaml) workflow
runs the same preparation and tests and uploads their evidence.

Preparation downloads the source archives identified by commit and SHA-256 in
[`pins.json`](pins.json), then uses `cargo build --release --locked`. It uses
Cargo's normal dependency cache and a build target directory inside the chosen
cache. On macOS it can select installed Command Line Tools for that process;
it does not change the system developer-directory setting. It never installs
R packages or modifies the package library.

The local `cli.json` build record binds the CLI bytes, source archive, lockfile,
toolchain, and reported version. It is a reproducibility/integrity record, not
an authenticated publisher signature. A changed cached archive or CLI fails
verification instead of being silently substituted. Use a fresh cache or
deliberately rebuild after inspecting an intentional pin change.

The test runner extracts the verified archives afresh, loads their R packages,
checks the pinned ellmer and DuckDB versions, and selects the prepared binary
through `DATA_DICT`. It does not install dependencies, fetch sources, or fall
back to another installed Commons/data-dict revision. A matching CLI version
string alone is insufficient: its bytes must match the local build record.

## Historical input identity

The dictionary and generation recipe come from
[the reviewed #61 fixture](https://github.com/JamesHWade/graft/tree/6d7bd84129c3bb2800509d3489719e31bece1ac7/tools/experiments/semantic-compatibility).
The original Parquet file was written to a temporary evidence directory and
was not committed. The committed 513-byte fixture was recovered with the original rows and
COPY settings under DuckDB 1.5.5. Every run checks those retained bytes against the independent
[historical result record](https://github.com/JamesHWade/graft/blob/6d7bd84129c3bb2800509d3489719e31bece1ac7/tools/experiments/semantic-compatibility/observed.json).

| Input | Historical SHA-256 required by the tests |
| --- | --- |
| Dictionary | `2b9ac2432abf8236963f6125d164aa9d1b909c24f6895dad4ab150adc26adfaa` |
| Parquet | `6eaf106b9009f4d416b1622b025f4e5ec226db5f81ed039b0e2c52566ff06016` |

Execution uses DuckDB 2.0.0. Its version is checked separately from the retained
input identity, so executing the fixture does not require rebuilding the old
engine used to recover the file. CI installs the repository binary and refuses
any version that differs from `pins.json`.

All current routes consume those exact recovered Parquet bytes or detached rows
read from them. Invalid-data and expression variants are separate files.
Numerical equality alone does not satisfy the historical identity check.

## What current public interfaces establish

| Case | Observed behavior checked by the fixture |
| --- | --- |
| Original data | Dictionary export and data-value validation succeed; the report is retained. |
| Total and filtered total | Public Commons `$metrics()` returns 35 and 15. |
| Derived dependency | Commons composes `SUM(doubled)` and returns 70. The exported dependency remains a bare reference. |
| Constant | Commons returns one metric row containing 42; the bare exported SQL produces 42 once per input row. |
| Row derivation | Public `$run_sql()` and bare DuckDB translation retain `20, 40, NA, 10`. |
| Invalid values | Data-value validation fails while profiling still succeeds. Commons construction is not data-value validation. |
| Missing and related references | The current validators/constructors reject the specific unresolved reference. |
| R-language definition | data-dict accepts `!is.na(revenue)`; the current Commons authored-dictionary route rejects it. |
| Mixed grain | Commons refuses a mixed row/aggregate expression as a metric dimension. |
| File measure | A separately authored R file measure remains callable alongside dictionary definitions and after proposed-contract refusal. |

The new direct Commons methods return data frames. They do not themselves
provide the older agent result's calculation labels, durable source identity,
or a validation receipt. The fixture does not manufacture that provenance.

CLI JSON documents are preserved as UTF-8 bytes with one trailing LF, because
the public `dd_run()` interface returns lines without transport separators.
The parsed export is kept alongside its exact retained bytes, path, and digest.
Validation reports and plain JSON observations are retained under the evidence
directory. `run.json` records producer pins, CLI identity, package versions,
and test outcomes; it is written as passed only after the suite succeeds.
The checked-in [`observed.json`](observed.json) retains the qualified local
run's results and source identities. It is a dated observation, not a substitute
for rerunning the suite or checking the PR's current CI.

## What the proposed contract establishes

The current export lacks explicit scalar/row/aggregate/mixed grain and
validator-produced input digests. The tests therefore pass a visibly
**fixture-only proposed supplement** and host observations. They refuse missing
metadata rather than inferring it from expression text or the lossy kind label.

Admission and request tests check exact content bindings, validation outcome,
typed definitions, reference consistency, dependency cycles, supported target
selection, and query roles. They retain original language, canonical reading,
fidelity, and translation notes/refusals. Host paths are supplied explicitly;
the fixture never follows a source path embedded in an export.

The column-type check is deliberately bounded to the fixture's scalar types,
number identifiers/quantities, and enums. It refuses richer nested types; it
does not parse or implement data-dict's type language. Request selection uses
the admitted in-memory record and does not revalidate files after admission.

The result is an inspectable nonexecuting selection. Dependency closure does
not solve target-aware composition, quoting, or physical-name rewriting. Those
need an upstream-defined symbol/template contract that the current producer
does not emit. No selected code is substituted into SQL or evaluated as R.

These tests prove the fixture's rejection and preservation rules. They do not
independently prove the truth of hand-authored grain or host validation claims,
that a concurrently mutable path remained stable while another process read
it, or that a real Commons constructor consumes this proposed object.

## Module layout

| File | Responsibility |
| --- | --- |
| `upstream.R`, `fixtures/` | Preserve exact historical inputs and call current public upstream interfaces. |
| `contract.R` | Nonexecuting proposed admission and request-role checks. |
| `tests/test-upstream.R` | Current numerical results, counterexamples, and independent file measures. |
| `tests/test-contract.R` | Proposed metadata, identity, refusal, and preservation behavior. |
| `runtime.R`, `tests/test-runtime.R` | Source/CLI integrity checks and rejection of mismatched cached inputs. |
| `pins.json`, `prepare.R`, `run.R` | Immutable preparation and the standalone offline runner. |

## Qualification boundary

The tested numerical scope is the pinned synthetic DuckDB fixture. Current
Commons and data-dict still parse independently; running both is not compiler
unification. Neither the fixture nor the proposal establishes other backend
execution, production authorization, validator-bound snapshot admission,
concurrent mutation safety, or Graft's Reader/durability/Forget requirements.
Upstream implementation and publication remain separate work.
