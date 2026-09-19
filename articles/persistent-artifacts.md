# Persistent artifacts and selected memory

Your saved work should survive both the end of an R session and a change
in the software that stores it. Graft preserves reports, tables, figures
and the exact evidence selected for later workflows. Its decision
journal records host reviews and separates historical inspection from
current reuse.

## Save and reopen exact content

The shared local artifact interface preserves opaque bytes and verifies
them when read. It supports trusted local files with a single writer.
Application approval, access, concurrent publication, power-loss
durability and permanent erasure remain separate requirements; saving
these bytes grants no approval.

``` r

library(graft)
path <- tempfile("artifacts-")
store <- graft_artifact_store(path, create = TRUE)
original <- graft_artifact_save(
  store, "report:daily", charToRaw("Original report"), "text/plain"
)
corrected <- graft_artifact_save(
  store, "report:daily", charToRaw("Corrected report"), "text/plain"
)
reopened <- graft_artifact_store(path)
rawToChar(graft_artifact_read(reopened, original)$bytes)
```

    ## [1] "Original report"

``` r

rawToChar(graft_artifact_read(reopened, corrected)$bytes)
```

    ## [1] "Corrected report"

``` r

unlink(path, recursive = TRUE)
```

References contain an identity and immutable revision. Retain them with
your workflow; the store deliberately has no automatic latest or
approved selection. This project is pre-production. Consumer contract 3
removes the graph/compiler APIs. The experiments below remain
comparative evidence, not the installed storage code.

## Pin evidence and shared meaning

A dependency is an exact artifact reference. Store dictionary and
vocabulary releases as content, then reference them alongside the
evidence used in a report. The selection preserves their bytes; it does
not evaluate expressions or infer that two measurements are comparable.

``` r

path <- tempfile("artifact-selection-")
store <- graft_artifact_store(path, create = TRUE)
vocabulary <- graft_artifact_save(
  store, "vocabulary:lab", charToRaw('{"concept":"sample"}'), "application/json"
)
dictionary <- graft_artifact_save(
  store, "dictionary:assay", charToRaw("name: assay"), "application/yaml",
  dependencies = list(vocabulary)
)
report <- graft_artifact_save(
  store, "report:assay", charToRaw("Assay interpretation"), "text/plain",
  dependencies = list(dictionary)
)
selection <- graft_artifact_select(store, list(report))
graft_artifact_read_selection(graft_artifact_store(path), selection)$artifacts
```

    ## [[1]]
    ## [[1]]$id
    ## [1] "report:assay"
    ## 
    ## [[1]]$revision
    ## [1] "d2a512537a5aeb64afc0579652fe8fb59564e8dec59b3d590110c231b05588d4"
    ## 
    ## 
    ## [[2]]
    ## [[2]]$id
    ## [1] "dictionary:assay"
    ## 
    ## [[2]]$revision
    ## [1] "514407a409fccc678ce634b5f7794a362960bc555acb66ee3928186e9c853a5f"
    ## 
    ## 
    ## [[3]]
    ## [[3]]$id
    ## [1] "vocabulary:lab"
    ## 
    ## [[3]]$revision
    ## [1] "084f468d1dd656e8d360372e129b9421e28a561e4f26e48149a354868c14c6b9"

``` r

unlink(path, recursive = TRUE)
```

The returned list includes the report, dictionary and vocabulary
revisions. `max_metadata_bytes` separately bounds encoded selection
metadata (1 MiB by default). Increase it for many long artifact
identities and pass that limit on both selection creation and reading.
Similarly, open the store with a larger `max_revision_bytes` (default 1
MiB) when saving or reading artifacts whose dependency lists produce
large revision manifests.

`max_artifacts` bounds traversal and the store’s `max_bytes` bounds
total selected payload bytes. Reading rechecks the entire closure. Save
the selection identifier with the application workflow, then apply its
own access and reuse decisions. The decision functions below record host
acceptance; a selection alone is not accepted memory. The tiny
dictionary above illustrates opaque preservation, not a validated
data-dict contract.

## Record acceptance and withdrawal

Applications decide whether a candidate is acceptable and who may use
it. Graft records those decisions against exact selections. A stream
names one independently reviewed subject; a new operation key represents
a new review, even when its selection is unchanged.

``` r

path <- tempfile("artifact-decisions-")
store <- graft_artifact_store(path, create = TRUE)
report <- graft_artifact_save(
  store, "report", charToRaw("Reviewed report"), "text/plain"
)
selection <- graft_artifact_select(store, list(report))
accepted <- graft_artifact_decide(
  store, "research:topic", "review-1", expected = NULL,
  selection = selection, action = "accept", actor = "reviewer:alice",
  reason = "Supporting evidence reviewed", purpose = "research"
)
input <- graft_artifact_reuse(
  store, "research:topic", accepted$id, "research", eligible = TRUE
)
input$selection$artifacts
```

    ## [[1]]
    ## [[1]]$id
    ## [1] "report"
    ## 
    ## [[1]]$revision
    ## [1] "be41974429575fb1dffa3a66cc3e2cc4e3f3d6dd9983ef6cb558e8b3de05d147"

``` r

withdrawn <- graft_artifact_decide(
  store, "research:topic", "withdraw-1", expected = accepted$id,
  selection = selection, action = "withdraw", actor = "reviewer:alice",
  reason = "Evidence needs correction", purpose = "research"
)
graft_artifact_read_decision(store, "research:topic", accepted$id)$action
```

    ## [1] "accept"

``` r

graft_artifact_read_decision(store, "research:topic")$action
```

    ## [1] "withdraw"

