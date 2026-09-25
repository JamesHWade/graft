# Plan and build a bounded artifact-store replacement

Compute an operational replacement plan after forgetting exact artifact
revisions, complete decision streams, or both, or with nothing to forget
to clean up unreferenced content a failed save left behind. The plan
preserves every revision that is neither forgotten nor a transitive
reverse dependent, which is a revision that depends directly or
indirectly on a forgotten revision. It then retains only content
referenced by those revisions. It removes a selection when any exact
reference in it is removed. It removes a whole decision stream when a
historical record names a removed selection or when the stream is
explicitly requested.

## Usage

``` r
graft_plan_replacement(
  store,
  forget = list(),
  forget_streams = character(),
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2
)

graft_replace(source, target, plan)
```

## Arguments

- store:

  A handle returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- forget:

  A list of exact artifact references returned by
  [`graft_save()`](https://jameshwade.github.io/graft/reference/graft_save.md).
  With `forget_streams` also empty, the plan forgets nothing and only
  leaves out unreferenced content.

- forget_streams:

  Character vector of complete decision stream names to remove. The
  names must already exist in the source inventory.

- max_objects:

  Maximum number of inventoried objects.

- max_total_bytes:

  Maximum total bytes inventoried across objects.

- max_metadata_bytes:

  Maximum aggregate encoded bytes allowed for selection metadata and
  complete decision journals. Revision metadata uses the source and
  target store `max_revision_bytes` limits.

- source:

  A source artifact-store handle for a replacement operation.

- target:

  An empty artifact-store handle to receive the replacement.

- plan:

  A plan returned by `graft_plan_replacement()`. The plan contains
  operational data, not an authorization or approval record.

## Value

`graft_plan_replacement()` returns a list with format
`graft-artifact-replacement/1`, source and target manifests, canonical
Forget roots and streams, limits, and removed artifact, selection, and
stream identities. `graft_replace()` returns the verified target
manifest only after the source and target have been checked again.

## Details

The bounded inventory must enumerate every artifact revision, selection,
decision record, and content object in the source store. Opaque payload
bytes are never scanned for identifiers, private fields, reasons, or
other erasure roots. The host must supply all additional roots and
streams required by its Forget policy, including copies outside this
artifact store.

Planning does not authorize Forget and does not delete anything.
Replacement copies verified objects into a new empty store. The source's
objects are never changed; a writable source may gain its lock file
under `locks/`. A copy or verification failure can leave a partial
target. The host must quarantine and discard that target, then rebuild a
new empty target. Planning and replacement hold the local source's and
target's store locks exclusively, so writers from other processes wait
until they finish. A host that switches to the replacement should hold
the source's lock across the plan, the copy, and the switch; see
[`graft_with_store_lock()`](https://jameshwade.github.io/graft/reference/graft_with_store_lock.md).
PostgreSQL callers must hold the host transaction and scope lock for the
operation.

## Examples

``` r
path <- tempfile("artifacts-")
replacement_path <- tempfile("replacement-")
store <- graft_store(path, create = TRUE)
target <- graft_store(replacement_path, create = TRUE)
ref <- graft_save(store, "Evidence", "report")
plan <- graft_plan_replacement(store, list(ref))
graft_replace(store, target, plan)
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
