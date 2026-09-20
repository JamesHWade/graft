# Back up and restore an artifact store

A Graft backup retains a complete logical artifact store: payloads,
revisions, selections, and every historical decision. It includes valid
orphan content; use a [replacement
plan](https://jameshwade.github.io/graft/articles/artifact-recovery.md)
first when the host has approved exclusions. Neither operation changes
the source.

The backup is a directory containing a canonical `bundle.json`
descriptor and an `objects/` store. It is closed when every listed
object has been copied and verified. This does not promise filesystem
flushes, a completed PostgreSQL transaction, or permission to serve its
contents.

## Retain the identity separately

The application supplies an opaque scope and generation. These might
identify an authenticated Reader’s artifact generation, but Graft does
not interpret them or authenticate that Reader. Keep the returned
receipt in the application’s independent registry, with the authority
needed to decide whether it is still eligible for restore.

``` r

library(graft)
```

    ## 
    ## Attaching package: 'graft'

    ## The following object is masked from 'package:base':
    ## 
    ##     Recall

``` r

source_path <- tempfile("source-")
backup_path <- tempfile("backup-")
source <- graft_store(source_path, create = TRUE)
evidence <- graft_save(
  source, "Synthetic observation", id = "evidence", media_type = "text/plain"
)
report <- graft_save(
  source, "An interpretation", id = "report", media_type = "text/plain",
  dependencies = evidence
)
accepted <- graft_accept(
  source, report, stream = "report-review", key = "review-1", expected = NULL,
  actor = "synthetic-reviewer",
  reason = "Evidence inspected", purpose = "research"
)
receipt <- graft_backup(
  source, backup_path, scope = "synthetic-reader", generation = "generation-1"
)
receipt$format
```

    ## [1] "graft-artifact-backup/1"

``` r

receipt$scope
```

    ## [1] "synthetic-reader"

``` r

receipt$generation
```

    ## [1] "generation-1"

The receipt binds the exact descriptor digest, scope, generation, and
complete manifest digest. It is an identity record, not a signature or
authorization token. Do not obtain `expected` by reading the bundle
being restored: that would let the bundle choose its own expected
identity. Keep both bundles and receipts private; artifact metadata and
even linkable digests can disclose sensitive information.

## Verify before restoring

In an application, first read the current independent registry and check
that the requested generation is eligible for the authenticated caller.
Only then supply its stored receipt to verification or restore. This
synthetic example keeps the receipt in memory; it does not implement a
durable registry.

``` r

identical(graft_verify_backup(backup_path, expected = receipt), receipt)
```

    ## [1] TRUE

``` r

restore_path <- tempfile("restored-")
restored <- graft_store(restore_path, create = TRUE)
manifest <- graft_restore(backup_path, restored, expected = receipt)
identical(manifest$id, receipt$manifest)
```

    ## [1] TRUE

``` r

graft_read(restored, report)@data
```

    ## [1] "An interpretation"

``` r

identical(graft_history(restored, "report-review")[[1L]], accepted)
```

    ## [1] TRUE

Verification rejects unsupported formats, altered descriptors,
unexpected files, symbolic links, nonregular files, invalid histories,
missing dependencies, and checksum mismatches. It compares all receipt
fields and inventories the complete store. Restore performs this check
before writing any target objects, requires an empty target, and
verifies the bundle again and the complete restored image before
returning its manifest.

Object count, total stored bytes, selection and decision metadata, and
descriptor size are bounded by caller arguments. The descriptor defaults
to at most 4 MiB; the store defaults to 10,000 objects and 64 MiB total.
Payload and revision limits come from the source or target store handle;
standalone verification also exposes `max_bytes` and
`max_revision_bytes`. Bounds are never accepted from the bundle. Local
directory enumeration itself is not a streaming bounded operation.

A receipt from another scope or generation cannot certify this bundle,
even when the artifact bytes are identical. However, an old bundle and
its matching old receipt remain mechanically restorable. The
application’s independent registry must deny retired generations,
including when an old database backup is loaded. Graft cannot detect a
rolled-back registry from a bundle checksum.

## Recover an interrupted operation

Register the backup destination and its staging parent with the host
before starting. The destination parent must already exist, and paths
must not contain `..` parent-traversal components. Graft creates a
sibling staging directory and renames it to the absent destination only
after verifying the complete image. It refuses to overwrite an existing
destination and cleans up its own staging directory on ordinary errors.
Process termination can leave staging behind; the host inventories and
disposes of it separately. Register the restore target before writing as
well.

Keep writers fenced and directories trusted throughout the operation. A
backup must be outside the source store, and a restore target must be
outside the bundle. Repeated verification is not a concurrent filesystem
snapshot. Do not expose a partially restored target. After failure,
quarantine it and retry in a fresh empty target. Existing destinations
and source stores are never deleted.

For PostgreSQL, use a host-owned transaction and consistent scope lock
ordering. A backup can capture rows visible in that transaction before
they are committed; its receipt does not prove the source transaction
committed. A successful restore also remains pending until the target
transaction commits. Verify a committed, reopened candidate before
publication. Filesystem and database operations do not form a
distributed transaction.

## Remaining recovery work

Closed bundle verification supplies one step in the protocol. Durable
independent generation retirement, write fencing, atomic publication,
crash recovery of the registry, and deployment-specific retention and
disposal remain tracked in [Graft
\#86](https://github.com/JamesHWade/graft/issues/86) and [Rill
\#106](https://github.com/JamesHWade/rill/issues/106). The [Forget
rollout gate](https://github.com/JamesHWade/graft/issues/48) stays open.
These synthetic mechanics do not prove physical secure erasure or
production recovery after power loss.
