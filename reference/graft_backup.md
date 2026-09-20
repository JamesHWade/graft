# Create a closed artifact-store backup

Copy a complete, verified artifact store into a versioned local backup
bundle. The bundle contains a canonical descriptor and an exact image of
the local artifact store. The receipt is small enough for an application
to retain separately from the bundle.

## Usage

``` r
graft_backup(
  store,
  path,
  scope,
  generation,
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2,
  max_bundle_metadata_bytes = 4 * 1024^2
)
```

## Arguments

- store:

  A handle returned by
  [`graft_store()`](https://jameshwade.github.io/graft/reference/graft_store.md)
  or
  [`graft_store_postgres()`](https://jameshwade.github.io/graft/reference/graft_store_postgres.md).

- path:

  An absent local directory path for the backup bundle. Existing paths,
  including dangling symbolic links, are rejected. The parent directory
  must already exist; paths must not contain `..` components.

- scope:

  An opaque, nonempty identifier that the host application associates
  with this scope.

- generation:

  An opaque, nonempty identifier that the host application associates
  with this generation.

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

A receipt containing the backup format, descriptor digest, scope,
generation, and complete manifest digest.

## Details

The source is never changed. A backup includes valid orphan content and
all historical decision records. Local source stores require a trusted
directory with a single writer and no concurrent writes. PostgreSQL
callers retain transaction and commit ownership; a successful receipt
does not prove that a transaction has committed. The destination is
built in a sibling staging directory and is renamed only after the
complete image is verified. On an ordinary failure, the operation
removes its staging directory. An interrupted process can leave staging
behind for host inventory and disposal. The destination's parent must
already be a readable directory, and paths cannot contain parent
traversal components.

Scope and generation associate the image with host records. They do not
authenticate a caller, grant access, or establish registry freshness.
