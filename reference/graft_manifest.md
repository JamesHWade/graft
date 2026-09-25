# Inventory a complete artifact store

Enumerate and verify every committed artifact object in a local or
transaction-scoped PostgreSQL store. The returned manifest is a
deterministic digest over the stored object keys, sizes, and bytes. The
function checks the store-format marker but excludes it from the
manifest's object list.

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

The function performs a strict, bounded inspection of a closed
candidate. Unknown object kinds, unexpected paths, staging files,
symbolic links, nonregular files, malformed metadata, missing
dependencies, corrupt bytes, and incomplete decision streams are
rejected. Valid content objects that are not referenced by a revision
are retained in the inventory so a replacement planner can omit them
explicitly.

A local store's lock is held exclusively for the whole inventory, so
writers in other processes wait rather than change the store midway; see
[`graft_with_store_lock()`](https://jameshwade.github.io/graft/reference/graft_with_store_lock.md).
A store this process cannot write is inventoried without the lock, so a
writer under another account does not wait. The operation does not
remove source objects, authorize access, interpret a host Forget
decision, or admit a generation for service. Hosts perform their own
publication and restore checks around this point-in-time inspection.
