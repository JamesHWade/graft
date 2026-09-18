# Artifact, memory and shared-meaning experiments

These are bounded, disposable architecture experiments for #59–#63. They add no
public Graft APIs and do not change any existing user store. The suite compares
Graft with a manifest-based composition under the same behavior checks, then
integrates each with current Commons and data-dict.

## Run

From the repository root, provision dependencies into an isolated directory:

```sh
export GRAFT_EXPERIMENT_HOME="/tmp/graft-experiment-dependencies"
Rscript tools/experiments/setup.R
Rscript tools/experiments/run.R
```

Setup requires network access, Rust/cargo, normal R build dependencies and a
writable temporary directory. It installs the pinned upstream sources into its
own library, installs this Graft checkout, and builds the matching data-dict CLI.
`pins.json` identifies the development sources. The current Tempest pin includes
[Tempest #73](https://github.com/JamesHWade/tempest/pull/73), which explicitly
supports the tested Graft 1.0 consumer contract alongside 0.x (>= 0.2.0, < 2.0.0).
Merge that consumer update before
using the new Graft API with an unpinned Tempest installation. `dependency-snapshot.json` records
the complete resolved R package set, R 4.6.1 and the FTS extension revision from
the successful Linux evidence run. Setup requests those exact package versions;
setup and every runner reject missing packages or version drift before producing
evidence. Every runner also verifies each development package's installed
`RemoteSha` against `pins.json`; matching version strings alone are insufficient.
Updating the snapshot is a deliberate change requiring a new full run.
Pins marked `install_dependencies: false` are installed separately after the
complete hard-dependency snapshot. Tempest requires this because its floating
`Remotes` otherwise conflicts with the pinned Deputy revision once upstream moves.
The deferred installation uses the exact source SHA without dependency expansion;
all subsequent source, version and integrity checks remain mandatory.
`versions.json` is setup's attestation of installed versions, source pins and the
CLI digest. Setup also records installed-tree digests for all pinned
development packages; every runner rejects changed payloads even when package
version and source metadata remain unchanged.
Every runner requires the attestation and verifies the selected CLI's exact bytes
against that digest and its declared source pins against `pins.json`. An
unattested manual library/binary combination is rejected even if versions match.
Setup always reinstalls Graft from the current checkout and records digests of
its runtime/build inputs and installed package payload. Runners reject changed
Graft sources or installed bytes even without a version bump. Experiment reports
and other documentation edits do not require reinstalling unchanged runtime code.
The CLI is built from a newly downloaded and extracted pinned archive each time;
existing source directories are neither trusted nor overwritten. CI seeds an
invalid legacy cache to verify this behavior.
CI scopes GitHub authentication to provisioning steps and disables checkout's
persisted credentials. Runtime steps clear GitHub token variables and assert
that they are empty before executing the experiments.
System libraries and OS images are not locked; this is a package snapshot, not a
bit-for-bit environment image.

Setup also installs the FTS extension used by Commons context search into an
isolated cache under `GRAFT_EXPERIMENT_HOME/duckdb` and records its version and
location. This requires DuckDB 1.5.5 or newer. The generated environment exports
`DUCKDB_R_HOME` so child processes use that same cache. The runner checks that FTS
is installed before it starts the experiments.

The runner itself is offline and credential-free. Set `GRAFT_EXPERIMENT_HOME` to
the directory produced by setup; the runner loads its generated `environment.R`
and verifies its `versions.json` attestation before execution.
Standalone runners use this same preflight; vocabulary and roundtrip execution
fail before constructing Commons when the recorded FTS extension is missing. Set
`GRAFT_EXPERIMENT_OUTPUT` to retain result JSON, validation reports and exports;
otherwise a temporary evidence directory is created. Failed checks exit nonzero.

Commons' native OS sandbox must work. A surrounding sandbox that prevents
`sandbox_init` needs execution outside that outer sandbox, while retaining
Commons' own sandbox. Do not enable its unsafe fallback to make tests pass.
macOS builds may need `DEVELOPER_DIR=/Library/Developer/CommandLineTools` when
Xcode is selected but unavailable. No system setting needs to be changed.

## Sequence and evidence

| Experiment | Code | Recorded interpretation |
| --- | --- | --- |
| #59 persistent artifacts | [artifacts](artifacts/README.md) | [Results](../../specs/2026-09-16-artifact-experiment.md) |
| #60 shared vocabulary | [vocabulary](vocabulary/README.md) | [Results](../../specs/2026-09-16-vocabulary-experiment.md) |
| #61 compiler compatibility | [semantic compatibility](semantic-compatibility/README.md) | [Results](../../specs/2026-09-16-semantic-compatibility.md) |
| #62 full Commons roundtrip | [roundtrip](roundtrip/README.md) | [Results](../../specs/2026-09-16-commons-roundtrip.md) |
| #64 Tempest checkpoint migration | [tempest-migration](tempest-migration/README.md) | [Results](../../specs/2026-09-16-tempest-migration.md) |
| #64 Tempest artifact reuse | [tempest-reuse](tempest-reuse/README.md) | [Results](../../specs/2026-09-17-tempest-reuse.md) |
| #64 direct Tempest acceptance | [tempest-cycle](tempest-cycle/README.md) | [Results](../../specs/2026-09-17-tempest-acceptance-cycle.md) |
| #50 supported Tempest adoption | [tempest-artifact-adoption](tempest-artifact-adoption/README.md) | Public Graft storage and decision interfaces |
| #63 architecture decision | All above | [ADR 0007](../../adr/0007-test-artifact-composition-before-expanding-graft.md) |

The dedicated GitHub workflow reruns the complete suite on Linux and uploads
results. These research sources are excluded from the built R package. Report
runtime results separately from source inspection and from production readiness.
Backwards compatibility is not required in this pre-production project. A working
redesigned consumer must still preserve its required artifact and research
behavior. Reader isolation, erasure/restore and concurrent durability remain
requirements before production use.
