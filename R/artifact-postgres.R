#' Open a transaction-scoped PostgreSQL artifact store
#'
#' Use the immutable artifact, selection, decision, and vocabulary APIs with
#' PostgreSQL persistence. The host application controls the connection,
#' transaction, authentication, and scope.
#'
#' @param connection An open `RPostgres::PqConnection` in an active transaction
#'   started through DBI at PostgreSQL's `READ COMMITTED` isolation level.
#'   Pools must supply a checked-out connection.
#' @param scope Isolation key selected by the host application, at most 1024
#'   UTF-8 bytes. Every object read and write is restricted to this scope. This
#'   key is not an authentication credential; never let an agent choose it.
#' @param create Whether to ensure the storage table and scope exist. Defaults
#'   to `FALSE`.
#'   Unlike local directory creation, `TRUE` can reopen an existing scope.
#' @inheritParams graft_store
#'
#' @details
#' The current PostgreSQL schema contains `graft_artifact_objects`, owned by
#' Graft. Scope, object kind, and object key form its primary key. Scopes never
#' share retained rows, even when payloads have identical digests. Artifact
#' formats and identities are identical to the local file implementation.
#'
#' A transaction-level advisory lock serializes operations within one scope.
#' The host commits only after its complete operation and approval checks
#' succeed. Rollback removes all changes made in the transaction. A returned
#' reference or decision is not durable until the host commits successfully.
#' Use a short transaction and rebind the authenticated scope in every worker.
#' Handles contain a live connection and must not be serialized or sent to
#' models. After the transaction ends, artifact operations require another
#' active transaction and acquire the scope lock again.
#'
#' The scope isolates data between scopes chosen by the host application. It
#' does not isolate database roles or arbitrary code: the database role can
#' access other scopes directly. The host must authorize every operation,
#' including historical inspection, and keep connections away from untrusted
#' code.
#' PostgreSQL controls durability configuration and backups. This interface
#' supplies no permanent Forget or backup admission protocol.
#'
#' @returns A Graft artifact store handle bound to the supplied connection and
#'   scope. The host remains responsible for closing the connection.
#' @export
#' @examplesIf identical(Sys.getenv("GRAFT_TEST_POSTGRES"), "true")
#' connection <- DBI::dbConnect(RPostgres::Postgres())
#' DBI::dbWithTransaction(connection, {
#'   store <- graft_store_postgres(connection, "example", create = TRUE)
#'   ref <- graft_save(store, "Hello", "note")
#' })
#' DBI::dbDisconnect(connection)
graft_store_postgres <- function(
  connection,
  scope,
  create = FALSE,
  max_bytes = 64 * 1024^2,
  max_revision_bytes = 1024^2
) {
  if (
    !requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("RPostgres", quietly = TRUE)
  ) {
    artifact_abort("PostgreSQL stores require DBI and RPostgres.")
  }
  if (!inherits(connection, "PqConnection") || !DBI::dbIsValid(connection)) {
    artifact_abort("`connection` must be an open RPostgres connection.")
  }
  scope <- artifact_check_text(scope, "scope")
  if (!rlang::is_bool(create)) {
    artifact_abort("`create` must be TRUE or FALSE.")
  }
  artifact_check_limit(max_bytes, "max_bytes")
  artifact_check_limit(max_revision_bytes, "max_revision_bytes")
  artifact_postgres_lock(connection, scope)
  if (create && !DBI::dbExistsTable(connection, "graft_artifact_objects")) {
    artifact_postgres_query(
      connection,
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      params = list("graft:table")
    )
    DBI::dbExecute(
      connection,
      paste(
        "CREATE TABLE IF NOT EXISTS graft_artifact_objects (",
        "scope text NOT NULL, kind text NOT NULL, object_key text NOT NULL,",
        "payload bytea NOT NULL, PRIMARY KEY (scope, kind, object_key))"
      )
    )
  }
  store <- PostgresArtifactStore(
    connection = connection,
    scope = scope,
    max_bytes = max_bytes,
    max_revision_bytes = max_revision_bytes
  )
  marker <- charToRaw('{"format":"graft-artifacts","version":1}')
  if (create) {
    artifact_postgres_put(store, "store", "format", marker, 1024)
  }
  if (
    !identical(artifact_postgres_read(store, "store", "format", 1024), marker)
  ) {
    artifact_abort("Unsupported artifact store marker.")
  }
  store
}

artifact_postgres_lock <- function(connection, scope) {
  # RPostgres checks its transaction state before issuing the SAVEPOINT.
  name <- basename(tempfile("graft_transaction_"))
  tryCatch(
    {
      DBI::dbBegin(connection, name = name)
      DBI::dbCommit(connection, name = name)
    },
    error = function(e) {
      artifact_abort(
        "A PostgreSQL artifact operation requires an active DBI transaction."
      )
    }
  )
  isolation <- artifact_postgres_query(
    connection,
    "SHOW transaction_isolation"
  )[[1L]]
  if (!identical(isolation, "read committed")) {
    artifact_abort(
      "PostgreSQL artifact operations require READ COMMITTED isolation."
    )
  }
  artifact_postgres_query(
    connection,
    "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
    params = list(paste0("graft:scope:", scope))
  )
  invisible(NULL)
}

artifact_postgres_read <- function(store, kind, key, limit) {
  rows <- artifact_postgres_query(
    store@connection,
    paste(
      "SELECT payload FROM graft_artifact_objects",
      "WHERE scope = $1 AND kind = $2 AND object_key = $3",
      "AND octet_length(payload) <= $4"
    ),
    params = list(store@scope, kind, key, limit)
  )
  if (nrow(rows) != 1L) {
    artifact_abort(
      "Artifact is unavailable in this scope or exceeds the byte bound."
    )
  }
  rows$payload[[1L]]
}

