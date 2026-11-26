# Persistent artifacts and review history

Saved work should remain verifiable after an R session ends. Graft keeps
reports, tables, figures, and the exact evidence behind them as
immutable revisions, then records explicit host review decisions so
historical inspection stays separate from current reuse.

## Save and reopen exact content

A local store keeps content-addressed files on disk and verifies digests
on every read. Several R processes can write to one store: content
writes use atomic staged renames, and per-stream advisory file locks
serialize decision recording (on file systems that honor advisory
locks). Saving bytes never approves them for reuse.

``` r

library(graft)
```

    ## 
    ## Attaching package: 'graft'

    ## The following object is masked from 'package:base':
    ## 
    ##     Recall

``` r

path <- tempfile("artifacts-")
store <- graft_store(path, create = TRUE)
original <- graft_save(
  store, "Original report", id = "report:daily", media_type = "text/plain"
)
corrected <- graft_save(
  store, "Corrected report", id = "report:daily", media_type = "text/plain"
)
reopened <- graft_store(path)
graft_read(reopened, original)@data
```

    ## [1] "Original report"

``` r

graft_read(reopened, corrected)@data
```

    ## [1] "Corrected report"

``` r

unlink(path, recursive = TRUE)
```

An `ArtifactRef` pairs a logical identity (`@id`) with an exact
immutable revision (`@revision`). There is no mutable “latest” pointer:
keep the references your workflow depends on, or record a decision
stream when an application wants a reviewed current result.

