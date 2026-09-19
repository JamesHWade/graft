# graft

Persistent artifacts and shared vocabulary for R

## Keep what you learn. Return to the exact evidence.

Retain reports, evidence and shared concepts after the workflow ends.
Record what a host accepted, preserve earlier revisions, and give a
later task the exact artifacts behind an answer.

[Retain your first
artifact](https://jameshwade.github.io/graft/articles/getting-started.md)
[Share concepts across
workflows](https://jameshwade.github.io/graft/articles/shared-vocabulary.md)

## From a result to persistent memory

A workflow produces a conclusion. A person reviews it. A later task
needs both the original answer and the evidence behind it. Graft keeps
immutable artifact revisions and exact dependency selections so a
correction can coexist with the history it replaces.

| Retain | Review | Reuse |
|----|----|----|
| Save artifact bytes and select exact dependencies. | Record the host’s acceptance or withdrawal for a stated purpose. | Verify the selected bytes and check current host eligibility. |

Saving or selecting an artifact does not approve it. Historical
inspection preserves evidence of an earlier decision; a new task still
needs current permission. Applications decide access, scientific
validity, review and retention.

## Start in R

``` r

pak::pak("JamesHWade/graft")

library(graft)
store <- graft_artifact_store("research-artifacts", create = TRUE)
report <- graft_artifact_save(
  store, "report:pilot", charToRaw("Pilot evidence and conclusions"), "text/plain"
)
selection <- graft_artifact_select(store, list(report))
rawToChar(graft_artifact_read(store, report)$bytes)
```

The
[quickstart](https://jameshwade.github.io/graft/articles/getting-started.md)
runs offline and introduces exact revisions, selections and host
decisions. The core artifact workflow requires neither a schema compiler
nor model credentials.

## Choose your next workflow

### Preserve a reviewed result

Retain a report with its evidence and record acceptance or withdrawal
without rewriting its earlier bytes.

[Use artifacts and
decisions](https://jameshwade.github.io/graft/articles/persistent-artifacts.md)

### Share concepts and relationships

Bind vocabulary to exact data-dict dictionary releases. Reopen the
retained source and rendered context without the original files.

[Build a shared
vocabulary](https://jameshwade.github.io/graft/articles/shared-vocabulary.md)

### Verify a replacement store

Preview exclusions and verify exact survivors in a separate store. Keep
Forget approval and backup admission with the application.

[Build a verified
replacement](https://jameshwade.github.io/graft/articles/artifact-recovery.md)

### Understand the package boundaries

Compose Commons analysis, data-dict contracts and Graft persistence
while keeping application policy with the consuming product.

[Read the
architecture](https://jameshwade.github.io/graft/articles/architecture.md)

### Check integration contracts

Inspect the supported formats, optional dependencies and tested scope
before connecting a workflow.

[Read integration
requirements](https://jameshwade.github.io/graft/articles/compatibility.md)

## What works together

Commons supplies live analytical capabilities. Data-dict describes data.
Graft retains artifacts, exact selections, decision history and shared
meaning. Tempest and Rill consume this infrastructure as applications;
their scientific or Reader-specific policies remain theirs. Vocabulary
relationships describe meaning and do not execute reasoning, authorize
joins or select agent tools.

Tempest’s public artifact workflow publishes completed research and
retains its reports and evidence. New research and resume require fresh
host admission. See the [persistent artifact
guide](https://jameshwade.github.io/graft/articles/persistent-artifacts.md)
for the application handoff and its tested scope. Rill now retains
opt-in Reader Memory through scoped PostgreSQL artifacts. Permanent
Forget and durable restore remain rollout gates.

## Scope and status

Graft supports trusted local files with one writer and PostgreSQL scopes
inside host-owned transactions. Complete manifests and non-destructive
replacement plans verify retained objects. Power-loss recovery,
authenticated access, restore admission and permanent erasure remain
separate work. No interchangeable backend API is promised today.

Consumer contract **3.1.0** adds verified replacement mechanics.
Contract 3 removes the native graph store, LinkML compiler, commit
plans, graph snapshots, managed OKF tree and graph-specific agent tools.
There are no compatibility wrappers. Retained artifact, selection,
decision and vocabulary formats keep their exact identities.
