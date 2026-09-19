# Getting started

Graft retains exact bytes, dependencies, host decisions, and shared
vocabulary. Use `graft_artifact_store(path, create = TRUE)` once, then
reopen the same path in later processes with
`graft_artifact_store(path)`.

``` r

library(graft)
path <- tempfile("graft-example-")
store <- graft_artifact_store(path, create = TRUE)
evidence <- graft_artifact_save(store, "evidence", charToRaw("Observed: 82%"), "text/plain")
report <- graft_artifact_save(store, "report", charToRaw("Pilot recovery was 82%."),
                             "text/plain", dependencies = list(evidence))
selection <- graft_artifact_select(store, list(report))
reopened <- graft_artifact_store(path)
length(graft_artifact_read_selection(reopened, selection)$artifacts)
```

    ## [1] 2

``` r

rawToChar(graft_artifact_read(reopened, report)$bytes)
```

    ## [1] "Pilot recovery was 82%."

``` r

unlink(path, recursive = TRUE)
```

Every read verifies exact content. Selections retain dependencies
transitively; replacing a source file cannot silently change an old
report’s evidence.

Continue with [persistent
artifacts](https://jameshwade.github.io/graft/articles/persistent-artifacts.md)
for host decisions and [shared
vocabulary](https://jameshwade.github.io/graft/articles/shared-vocabulary.md)
for concepts across workflows.
