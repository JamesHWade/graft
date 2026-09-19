# Preserve an exact artifact selection

Retain explicit roots and their complete dependency closure as an
immutable selection. Selection records content, not approval, permission
or factual truth.

## Usage

``` r
graft_artifact_select(
  store,
  roots,
  max_artifacts = 1000L,
  max_metadata_bytes = 1024^2
)

graft_artifact_read_selection(
  store,
  selection,
  max_artifacts = 1000L,
  max_metadata_bytes = 1024^2
)
```

## Arguments

- store:

  A handle returned by
  [`graft_artifact_store()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md)
  or
  [`graft_artifact_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_artifact_store_postgres.md).

- roots:

  Nonempty list of exact artifact references returned by
  [`graft_artifact_save()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md).
  Duplicate roots are removed, retaining first order.

- max_artifacts:

  Maximum number of distinct references traversed. Each traversal also
  limits the sum of payload sizes to the store's `max_bytes`.

- max_metadata_bytes:

  Maximum encoded selection metadata bytes to save or read, a positive
  whole number. Defaults to 1 MiB (`1024^2`), independently of artifact
  count and payload bounds. Increase it for many long references and
  supply the same or a larger limit when reading that selection.

- selection:

  Selection digest returned by `graft_artifact_select()`.

## Value

`graft_artifact_select()` returns an immutable SHA-256 selection digest.
`graft_artifact_read_selection()` returns `id`, `roots` and `artifacts`,
where `artifacts` contains the complete ordered list of exact dependency
references.

## Details

Save dependencies with
`graft_artifact_save(dependencies = list(ref, ...))`. Dependencies are
exact references, not latest pointers or inferred relations. Dictionary
and vocabulary releases may be stored as opaque artifacts and pinned
alongside evidence. Graft does not evaluate their expressions or infer
ontology relationships. Direct dependency and root order are
significant; duplicates retain their first occurrence. Closure order is
breadth-first.

Both selection functions verify every selected payload. Reads
independently recompute the dependency closure and reject altered or
incomplete selections. The returned references can be resolved with
[`graft_artifact_read()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md).
Corrections do not change an earlier selection. Applications separately
decide whether a selection may be consulted for a purpose, and enforce
access. Storage limits and publication guarantees are those of
[`graft_artifact_store()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md).

## Examples

``` r
path <- tempfile("artifacts-")
store <- graft_artifact_store(path, create = TRUE)
source <- graft_artifact_save(store, "source", charToRaw("Evidence"),
"text/plain")
report <- graft_artifact_save(
  store, "report", charToRaw("Interpretation"), "text/plain",
  dependencies = list(source)
)
selection <- graft_artifact_select(store, list(report))
graft_artifact_read_selection(store, selection)$artifacts
#> [[1]]
#> [[1]]$id
#> [1] "report"
#> 
#> [[1]]$revision
#> [1] "ff852b045b8c2ccb78f61f2a17c162ecfb0d223d4ac7978e6d1361fb23de3da5"
#> 
#> 
#> [[2]]
#> [[2]]$id
#> [1] "source"
#> 
#> [[2]]$revision
#> [1] "49e0b2d60b68d6a2b1588879a19e872fbaa41b9a9ca65840248643f21737fbc2"
#> 
#> 
unlink(path, recursive = TRUE)
```
