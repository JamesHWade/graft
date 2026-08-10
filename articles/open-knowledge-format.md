# Work with open knowledge

The [Open Knowledge
Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf)
(OKF) gives accepted knowledge a human- and agent-readable working
surface. People can open Markdown, follow links, inspect provenance, and
review a Git diff without needing a database client.

Readable files are useful, but they are not a second source of truth. In
graft:

- The compiled Graft manifest is the domain contract.
- The revision ledger is the authority for accepted knowledge.
- OKF is a deterministic projection and proposal surface.
- [`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
  and
  [`graft_commit()`](https://jameshwade.github.io/graft/reference/graft_commit.md)
  are the route from edited files back to accepted knowledge.

This boundary keeps filesystem edits reviewable without allowing them to
bypass identity, validation, provenance, or commit preconditions.

## Configure the working tree

A file-backed store manages a sibling OKF directory by default. For
example, `knowledge.duckdb` uses `knowledge.okf` unless `okf_path` is
supplied.

``` r

library(graft)

schema <- graft_schema(system.file(
  "extdata",
  "personinfo.graft.json",
  package = "graft",
  mustWork = TRUE
))

store_path <- tempfile(fileext = ".duckdb")
okf_path <- tempfile(pattern = "graft-knowledge-")

store <- graft_open(
  schema,
  path = store_path,
  okf = "managed",
  okf_path = okf_path
)
```

Use `okf = "disabled"` when a store should have no managed working tree.
An explicit `okf_path` is useful when the readable projection belongs
inside a repository. If it is omitted, graft derives a sibling `.okf`
directory from the DuckDB filename. These are alternative
configurations; open the store only once with the one you want.

``` r

default_store_path <- "knowledge.duckdb"
default_okf_path <- "knowledge.okf"
```

## Synchronize accepted knowledge

After committing records, synchronize explicitly:

``` r

graft_ingest(
  store,
  list(
    Organization = data.frame(
      id = "org:daily-planet",
      name = "Daily Planet"
    ),
    Person = data.frame(
      id = "person:lois-lane",
      full_name = "Lois Lane",
      employed_by = I(list("org:daily-planet"))
    )
  ),
  graft_provenance(
    producer = "directory-import",
    idempotency_key = "daily-planet-v1"
  )
)

bundle <- graft_sync(store)
bundle
```

[`graft_sync()`](https://jameshwade.github.io/graft/reference/graft_sync.md)
stages and validates a complete deterministic bundle before replacing a
graft-managed destination. It never changes accepted records and does
not replace an unrelated directory.

Synchronization is separate from commit for a reason. Once a transaction
has accepted a revision, a later filesystem failure cannot make that
authoritative commit ambiguous. The working tree can simply be
synchronized again.

The bundle contains a navigable index and concept documents. Public
record content is stored in readable frontmatter and prose; object
references become links; source and revision identity remain traceable.
Sensitive fields are filtered according to the contract that governs
retrieval.

## Inspect state without changing it

``` r

status <- graft_status(store)
status$status
status$reason
```

[`graft_status()`](https://jameshwade.github.io/graft/reference/graft_status.md)
is read-only. It distinguishes these states:

- `current`: the working tree matches current accepted knowledge;
- `modified`: local edits form a proposal against the current accepted
  base;
- `stale`: the store has newer accepted revisions;
- `missing`: the configured working tree does not exist;
- `unconfigured`: the store has no managed OKF path; and
- `incompatible`: the bundle cannot be interpreted under the active
  contract.

Use `deep = TRUE` to verify the working tree’s content digest. Status
does not silently repair, overwrite, or accept anything.

## Treat edits as proposals

A person or tool may edit the structured record mapping in a concept
document. The edited file is still only a proposal. Review it with
explicit provenance:

``` r

concept_path <- file.path(
  bundle$path,
  "concepts",
  utils::URLencode("Organization", reserved = TRUE),
  paste0(utils::URLencode("org:daily-planet", reserved = TRUE), ".md")
)

contents <- readLines(concept_path, warn = FALSE, encoding = "UTF-8")
edited <- sub(
  "name: Daily Planet",
  "name: Daily Planet News",
  contents,
  fixed = TRUE
)
stopifnot(!identical(contents, edited))
writeLines(edited, concept_path, useBytes = TRUE)
```

``` r

review <- graft_review(
  store,
  provenance = graft_provenance(
    producer = "human-review",
    run_id = "review-17",
    idempotency_key = "approved-okf-edit-17"
  )
)

review@valid
review@changes
review@issues
```

[`graft_review()`](https://jameshwade.github.io/graft/reference/graft_review.md)
reads a stable snapshot, compares the proposed records with current
accepted revisions, and applies the same normalization, identity, and
contract validation as
[`graft_plan()`](https://jameshwade.github.io/graft/reference/graft_plan.md).
The returned `GraftCommitPlan` is bound to the exact bundle digest,
accepted base, active schema, and store.

Only complete managed bundles can be reviewed. Removing concept
documents is not a supported way to delete knowledge. Restore the
document before planning another proposal.

## Accept through the ordinary commit boundary

``` r

if (review@valid) {
  result <- graft_commit(store, review)
}
```

Committing rechecks both the ordinary plan preconditions and the OKF
source snapshot. If the files changed after review, the accepted base
advanced, or the contract changed, the commit fails without a partial
write. Review the new state and create a fresh plan.

After acceptance, synchronize the working tree to the new accepted
heads:

``` r

graft_sync(store)
graft_status(store)
```

The complete loop is therefore explicit:

``` text
accepted revisions -> sync -> readable files -> edit -> review -> commit -> sync
```

## Give agents the accepted view

[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
creates four read-only tool definitions backed by
[`graft_find()`](https://jameshwade.github.io/graft/reference/graft_find.md),
[`graft_get()`](https://jameshwade.github.io/graft/reference/graft_get.md),
[`graft_query()`](https://jameshwade.github.io/graft/reference/graft_query.md),
and
[`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md):

``` r

tools <- graft_tools(store)
names(tools)
```

The tool definitions expose bounded accepted retrieval, not filesystem
access or mutation. A modified OKF document remains a proposal until it
passes review and commit. The host decides which model provider, if any,
receives the tools.

``` r

graft_close(store)
unlink(store_path)
unlink(okf_path, recursive = TRUE)
```
