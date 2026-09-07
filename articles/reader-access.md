# Keep Readers' accepted knowledge separate

Two Readers may accept different interpretations of the same article. A
later task must use the authenticated Reader’s accepted knowledge, even
if another Reader has the same record ID. This offline example opens a
separate Graft store for each Reader and checks host authorization
before every read.

This is an application-owned teaching recipe for
[\#47](https://github.com/JamesHWade/graft/issues/47). It uses synthetic
records and grants, not Rill authentication. The [storage and access
proposal](https://github.com/JamesHWade/graft/blob/main/adr/0005-isolate-reader-knowledge-stores.md)
compares separate stores with shared scoped reads and specifies the
remaining Rill work. No Graft access-control API is added.

## Bind access in the host

The host supplies the Reader, store locator, and current grant revision.
These inputs must never come from model arguments or a saved reuse
basis. The recipe opens read-only, checks the expected store UUID,
collects the read, rechecks the grant revision, and closes the
connection. It returns a generic error when any step fails.

``` r

example <- new.env()
sys.source(system.file("examples/reader-access.R", package = "graft"), example)
directory <- tempfile("reader-access-")
dir.create(directory)
locations <- example$reader_access_fixture(directory)
grants <- new.env()
grants$alice <- "alice-grant-1"
grants$bob <- "bob-grant-1"
bind <- function(reader) {
  example$reader_knowledge_access(
    reader,
    locate = \(reader) locations[[reader]],
    grant = \(reader) grants[[reader]]
  )
}
alice <- bind("alice")
bob <- bind("bob")
alice(\(store) graft_get(store, "knowledge:preference"))$record$body
#> [1] "alice Prefer short reading sessions in the morning; this is a preference, not source evidence."
bob(\(store) graft_get(store, "knowledge:preference"))$record$body
#> [1] "bob Prefer short reading sessions in the morning; this is a preference, not source evidence."
```

The colliding ID resolves inside the selected store. A foreign ID and an
unavailable ID produce the same boundary error. Search and accepted
calculations only observe the selected Reader’s data.

``` r

unavailable <- function(read) {
  tryCatch(read(), reader_knowledge_unavailable = conditionMessage)
}
unavailable(\() alice(\(store) graft_get(store, "knowledge:interpretation:bob")))
#> [1] "Accepted knowledge is unavailable."
unavailable(\() alice(\(store) graft_get(store, "absent")))
#> [1] "Accepted knowledge is unavailable."
alice(\(store) nrow(graft_find(store, "bob")))
#> [1] 0
alice(\(store) graft_calculate(store, "knowledge_count"))
#>   knowledge_count
#> 1               4
bob(\(store) graft_calculate(store, "knowledge_count"))
#>   knowledge_count
#> 1               3
```

Separate files matter here: a column marked `display: restricted` only
omits that column. It does not authorize a Reader, filter other records,
or protect aggregates in a shared store. The host’s callback is trusted
R code; do not expose it, filesystem access, or an R evaluator to the
model.

## Pin a tool without freezing permission

The tool exposes only a record ID. It obtains its complete JSON result
and receipt from
[`graft_tools()`](https://jameshwade.github.io/graft/reference/graft_tools.md)
after reopening the authorized store at the pinned boundary. Revoking
access after construction prevents the next call.

``` r

tool <- example$reader_record_tool(alice, locations$alice$snapshot)
value <- jsonlite::fromJSON(tool("knowledge:preference"))
value$result$record$body
#> [1] "alice Prefer short reading sessions in the morning; this is a preference, not source evidence."
identical(value$receipt$store$id, locations$alice$store_id)
#> [1] TRUE
grants$alice <- NULL
unavailable(\() tool("knowledge:preference"))
#> [1] "Accepted knowledge is unavailable."
bob(\(store) graft_get(store, "knowledge:preference"))$record$body
#> [1] "bob Prefer short reading sessions in the morning; this is a preference, not source evidence."
```

The same callback rejects a changed grant revision during a read,
including a revoke/regrant cycle. Content already delivered to a model
or client remains a host lifecycle concern: cancel affected runs and
discard their reusable context. Permanent erasure and backup restore
remain separate work in
[\#48](https://github.com/JamesHWade/graft/issues/48).

## Reconnect with a complete basis

Persist the [complete selected
basis](https://jameshwade.github.io/graft/articles/reuse-basis.md), then
reconstruct the Reader’s access from trusted host state in the new
session or worker. The checkpoint contains no locator or credentials. A
basis from another store fails even when its selected record ID exists
locally.

``` r

grants$alice <- "alice-grant-2"
sys.source(system.file("examples/reuse-basis.R", package = "graft"), example)
basis <- alice(\(store) example$capture_reuse_basis(
  store,
  "knowledge:preference",
  data.frame(outcome = character(), dependency = character())
))
checkpoint <- file.path(directory, "basis.rds")
saveRDS(basis, checkpoint)
restored <- readRDS(checkpoint)
reconnected <- bind("alice")
reconnected(\(store) example$read_reuse_basis(store, restored, \(ids) TRUE))
#> $`knowledge:preference`
#> $`knowledge:preference`$id
#> [1] "knowledge:preference"
#> 
#> $`knowledge:preference`$kind
#> [1] "preference"
#> 
#> $`knowledge:preference`$purpose
#> [1] "reading selection"
#> 
#> $`knowledge:preference`$body
#> [1] "alice Prefer short reading sessions in the morning; this is a preference, not source evidence."
#> 
#> $`knowledge:preference`$lifecycle
#> [1] "active"
#> 
#> $`knowledge:preference`$tags
#> [1] "reading"
unavailable(\() bob(\(store) example$read_reuse_basis(store, restored, \(ids) TRUE)))
#> [1] "Accepted knowledge is unavailable."
```

Here the inner callback permits the complete selection because the outer
access boundary already authorizes this Reader’s store. A product must
additionally apply its current consultation-eligibility policy. Package
tests repeat the rebind in a separate R process, with all writer
connections closed first.

The example proves isolated Graft reads and host tool composition. It
does not establish durable hosting, concurrent writer access, Rill’s
Document hydration, or permanent Forget. Those gates remain explicit in
[\#51](https://github.com/JamesHWade/graft/issues/51) and the access
proposal.
