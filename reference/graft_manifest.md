# Inventory a complete artifact store

Enumerate and verify every committed artifact object in a local or
transaction-scoped PostgreSQL store. The returned manifest is a
deterministic digest of the stored object keys, sizes and bytes. The
marker identifying the store format is checked but is not included in
the manifest object list.

## Usage

``` r
graft_manifest(
  store,
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2
)
```

## Arguments

- store:

  A handle returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- max_objects:

  Maximum number of committed artifact objects to inspect. The store
  marker is not counted.

- max_total_bytes:

  Maximum total bytes across committed artifact objects. The store
  marker is not counted.

- max_metadata_bytes:

  Maximum bytes for one selection or decision object and the aggregate
  bytes of one decision stream. Revision reads use the store handle's
  max_revision_bytes bound.

## Value

A list with format, id and ordered objects. Each object has kind, key,
size and the SHA-256 digest of its exact stored bytes.

## Details

This is a strict, bounded inspection of a closed candidate. Unknown
object kinds, unexpected paths, staging files, symbolic links,
nonregular files, malformed metadata, missing dependencies, corrupt
bytes and incomplete decision streams are rejected. Valid content
objects that are not referenced by a revision are retained in the
inventory so a replacement planner can omit them explicitly.

The operation does not quiesce writers, remove source objects, authorize
access, interpret a host Forget decision, or admit a generation for
service. Hosts must quiesce the source and perform their own publication
and restore checks around this point-in-time inspection.
