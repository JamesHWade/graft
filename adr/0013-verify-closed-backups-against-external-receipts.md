# Verify closed backups against external receipts

Status: accepted for closed artifact bundle mechanics. Publication, durable
independent journal recovery, and permanent Forget remain gated by #86 and #48.

## Context

ADR 0012 verifies a logical replacement but does not retain a portable complete
image. A bundle needs an explicit format, complete checksums, bounded validation,
and an association with the host's scope and generation. Content metadata cannot
supply its own authority to restore a retired generation.

## Decision

Consumer contract 3.2 exposes `graft_artifact_backup()`,
`graft_artifact_backup_verify()`, and `graft_artifact_restore()`. The bundle format
is `graft-artifact-backup/1` and its local directory contains exactly:

- `bundle.json`: canonical JSON containing format, opaque scope and generation,
  and the complete artifact manifest.
- `objects/`: a local artifact store with its format marker and exact objects.

The separate receipt contains format, descriptor SHA-256 digest, scope,
generation, and manifest digest. Hosts retain it independently. Verification
requires the expected receipt, validates the descriptor and complete image, and
compares every identity field. Unknown fields, duplicate entries, noncanonical
bytes, unsupported formats, links, nonregular objects, and incomplete histories
are rejected. Input limits come from callers, never the bundle. Descriptor size
is bounded before JSON parsing; object inventory and bytes use recovery limits.
Local directory enumeration still precedes the inventory count check.

A full backup preserves valid orphan content and every decision record. It does
not apply exclusions. Use the replacement planner to choose survivors, then back
up that verified replacement. Scope and generation associate contents with host
records; they do not authenticate the caller, grant access, or establish registry
freshness. Valid old bundles remain mechanically restorable with their matching
old receipts. The independent registry must deny those retired generations.

## Failure and publication boundary

The destination parent must already exist; paths containing `..` components are
rejected before lexical normalization can change their meaning across symlinks.
Backup writes to a sibling staging
directory outside the source store, verifies
it, and renames it to a previously absent destination. It never overwrites an
existing destination. Ordinary errors clean up the operation's own staging;
process termination can leave it behind. Hosts register destinations and staging
parents before writing and track disposal separately. Trusted quiescent local
storage and one writer remain requirements; no fsync or power-loss claim is made.

Restore validates before writing, requires an empty target outside the bundle,
copies exact bytes, and verifies both images again. Failed targets remain
quarantined and require a fresh empty retry. Neither backup nor restore deletes
source content, publishes a generation, or changes application acceptance.

PostgreSQL scope operations remain inside host-owned transactions. A bundle made
from uncommitted rows can survive source rollback: it proves those captured
bytes, not their database commitment. Restored rows also require a successful
host commit. A host verifies the committed reopened candidate and backup before
publication. Cross-backend copy is not a distributed transaction.

## Consequences

The format reuses exact artifact identities and complete recovery validation
without introducing archive extraction, R object deserialization, a new database
schema, or application-specific Reader records. The receipt is deliberately small
enough for an independent registry, while the descriptor carries the full image
inventory. Both remain private operational data.

The remaining protocol needs an independently durable monotonic journal, writer
fencing, candidate registration, atomic generation publication, restart handling,
and deployment-specific key and copy disposal. Checksums, directory renames,
transaction rollback tests, and restore denial do not establish physical erasure
or recovery from a lost or rolled-back registry.
