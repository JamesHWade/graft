---
status: proposed
---

# Isolate Reader knowledge in separate stores

For the first Rill integration, use one Graft store per Reader behind a
Rill-owned authorization boundary. This is the proposed host design and offline
contract for [Graft #47](https://github.com/JamesHWade/graft/issues/47), not a
deployed Rill feature or a new Graft access API. The executable example is
`inst/examples/reader-access.R`; `tests/testthat/test-reader-access.R` exercises
real stores, receipts, an ellmer loop, and a fresh R process.

## Why this boundary

Graft can read an accepted boundary, but it does not authenticate Readers.
An `owner_binding` column, a class filter, `display: restricted`, or a snapshot
does not authorize access. Filtering one query in a shared store would leave
history, changes, relationships, dictionary metadata, calculations, counts,
and receipt resolution as independent disclosure paths.

| Option | Consequence | Decision |
| --- | --- | --- |
| Separate store per Reader | Existing public reads see only that Reader's accepted records. Rill must bind storage, execution, and source access to the authenticated Reader. | Use for the first proof and propose for the initial host integration. |
| Shared store with a scoped read capability | Every direct read, definition, dependency, diagnostic, receipt, and historical boundary must enforce the same scope before selection and aggregation. DuckDB file access is not a Reader authorization boundary. | Defer until a real consumer demonstrates that separate stores are insufficient. |
| A shared store filtered by `owner_id` | Unfiltered APIs and derived results can reveal private data or its existence. | Reject. |

No generic scope class, new schema language, or implicit Reader column is
required by this proof. Graft continues to own accepted records and exact
boundaries; Rill owns Reader identity, admission, source access, task purpose,
and consultation eligibility.

## Host and storage constraints

Rill's [runtime ADR](https://github.com/JamesHWade/rill/blob/main/docs/adr/0001-hosted-rill-runtime-and-identity.md)
and [Agent Run ADR](https://github.com/JamesHWade/rill/blob/main/docs/adr/0005-keep-agent-runs-durable-and-execution-process-local.md)
describe one web process, PostgreSQL product records, process-local execution,
and a separate poller. The deployment guide does not establish a durable Graft
disk or a knowledge-store connection lifecycle.

A [Render persistent disk](https://render.com/docs/disks) would require a
storage/deployment decision: files survive only under its mount; the disk is
attached to one service instance and is unavailable to the separate cron
service. A disk-backed service also loses zero-downtime deployment. The proof
uses temporary local files and makes no claim about deployed persistence.

[DuckDB's embedded concurrency contract](https://duckdb.org/docs/current/connect/concurrency)
supports a writing process or multiple read-only processes. Rill must coordinate
writers with external readers; reopening a file does not establish safe
concurrent access. The example closes its writer before a worker opens a
read-only connection. It does not copy an active database or pass connections
between processes. A future service or remote backend needs separate evidence.

The host must provision stores on durable storage, record their UUIDs in its
trusted Reader mapping, serialize incompatible access, and verify backup and
restore before rollout. A missing or mismatched store fails closed; opening a
new empty store is not recovery.

## Authorization and reference resolution

Only verified host identity selects a Reader. Neither model arguments nor
serialized reuse bases select a Reader, filesystem path, schema, credential,
or live database handle. A trusted host registry maps that Reader to a store
path, schema, and expected store UUID. The example verifies the UUID after a
read-only open, then resolves any snapshot against that store.

Before lookup, the host supplies a nonempty current grant revision. After
reading, the revision must still match. Revocation or a revoke/regrant cycle
changes that revision and prevents release of the result. The production host
must obtain it from its current authorization state, not a stale session copy.
The example's in-memory grants are synthetic policy inputs, not authentication.

The read callback is trusted application code. It must return collected values,
not a store, view, closure, or connection. The model receives only the declared
record tool; it cannot supply a callback, Reader, SQL, path, or arbitrary R code.
Separate files do not sandbox hostile code running under the host's OS account.

The tool checks authorization at construction and again on every invocation.
It uses a pinned `graft_get()` result and its complete canonical receipt. A
foreign snapshot is rejected even when the other store has the same schema
and record ID. Receipt identities identify evidence; possession of one grants
no access. Graft's verification label still assesses the recorded evidence path,
not Reader authentication or factual accuracy.

Unknown records, foreign records, invalid references, revoked access, and
storage failures produce the same content-free boundary error, without an
underlying exception attached. This avoids an existence oracle or leaking a
private path through an error. Rill should record a separate content-free
operational failure category. Equal response timing is not established here.

## Sources, caches, and lifecycle

Each Reader's private capture keeps its own logical Document revision and
provenance, including when the original URL or bytes match another Reader's
capture. A shared URL never resolves a foreign record. Cross-store foreign
keys fail validation; an authorized handoff must explicitly import an allowed
copy and preserve its source revision under the receiving host's ownership.
Rill still authorizes hydration of external Documents under
[its Library ADR](https://github.com/JamesHWade/rill/blob/main/docs/adr/0007-separate-shared-sources-from-reader-libraries.md).
This example's synthetic source rows do not prove that Rill hydration path.

The recipe caches neither results nor connections. Reconnects and workers
reconstruct access from trusted host state and recheck authorization before
reading a saved basis. A production cache must include Reader, store UUID,
accepted boundary, selection, and current grant revision in its ownership
contract, and check access on a cache hit. Cross-Reader cache reuse is forbidden.

Revocation stops subsequent reads; it cannot retract content already returned
to a model, Conversation, or client. The host must cancel affected runs and
discard their reusable context before proceeding. Archive and consultation
eligibility follow the separate reuse contract. Permanent Forget must also
remove derived copies and prevent restoration from backups; it remains gated
by [#48](https://github.com/JamesHWade/graft/issues/48). No erasure is implemented
by this access recipe.

## Bounded implementation handoff

[Graft #51](https://github.com/JamesHWade/graft/issues/51) and
[Rill #7](https://github.com/JamesHWade/rill/issues/7) own the product follow-through:

1. Resolve verified identity to a Reader and a durable store binding. Test
   admission changes, missing stores, substituted UUIDs, and reconnects using
   Rill's actual store and Agent Run objects.
2. Map accepted Reading Artifacts and Reader Memory with exact private
   Document revisions. Test guessed IDs, cross-Reader relationships and source
   hydration, including equal URLs and bytes.
3. Bind the narrow tool to each run, enforce current access on invocation and
   delivery, cancel affected runs on revocation, and prohibit shared result or
   conversation caches. Recheck task eligibility separately.
4. Establish durable storage, connection ownership, recoverable backup, and
   permanent Forget across authoritative and derived copies under #48.

The Graft-side proof can be reviewed independently. Rill integration and its
production access/erasure gates remain open until these host tests pass.
