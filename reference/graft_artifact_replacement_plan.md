# Plan and build a bounded artifact-store replacement

Compute an operational replacement plan after forgetting exact artifact
revisions and/or complete decision streams. The plan preserves every
revision which is not a forgotten revision or a transitive reverse
dependent, then retains only content referenced by those revisions. A
selection is removed when any of its exact references is removed. A
whole decision stream is removed when any historical record names a
removed selection, or when the stream is explicitly requested.

## Usage

``` r
graft_artifact_replacement_plan(
  store,
  forget,
  forget_streams = character(),
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2
)

graft_artifact_replace(source, target, plan)
```

## Arguments

- store:

  A handle returned by
  [`graft_artifact_store()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md)
  or
  [`graft_artifact_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_artifact_store_postgres.md).

- forget:

  A list of exact artifact references returned by
  [`graft_artifact_save()`](https://jameshwade.github.io/graft/reference/graft_artifact_store.md).
  It may be empty when `forget_streams` is nonempty.

- forget_streams:

  Character vector of complete decision stream names to remove. The
  names must already exist in the source inventory.

- max_objects:

  Maximum number of inventoried objects.

- max_total_bytes:

  Maximum total bytes inventoried across objects.

- max_metadata_bytes:

  Maximum aggregate encoded bytes allowed while reading selection
  metadata and complete decision journals. Revision metadata uses the
  source and target store `max_revision_bytes` limits.

- source:

  A source artifact-store handle for a replacement operation.

- target:

  An empty artifact-store handle to receive the replacement.

- plan:

  A plan returned by `graft_artifact_replacement_plan()`. The plan is
  operational data; it is not an authorization or approval record.

## Value

`graft_artifact_replacement_plan()` returns a list with format
`graft-artifact-replacement/1`, source and target manifests, canonical
Forget roots and streams, limits, and removed artifact, selection, and
stream identities. `graft_artifact_replace()` returns the verified
target manifest only after the source and target have been checked
again.

## Details

The inventory is bounded and must enumerate every artifact revision,
selection, decision record, and content object in the source store.
Opaque payload bytes are never scanned for identifiers, private fields,
reasons, or other erasure roots. The host must supply all additional
roots and streams required by its Forget policy, including copies
outside this artifact store.

Planning does not authorize Forget and does not delete anything.
Replacement copies verified objects into a new empty store. The source
is never changed. A copy or verification failure can leave a partial
target; the host must quarantine and discard that target and rebuild a
new empty target. Local stores require quiesced single-writer access.
PostgreSQL callers must hold the host transaction and scope lock for the
operation.

## Examples

``` r
path <- tempfile("artifacts-")
replacement_path <- tempfile("replacement-")
store <- graft_artifact_store(path, create = TRUE)
target <- graft_artifact_store(replacement_path, create = TRUE)
ref <- graft_artifact_save(store, "report", charToRaw("Evidence"),
  "text/plain")
plan <- graft_artifact_replacement_plan(store, list(ref))
graft_artifact_replace(store, target, plan)
#> $format
#> [1] "graft-artifact-manifest/1"
#> 
#> $id
#> [1] "65487a4f587bee4eff00304a2896ebc69d66a5c64b28ceab5117da0bc324f155"
#> 
#> $objects
#> list()
#> 
unlink(path, recursive = TRUE)
unlink(replacement_path, recursive = TRUE)
```
