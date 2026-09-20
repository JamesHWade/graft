# Back up and restore an artifact store

A Graft backup retains the complete logical artifact store: payloads,
revisions, selections, and every historical decision. It also includes
valid orphan content. If the application has approved exclusions, use a
[replacement
plan](https://jameshwade.github.io/graft/articles/artifact-recovery.md)
first. Neither operation changes the source.

The backup directory contains a canonical `bundle.json` descriptor and
an `objects/` store. It is closed only after every listed object has
been copied and verified. Closure does not promise filesystem flushes, a
completed PostgreSQL transaction, or permission to serve the contents.

## Retain the identity separately

The application supplies an opaque scope and generation. They may
identify an authenticated Reader’s artifact generation, but Graft does
not interpret them or authenticate the Reader. Store the returned
receipt in the application’s independent registry, along with the
authority needed to decide whether the generation remains eligible for
restore.

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
complete manifest digest. It records identity; it is not a signature or
authorization token. Do not obtain `expected` by reading the bundle
being restored. Doing so would let the bundle choose its own expected
identity. Keep both bundles and receipts private; artifact metadata and
even linkable digests can disclose sensitive information.

## Verify before restoring

An application first reads its current independent registry and checks
that the requested generation is eligible for the authenticated caller.
It then supplies the stored receipt to verification or restore. This
synthetic example keeps the receipt in memory and does not implement a
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
missing dependencies, and checksum mismatches. It compares every receipt
field and inventories the complete store. Restore runs this check before
writing target objects. It requires an empty target, then verifies the
bundle again and the complete restored image before returning its
manifest.

Caller arguments bound object count, total stored bytes, selection and
decision metadata, and descriptor size. The descriptor defaults to at
most 4 MiB; the store defaults to 10,000 objects and 64 MiB total.
Payload and revision limits come from the source or target store handle.
Standalone verification also exposes `max_bytes` and
`max_revision_bytes`. The bundle cannot supply these bounds. Enumerating
a local directory is not itself a streaming bounded operation.

A receipt from another scope or generation cannot certify this bundle,
even if the artifact bytes are identical. An old bundle and its matching
old receipt remain mechanically restorable. The application’s
independent registry must deny retired generations, including after
loading an old database backup. A bundle checksum cannot tell Graft that
the registry was rolled back.

## Recover an interrupted operation

Before starting, register the backup destination and its staging parent
with the application. The destination parent must already exist, and
paths must not contain `..` parent-traversal components. Graft creates a
sibling staging directory. It renames that directory to the absent
destination only after verifying the complete image. It refuses to
overwrite an existing destination and cleans up its own staging
directory after ordinary errors. Process termination can leave staging
behind; the application must inventory and dispose of it separately.
Register the restore target before writing to it.

Fence writers and keep the directories trusted throughout the operation.
Place a backup outside the source store and a restore target outside the
bundle. Repeated verification does not create a concurrent filesystem
snapshot. Do not expose a partially restored target. After a failure,
quarantine it and retry with a fresh empty target. Graft never deletes
existing destinations or source stores.

With PostgreSQL, use an application-owned transaction and a consistent
order for scope locks. A backup can capture rows visible in that
transaction before commit, so its receipt does not prove that the source
transaction committed. A successful restore remains pending until the
target transaction commits. Verify a committed, reopened candidate
before publication. Filesystem and database operations do not form a
distributed transaction.

## Remaining recovery work

Closed bundle verification covers one step of the protocol. Durable
independent generation retirement, write fencing, atomic publication,
registry crash recovery, and deployment-specific retention and disposal
remain tracked in [Graft
\#86](https://github.com/JamesHWade/graft/issues/86) and [Rill
\#106](https://github.com/JamesHWade/rill/issues/106). The [Forget
rollout gate](https://github.com/JamesHWade/graft/issues/48) remains
open. These synthetic mechanics do not prove physical secure erasure or
production recovery after power loss.
