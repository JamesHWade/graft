# Restore a verified backup into an empty artifact store

Verify a closed backup, then copy its exact objects into an empty local
or transaction-scoped PostgreSQL artifact store. Verify the target again
before returning its manifest.

## Usage

``` r
graft_restore(
  path,
  target,
  expected,
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2,
  max_bundle_metadata_bytes = 4 * 1024^2
)
```

## Arguments

- path:

  A local backup bundle path without `..` components.

- target:

  An empty handle returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- expected:

  The independently retained receipt expected for this bundle.

- max_objects:

  Maximum number of stored artifact objects to inspect.

- max_total_bytes:

  Maximum total bytes across stored artifact objects.

- max_metadata_bytes:

  Maximum bytes for one selection or decision object and the aggregate
  bytes of one decision stream.

- max_bundle_metadata_bytes:

  Maximum bytes for the `bundle.json` descriptor.

## Value

The complete manifest of the verified restored target.

## Details

The bundle is verified before any target object is written, then
verified again after copying. The target must be empty and outside the
bundle. A failed copy can leave a partial target. Quarantine it and
retry in a fresh empty target. The source bundle is never changed.
PostgreSQL callers own the surrounding transaction and commit.