Use
[`graft_save_file()`](https://jameshwade.github.io/graft/reference/graft_save_file.md)
to ingest a bounded file from disk explicitly; strings passed to
[`graft_save()`](https://jameshwade.github.io/graft/reference/graft_save.md)
are always treated as UTF-8 text content, never as file paths.

## Pin evidence with selections

Declare dependencies by passing one `ArtifactRef` (or a list of them) to
[`graft_save()`](https://jameshwade.github.io/graft/reference/graft_save.md).
Calling
[`graft_select()`](https://jameshwade.github.io/graft/reference/graft_select.md)
captures the roots together with their complete verified dependency
closure as an immutable `ArtifactSelection`:

``` r

path <- tempfile("artifact-selection-")
store <- graft_store(path, create = TRUE)
vocabulary <- graft_save(
  store, '{"concept":"sample"}',
  id = "vocabulary:lab", media_type = "application/json"
)
dictionary <- graft_save(
  store, "name: assay", id = "dictionary:assay", media_type = "application/yaml",
  dependencies = vocabulary
)
report <- graft_save(
  store, "Assay interpretation", id = "report:assay", media_type = "text/plain",
  dependencies = dictionary
)
selection <- graft_select(store, report)
reopened_selection <- graft_read_selection(graft_store(path), selection@id)
reopened_selection@artifacts
```

    ## [[1]]
    ## <ArtifactRef report:assay@d2a512537a5aeb64afc0579652fe8fb59564e8dec59b3d590110c231b05588d4>
    ## 
    ## [[2]]
    ## <ArtifactRef dictionary:assay@514407a409fccc678ce634b5f7794a362960bc555acb66ee3928186e9c853a5f>
    ## 
    ## [[3]]
    ## <ArtifactRef vocabulary:lab@084f468d1dd656e8d360372e129b9421e28a561e4f26e48149a354868c14c6b9>

``` r

unlink(path, recursive = TRUE)
```

`reopened_selection@artifacts` contains the exact revisions of the
report, dictionary, and vocabulary. `max_artifacts` bounds dependency
traversal, `store@max_bytes` bounds aggregate selected payloads, and
`max_metadata_bytes` / `max_revision_bytes` bound encoded metadata (1
MiB by default). Reading a selection re-verifies the entire dependency
chain.

## Record acceptance and withdrawal

Applications decide whether a candidate is acceptable and who may use
it. Graft records each decision in a named **decision stream**. Supply
the expected predecessor (`expected = NULL` for the first decision, or
the prior `Decision`) and a stable request `key` so stale reviews fail
and retries are idempotent:

``` r

path <- tempfile("artifact-decisions-")
store <- graft_store(path, create = TRUE)
report <- graft_save(
  store, "Reviewed report", id = "report", media_type = "text/plain"
)
accepted <- graft_accept(
  store, report, stream = "research:topic", key = "review-1", expected = NULL,
  actor = "reviewer:alice",
  reason = "Supporting evidence reviewed", purpose = "research"
)
input <- graft_recall(
  store, "research:topic", purpose = "research", eligible = TRUE
)
input@artifacts
```

    ## [[1]]
    ## <Artifact report@be41974429575fb1dffa3a66cc3e2cc4e3f3d6dd9983ef6cb558e8b3de05d147 media_type=text/plain bytes=15>

``` r

withdrawn <- graft_withdraw(
  store, "research:topic", expected = accepted, key = "withdraw-1",
  actor = "reviewer:alice", reason = "Evidence needs correction"
)
graft_history(store, "research:topic")[[1L]]@action
```

    ## [1] "accept"

``` r

graft_history(store, "research:topic")[[2L]]@action
```

    ## [1] "withdraw"

``` r

unlink(path, recursive = TRUE)
```

- `eligible = TRUE` stands in for your application’s current access
  check.
- [`graft_recall()`](https://jameshwade.github.io/graft/reference/graft_recall.md)
  verifies eligibility, purpose match, the stream’s current accepted
  head, and every selected byte. After withdrawal it returns status
  `"withdrawn"` with no artifact payloads.
- [`graft_history()`](https://jameshwade.github.io/graft/reference/graft_history.md)
  and
  [`graft_read()`](https://jameshwade.github.io/graft/reference/graft_read.md)
  keep earlier decisions and revisions inspectable for audit without
  re-approving them for reuse.
- `Decision@selection` holds the exact selection digest so histories can
  be inspected without materializing payloads.

## List what is kept

[`graft_streams()`](https://jameshwade.github.io/graft/reference/graft_streams.md)
returns each stream’s current decision so an application can display
what it has kept without maintaining a separate catalog. Pass `purpose`
to filter by purpose, and inspect `@action` to distinguish accepted
streams from withdrawn ones:

``` r

path <- tempfile("artifact-streams-")
store <- graft_store(path, create = TRUE)
report <- graft_save(store, "Reviewed report", id = "report")
graft_accept(
  store, report, stream = "project:reactor", key = "keep-1", expected = NULL,
  actor = "reviewer:alice", reason = "Kept to the project", purpose = "kept"
)
```

    ## <Decision accept stream=project:reactor sequence=1 id=7f8e25d1c66d60ead067f55450c776643232cc64a24f23e6e8863d27c36de404>

``` r

kept <- graft_streams(store, purpose = "kept")
vapply(kept, \(x) paste(x@stream, x@action), character(1))
```

    ## [1] "project:reactor accept"

``` r

unlink(path, recursive = TRUE)
```

Listing reads decision metadata only—it returns no artifact payloads and
requires no eligibility callback. Streams are returned ordered by name.

## Use PostgreSQL scopes

For multi-user or database-backed apps,
[`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md)
provides the exact same API inside a DBI transaction owned by your
application:

``` r

DBI::dbWithTransaction(connection, {
  # Derive scope from authenticated identity and check access first.
  store <- graft_store_postgres(
    connection, scope = trusted_scope, create = TRUE
  )
  ref <- graft_save(store, "Accepted text", id = "note", media_type = "text/plain")
  accepted <- graft_accept(
    store, ref, stream = "note", key = "review-1", expected = NULL,
    actor = trusted_actor,
    reason = "Explicit review", purpose = "reader-context"
  )
  # Application catalog writes can commit atomically in the same transaction.
})
```

Every retained row in `graft_artifact_objects` belongs to one `scope`,
and a transaction-level advisory lock serializes operations within that
scope. Rolling back the transaction undoes every write cleanly. Because
the scope key isolates data rather than authenticating callers,
applications should always derive `scope` from authenticated identity
and never let a model choose it.
