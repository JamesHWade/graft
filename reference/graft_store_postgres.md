# Open a transaction-scoped PostgreSQL artifact store

Use the immutable artifact, selection, decision, and vocabulary APIs
with PostgreSQL persistence. The host application controls the
connection, transaction, authentication, and scope.

## Usage

``` r
graft_store_postgres(
  connection,
  scope,
  create = FALSE,
  max_bytes = 64 * 1024^2,
  max_revision_bytes = 1024^2
)
```

## Arguments

- connection:

  An open `RPostgres::PqConnection` in an active transaction started
  through DBI at PostgreSQL's `READ COMMITTED` isolation level. Pools
  must supply a checked-out connection.

- scope:

  Isolation key selected by the host application, at most 1024 UTF-8
  bytes. Every object read and write is restricted to this scope. This
  key is not an authentication credential; never let an agent choose it.

- create:

  Whether to ensure the storage table and scope exist. Defaults to
  `FALSE`. Unlike local directory creation, `TRUE` can reopen an
  existing scope.

- max_bytes:

  Maximum payload bytes per artifact to save or read in this handle.
  Dependency traversal also applies this limit to aggregate payloads.

- max_revision_bytes:

  Maximum encoded metadata bytes per revision to save or read through
  this handle, a positive whole number. Defaults to 1 MiB (`1024^2`),
  independently of payload and dependency-count bounds. Increase it for
  large dependency lists, including when reopening the store.

## Value

A Graft artifact store handle bound to the supplied connection and
scope. The host remains responsible for closing the connection.

## Details

The current PostgreSQL schema contains `graft_artifact_objects`, owned
by Graft. Scope, object kind, and object key form its primary key.
Scopes never share retained rows, even when payloads have identical
digests. Artifact formats and identities are identical to the local file
implementation.

A transaction-level advisory lock serializes operations within one
scope. The host commits only after its complete operation and approval
checks succeed. Rollback removes all changes made in the transaction. A
returned reference or decision is not durable until the host commits
successfully. Use a short transaction and rebind the authenticated scope
in every worker. Handles contain a live connection and must not be
serialized or sent to models. After the transaction ends, artifact
operations require another active transaction and acquire the scope lock
again.

The scope isolates data between scopes chosen by the host application.
It does not isolate database roles or arbitrary code: the database role
can access other scopes directly. The host must authorize every
operation, including historical inspection, and keep connections away
from untrusted code. PostgreSQL controls durability configuration and
backups. This interface supplies no permanent Forget or backup admission
protocol.

## Examples

``` r
if (FALSE) { # identical(Sys.getenv("GRAFT_TEST_POSTGRES"), "true")
connection <- DBI::dbConnect(RPostgres::Postgres())
DBI::dbWithTransaction(connection, {
  store <- graft_store_postgres(connection, "example", create = TRUE)
  ref <- graft_save(store, "Hello", "note")
})
DBI::dbDisconnect(connection)
}
```
