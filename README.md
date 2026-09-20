# graft <img src="man/figures/logo.png" align="right" height="138" alt="Graft logo" />

Graft retains **persistent artifacts and shared vocabulary** for R workflows and
agents. Reports, evidence, dictionary releases, and other outputs remain readable
at exact revisions after the process that produced them has ended.

## What belongs here

- **Artifacts:** immutable bytes and descriptive metadata, with verified reads.
- **Selections:** explicit roots and their complete exact dependency closure.
- **Decisions:** host acceptance and withdrawal, purpose, history, and safe retries.
- **Vocabulary:** shared concepts and relationships bound to pinned data-dict
  dictionaries, with retained source bytes and rendered context.

Commons supplies live analysis capabilities. Data-dict describes data. Graft
retains their inputs, shared meaning, and outputs. Tempest and Rill are consuming
applications: they own research validation, user access, review, and retention
policy. Graft does not decide which claims are true or which tools an agent may use.

## Retain and reuse a report

```r
library(graft)
store <- graft_artifact_store("research-artifacts", create = TRUE)
report <- graft_artifact_save(
  store, "report:pilot", charToRaw("Pilot evidence and conclusions"), "text/plain"
)
selection <- graft_artifact_select(store, list(report))
accepted <- graft_artifact_decide(
  store, "pilot", "review-1", expected = NULL,
  selection = selection, action = "accept", actor = "reviewer",
  reason = "Evidence reviewed", purpose = "briefing"
)

# Reopen in a later process. The host supplies current eligibility.
store <- graft_artifact_store("research-artifacts")
graft_artifact_reuse(store, "pilot", accepted$id, "briefing", eligible = TRUE)
rawToChar(graft_artifact_read(store, report)$bytes)
```

Saving or selecting an artifact does not approve it. A later correction changes
current eligibility while preserving the earlier bytes and decision history.
Applications recheck admission before starting or resuming work.

## Shared meaning across workflows

[`graft_vocabulary_publish()`](https://jameshwade.github.io/graft/reference/graft_vocabulary_publish.html)
pins vocabulary, field bindings, and dictionary releases in one selection.
[`graft_vocabulary_read()`](https://jameshwade.github.io/graft/reference/graft_vocabulary_publish.html)
restores them without the original files or data-dict CLI. Relationships describe
meaning; they do not authorize joins, convert units, or execute reasoning.

## Scope and status

This pre-production package supports trusted local files with one writer and
PostgreSQL scopes inside host-owned transactions. Power-loss recovery,
authenticated access, and permanent erasure remain separate work. The artifact
contract allows future persistence implementations; no interchangeable backend
API is promised today.

Consumer contract **3.2.0** adds closed backup bundles and verified restore.
Contract 3 removes the native graph store, LinkML compiler,
commit plans, graph snapshots, managed OKF tree, and graph-specific agent tools.
There are no compatibility wrappers. Existing artifact, selection, and decision
formats keep their exact identities.

Read [getting started](https://jameshwade.github.io/graft/articles/getting-started.html),
[persistent artifacts](https://jameshwade.github.io/graft/articles/persistent-artifacts.html),
and [shared vocabulary](https://jameshwade.github.io/graft/articles/shared-vocabulary.html).

## Verified replacement stores

Preview exclusions and verify exact survivors in a separate store with artifact
manifests and replacement plans. See the [replacement guide](https://jameshwade.github.io/graft/articles/artifact-recovery.html).
Applications still own permanent Forget authorization, generation retirement,
backup admission, and disposal; these operations never delete source content.

Create a complete backup with `graft_artifact_backup()` and retain its identity
receipt separately. `graft_artifact_restore()` verifies the closed bundle against
that receipt before copying into an empty target. See the [backup guide](https://jameshwade.github.io/graft/articles/artifact-backups.html).
A matching receipt proves the expected contents; the application still checks
that the generation is currently eligible for restore.
