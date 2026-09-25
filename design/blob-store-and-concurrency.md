# Blob storage and concurrent processes

September 24, 2026. Written for Crucible's kept artifacts, which are the first
records in graft to need bytes (plots, HTML, Word files) and the first to be
written from several processes (Posit Connect runs several R processes per
app).

## Blobs

**A contract opts in by declaring a `graft_blob` table** with:
- a string `id` primary key;
- a required string `media_type`;
- a required numeric `size_bytes`.

Other tables reference a blob with an ordinary `foreign_key` column, so the
reference rules graft already has decide whether a reference resolves.

The data-dict spec rejects unknown column keys, so a per-column marker such as
`graft: {blob: true}` would not validate. A reserved table name keeps the
contract valid data-dict while making the opt-in explicit and visible in the
contract itself, not in a call to `graft_open()`.

**`id` is `sha256:<hex>` of the bytes**, the same digest form graft uses for
content digests. Bytes live beside the store in `<stem>.blobs/<hex[1:2]>/<hex>`,
mirroring the managed OKF path (`<stem>.okf`). An in-memory store uses a
temporary directory for the life of the process.

**Flow.** `graft_blob(store, x, media_type)` writes the bytes and returns the
`graft_blob` row. It writes to a staging file in the target directory and then
renames, which is atomic on one file system, and skips the write when verified
bytes with that name already exist. The caller puts that row in the batch
beside the records that reference it, so bytes and references go through the
same `graft_plan()` review and `graft_commit()` transaction.

Planning adds these issues, each with condition class `graft_blob_error`:

| Rule | Meaning |
|---|---|
| `blob_id` | the id is not `sha256:<64 hex>` |
| `blob_missing` | no bytes under that name |
| `blob_size` | the byte count differs from `size_bytes` |
| `blob_digest` | the bytes do not hash to the name |
| `blob_immutable` | the batch would update a committed blob |

`graft_commit()` checks the bytes again before its transaction. A file removed
or altered between plan and commit aborts the commit and writes nothing.

`graft_blob_read()` returns bytes only for a committed `graft_blob` record, and
only after their size and digest match it.

**Not done:**
- Garbage collection of staged bytes that were never committed.
- Copying blobs when a store file is moved: the directory moves with the store
  by name only.
- Including blobs in the OKF working tree.

## Concurrent processes

DuckDB lets one process hold a database file at a time. The lock is taken when
the file is opened, and **it blocks read-only opens too**. This was checked on
September 24, 2026 with duckdb R 1.4: a second process opening read-only gets
`Could not set lock on file ... Conflicting lock is held`.

`graft_open()` keeps its connection until `graft_close()`, so a Shiny session
holding a store open blocks every other process on Connect, including ones that
only want to read.

What this change does: a lock conflict at open now signals `graft_store_busy`
(also a `graft_backend_error`), with the store path and advice to open per
operation and retry. It is tested with a second R process holding the file.

Options for a multi-process host, not yet chosen:

1. **Open per operation.** Open, plan or read, commit, and close within one
   call, retrying on `graft_store_busy` with a short backoff. This costs one
   store verification per open. Commits in Crucible are rare (a person
   pressing Keep), but reads, such as listing kept artifacts on Home, are
   frequent. They may need a cached projection, or reads from an exported
   snapshot. The smallest change; the first thing to try.
2. **A single writer process.** Other processes submit plans to one process
   that holds the store, for example the scheduled jobs runner or a small
   plumber service, and read from its exports. Robust, but it adds a service
   and its latency to Keep.
3. **A pins or dowcrud backend.** Keep the ledger as versioned pins. That fits
   how Crucible's shared layer already works on Connect, but graft's backend
   is DuckDB-specific throughout (projections, set-based commits), so this is
   a large change.

**Needs a Connect test before choosing:**
- lock and retry behaviour under several processes;
- whether the file system under the data directory (possibly a network share) honours
  DuckDB's file locks at all. If it does not, option 1 is unsafe and option 2
  is required.