artifact_postgres_put <- function(store, kind, key, bytes, limit) {
  if (length(bytes) > limit) {
    artifact_abort("Artifact exceeds the byte bound.")
  }
  DBI::dbExecute(
    store@connection,
    paste(
      "INSERT INTO graft_artifact_objects (scope, kind, object_key, payload)",
      "VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING"
    ),
    params = list(store@scope, kind, key, list(bytes))
  )
  if (!identical(artifact_postgres_read(store, kind, key, limit), bytes)) {
    artifact_abort("Immutable artifact key contains different bytes.")
  }
  invisible(NULL)
}

S7::method(artifact_storage_read, PostgresArtifactStore) <- function(
  store,
  kind,
  key,
  limit
) {
  artifact_postgres_read(store, kind, key, limit)
}

S7::method(artifact_storage_put, PostgresArtifactStore) <- function(
  store,
  kind,
  key,
  bytes,
  limit
) {
  artifact_postgres_put(store, kind, key, bytes, limit)
}

S7::method(artifact_with_stream_lock, PostgresArtifactStore) <- function(
  store,
  stream,
  code
) {
  code()
}

S7::method(artifact_with_store_lock, PostgresArtifactStore) <- function(
  store,
  exclusive,
  code
) {
  code()
}

S7::method(artifact_decision_entries, LocalArtifactStore) <- function(
  store,
  hash,
  max_decisions
) {
  path <- artifact_path(store, "decisions", hash)
  if (!file.exists(path)) {
    return(data.frame(name = character(), size = numeric()))
  }
  if (!dir.exists(path) || file.access(path, 4L) != 0L) {
    artifact_abort("Decision journal is not a readable directory.")
  }
  files <- list.files(path, all.files = TRUE, no.. = TRUE)
  files <- sort(files[!grepl("^staged-", files)])
  paths <- file.path(path, files)
  if (any(dir.exists(paths))) {
    artifact_abort("Decision journal has invalid entries.")
  }
  data.frame(name = files, size = file.info(paths)$size)
}

S7::method(artifact_decision_streams, LocalArtifactStore) <- function(
  store,
  max_streams
) {
  path <- file.path(store@path, "decisions")
  if (!file.exists(path)) {
    return(character())
  }
  if (!dir.exists(path) || file.access(path, 4L) != 0L) {
    artifact_abort("Decision directory is not readable.")
  }
  hashes <- sort(
    list.files(path, all.files = TRUE, no.. = TRUE),
    method = "radix"
  )
  if (
    !all(grepl("^[0-9a-f]{64}$", hashes)) ||
      !all(dir.exists(file.path(path, hashes)))
  ) {
    artifact_abort("Decision directory has invalid entries.")
  }
  # A failed first publication can leave a journal with no committed record,
  # which artifact_decision_entries() treats as empty; it is not a stream, so
  # it does not count against the bound.
  committed <- character()
  for (hash in hashes) {
    files <- list.files(file.path(path, hash), all.files = TRUE, no.. = TRUE)
    if (!all(grepl("^staged-", files))) {
      committed <- c(committed, hash)
      if (length(committed) > max_streams) {
        break
      }
    }
  }
  committed
}

S7::method(artifact_decision_entries, PostgresArtifactStore) <- function(
  store,
  hash,
  max_decisions
) {
  prefix <- paste0(hash, "/")
  rows <- artifact_postgres_query(
    store@connection,
    paste(
      "SELECT object_key, octet_length(payload) AS size",
      "FROM graft_artifact_objects WHERE scope = $1 AND kind = 'decisions'",
      "AND left(object_key, length($2)) = $2 ORDER BY object_key LIMIT $3"
    ),
    params = list(store@scope, prefix, max_decisions + 1)
  )
  data.frame(
    name = substring(rows$object_key, nchar(prefix) + 1L),
    size = rows$size
  )
}

S7::method(artifact_decision_streams, PostgresArtifactStore) <- function(
  store,
  max_streams
) {
  # Every decision key must be a stream hash and a journal entry name before
  # stream hashes are taken from its prefix; a damaged key would otherwise be
  # grouped under a stream and then skipped, leaving the list incomplete.
  malformed <- artifact_postgres_query(
    store@connection,
    paste(
      "SELECT 1 FROM graft_artifact_objects",
      "WHERE scope = $1 AND kind = 'decisions'",
      "AND object_key !~ '^[0-9a-f]{64}/[0-9]{10}-[0-9a-f]{64}[.]json$' LIMIT 1"
    ),
    params = list(store@scope)
  )
  if (nrow(malformed)) {
    artifact_abort("Decision directory has invalid entries.")
  }
  rows <- artifact_postgres_query(
    store@connection,
    paste(
      "SELECT DISTINCT left(object_key, 64) COLLATE \"C\" AS stream",
      "FROM graft_artifact_objects WHERE scope = $1 AND kind = 'decisions'",
      "ORDER BY stream LIMIT $2"
    ),
    params = list(store@scope, max_streams + 1)
  )
  hashes <- as.character(rows$stream)
  if (!all(grepl("^[0-9a-f]{64}$", hashes))) {
    artifact_abort("Decision directory has invalid entries.")
  }
  hashes
}

artifact_postgres_query <- function(connection, statement, params = list()) {
  result <- DBI::dbSendQuery(connection, statement)
  on.exit(DBI::dbClearResult(result), add = TRUE)
  if (length(params)) {
    DBI::dbBind(result, params)
  }
  DBI::dbFetch(result)
}