``` r

unlink(path, recursive = TRUE)
```

The `eligible = TRUE` argument represents the application’s current
policy check; it is not an authentication mechanism. Reuse also requires
the current accepted head, an exact purpose match and intact selected
content. The earlier acceptance remains inspectable after withdrawal,
but cannot pass current reuse. Low-level reads remain available for
authorized historical inspection; applications must enforce access on
every route.

Always supply the predecessor observed during review. An identical retry
returns its original historical record and never restores eligibility. A
changed retry or stale new request fails. Withdrawal needs intact
decision history but remains possible when selected payloads are corrupt
or unavailable.

Each stream uses a bounded, append-only journal. Defaults allow 1,000
decisions and 1 MiB of aggregate journal metadata; selection bounds are
independent. Staging is not a committed decision. A complete immutable
record is the commit point, so an interrupted request can be retried
without duplicating acceptance. Concurrent writers, power-loss
durability and backup recovery remain separate operational work.

## From analysis to later reuse

Suppose Commons produces a report, table, and figure. A useful artifact
layer preserves their contents, stable identities, revisions, and
references to the exact inputs and meaning used to produce them. A
correction creates a new result while the original remains available for
historical inspection.

| Concern | Proposed owner |
|----|----|
| Local schemas, types, constraints, and expressions | data-dict |
| Shared concepts and qualified bindings across dictionaries | A separate internal vocabulary publishing module |
| Analysis, context search, and calculation evidence | Commons |
| Artifact contents, revisions, dependencies, and saved selections | Graft shared artifact infrastructure |
| Approval, access, reuse purpose, withdrawal, and active task lifetime | The application |

The vocabulary publisher connects domain concepts across workflows. A
binding can associate two local fields with the same concept while
retaining their source dictionaries and units. It does not by itself
establish that their values can be joined or compared.

## Persistent artifacts provide material for memory

A later workflow might select an approved interpretation, a dictionary
release, and three earlier results. The saved selection records those
exact revisions and their dependencies. An unchanged day retains the
full selection even when there is no new acceptance receipt.

Saving a draft and approving its reuse are separate actions. The
application checks current eligibility when it starts a new workflow.
Corrections and returning to an earlier input revision do not
automatically reapprove a withdrawn selection. The prototype permits the
application to explicitly approve it again; the application owns who may
do that and for what purpose. Historical access does not imply
permission to use that evidence in a new task.

The application also owns cancellation of active work, Reader identity,
and permanent Forget. A stored selection cannot erase copies already
given to a model.

## What “replaceable” means

Applications retain exact artifacts, dependency selections, and host
decisions. They do not depend on graph tables, a schema compiler, or
native store objects. A future storage implementation must preserve
those identities and history; Graft does not yet expose a pluggable
backend interface.

The earlier composition experiments compared native graph storage with
immutable manifests. Their source and observations remain in the
repository as historical research. They motivated the artifact contract
and the consumer contract 3 cut; they are not current native-store usage
instructions.

Shared infrastructure remains in Graft. Tempest and Rill own product
semantics, access, approval, and retention. Publication recovery remains
separate work in [\#49](https://github.com/JamesHWade/graft/issues/49).

## Use retained research in Tempest

Tempest now maps validated completed research into this artifact
contract. Its `tempest_publish_artifact_research()` retains the exact
evidence closure, source bodies, program provenance and readable report.
A host explicitly accepts that selection using
[`graft_artifact_decide()`](https://jameshwade.github.io/graft/reference/graft_artifact_decide.md).

`tempest_reuse_artifact_research()` validates the scientific evidence
and consults the current Graft decision using a host eligibility
callback. New runs and session resume recheck admission. The callback is
transient; session bundles retain content and decision provenance, never
a saved permission. Historical inspection uses
`tempest_read_artifact_research()` and does not grant reuse.

The [Tempest artifact
guide](https://jameshwade.github.io/tempest/articles/artifact-knowledge.html)
contains the installed offline example. Current Tempest consumer tests
exercise publication, fresh-process reads, corrections, and current
admission through these public interfaces. The earlier pinned experiment
suite remains historical evidence. These synthetic fixtures do not
establish production access or erasure.

## PostgreSQL and host-selected scopes

[`graft_artifact_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_artifact_store_postgres.md)
uses the same artifact, selection, decision, and vocabulary interfaces
inside a host-owned DBI transaction. Its optional DBI and RPostgres
dependencies are needed only for PostgreSQL stores.

``` r

DBI::dbWithTransaction(connection, {
  # The host derives this scope from authenticated identity and checks access.
  store <- graft_artifact_store_postgres(
    connection, scope = trusted_scope, create = TRUE
  )
  ref <- graft_artifact_save(store, "note", charToRaw("Accepted text"), "text/plain")
  selection <- graft_artifact_select(store, list(ref))
  accepted <- graft_artifact_decide(
    store, "note", "review-1", expected = NULL,
    selection = selection, action = "accept", actor = trusted_actor,
    reason = "Explicit review", purpose = "reader-context"
  )
  # Host catalog and receipt writes can use this same connection.
})
# Only successful transaction completion commits the operation.
```

Every retained row belongs to one scope. Graft serializes operations
within a scope until commit or rollback; the host can atomically retain
its own records in the same transaction. A scope key is not
authentication, and the database role can still access other scopes
directly. Applications must check access before every operation and
supply scope from trusted identity, including in background workers.
Connections and store handles are process-local.

This boundary does not implement permanent Forget or prevent an old
database backup from restoring deleted content. Those remain explicit
host and storage obligations before a broad memory rollout.
