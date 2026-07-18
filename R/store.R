#' Connect to a DuckDB knowledge store
#'
#' A store combines a compiled graft schema with one DuckDB connection. When
#' graft creates the connection, graft owns and closes it. A caller-supplied
#' connection is never closed by graft.
#'
#' @param schema A `kg_schema` object or manifest path.
#' @param path DuckDB file path, or `":memory:"`. When supplied together with
#'   `connection`, it must identify that connection's database.
#' @param read_only Whether the store must prohibit writes.
#' @param connection An optional existing DuckDB DBI connection.
#'
#' @return A `kg_store` object. Call [kg_init()] before using a new store.
#' @export
kg_connect_duckdb <- function(
  schema,
  path = ":memory:",
  read_only = FALSE,
  connection = NULL
) {
  schema <- as_kg_schema(schema)
  validate_read_only(read_only)

  owns_connection <- is.null(connection)
  if (owns_connection) {
    validate_store_path(path)
    path <- duckdb_path(path)
    connection <- duckdb_connect(path, read_only)
  } else {
    validate_duckdb_connection(connection)
    if (!missing(path)) {
      validate_store_path(path)
      requested_path <- duckdb_path(path)
      connection_path <- duckdb_connection_path(connection)
      if (!identical(requested_path, connection_path)) {
        abort_backend_error(
          paste0(
            "`path` does not identify the supplied DuckDB connection: `",
            requested_path,
            "` != `",
            connection_path,
            "`."
          ),
          operation = "connect",
          argument = "path",
          store_path = requested_path,
          connection_path = connection_path
        )
      }
    }
    path <- duckdb_connection_path(connection)
  }

  capabilities <- new_duckdb_capabilities(
    read_only = read_only,
    owns_connection = owns_connection
  )
  store <- new_kg_store(
    schema = schema,
    connection = connection,
    owns_connection = owns_connection,
    read_only = read_only,
    path = path,
    capabilities = capabilities
  )
  if (owns_connection) {
    reg.finalizer(
      store,
      function(store) {
        disconnect_owned_store(store, finalizer = TRUE)
      },
      onexit = TRUE
    )
  }
  store
}

validate_read_only <- function(read_only) {
  if (
    !is.logical(read_only) ||
      length(read_only) != 1L ||
      is.na(read_only)
  ) {
    abort_backend_error(
      "`read_only` must be `TRUE` or `FALSE`.",
      operation = "connect",
      argument = "read_only"
    )
  }
  invisible(read_only)
}

validate_store_path <- function(path) {
  if (
    !is.character(path) ||
      length(path) != 1L ||
      is.na(path) ||
      !nzchar(path)
  ) {
    abort_backend_error(
      "`path` must be one non-empty DuckDB path.",
      operation = "connect",
      argument = "path"
    )
  }
  invisible(path)
}

validate_duckdb_connection <- function(connection) {
  if (
    !inherits(connection, "DBIConnection") ||
      !inherits(connection, "duckdb_connection")
  ) {
    abort_backend_error(
      "`connection` must be a DuckDB DBI connection.",
      operation = "connect",
      argument = "connection"
    )
  }
  if (
    !isTRUE(tryCatch(
      DBI::dbIsValid(connection),
      error = \(.x) FALSE
    ))
  ) {
    abort_backend_error(
      "`connection` is closed or invalid.",
      operation = "connect",
      argument = "connection"
    )
  }
  invisible(connection)
}

validate_store_writable <- function(store, operation = "write") {
  validate_kg_store(store)
  if (isTRUE(store$read_only)) {
    abort_backend_error(
      paste0(
        "A read-only store cannot perform `",
        operation,
        "`."
      ),
      operation = operation,
      store_path = store$path
    )
  }
  invisible(store)
}

#' Initialize or verify a graft store
#'
#' Initialization creates client tables from the compiled manifest plus the
#' five package-owned metadata tables. It is atomic and idempotent. Existing
#' stores must have the same structural digest as the active schema.
#'
#' @param store A `kg_store` object.
#'
#' @return `store`, invisibly.
#' @export
kg_init <- function(store) {
  validate_kg_store(store)
  validate_manifest_physical_names(store$schema)

  if (duckdb_table_exists(store$connection, "_graft_store")) {
    verify_initialized_store(store)
    return(invisible(store))
  }
  if (isTRUE(store$read_only)) {
    abort_backend_error(
      "A read-only store cannot initialize a blank database.",
      operation = "initialize",
      store_path = store$path
    )
  }
  validate_store_writable(store, "initialize")

  existing <- duckdb_table_names(store$connection)
  if (length(existing) > 0L) {
    abort_backend_error(
      paste0(
        "Cannot initialize a non-empty database without `_graft_store`; ",
        "found: ",
        paste(sort(existing), collapse = ", "),
        "."
      ),
      operation = "initialize",
      existing_tables = existing,
      store_path = store$path
    )
  }

  with_duckdb_error(
    "initialize",
    DBI::dbWithTransaction(store$connection, {
      create_metadata_tables(store$connection)
      create_manifest_tables(store$connection, store$schema)
      insert_store_metadata(store)
    })
  )
  invisible(store)
}

#' Disconnect a graft store
#'
#' Disconnecting is safe to call more than once. Graft closes only connections
#' it created; caller-supplied connections remain open.
#'
#' @param store A `kg_store` object.
#'
#' @return `store`, invisibly.
#' @export
kg_disconnect <- function(store) {
  validate_kg_store(store, require_open = FALSE)
  if (isTRUE(store$closed)) {
    return(invisible(store))
  }
  if (isTRUE(store$owns_connection)) {
    disconnect_owned_store(store)
  } else {
    store$closed <- TRUE
  }
  invisible(store)
}

disconnect_owned_store <- function(store, finalizer = FALSE) {
  if (!is_kg_store(store) || isTRUE(store$closed)) {
    return(invisible(store))
  }
  valid <- isTRUE(tryCatch(
    DBI::dbIsValid(store$connection),
    error = \(.x) FALSE
  ))
  if (valid) {
    if (isTRUE(finalizer)) {
      try(duckdb_disconnect(store$connection), silent = TRUE)
    } else {
      duckdb_disconnect(store$connection)
    }
  }
  store$closed <- TRUE
  invisible(store)
}

#' Inspect a graft store
#'
#' @param store A `kg_store` object.
#'
#' @return A named list describing the connection, initialization state, and
#'   active schema fingerprints.
#' @export
kg_store_info <- function(store) {
  validate_kg_store(store, require_open = FALSE)
  closed <- isTRUE(store$closed)
  metadata <- NULL
  initialized <- NA
  table_count <- NA_integer_
  if (!closed) {
    initialized <- duckdb_table_exists(store$connection, "_graft_store")
    table_count <- length(duckdb_table_names(store$connection))
    if (initialized) {
      metadata <- read_store_metadata(store$connection)
    }
  }

  fingerprints <- store$schema$manifest$fingerprints
  list(
    backend = "duckdb",
    path = store$path,
    read_only = store$read_only,
    owns_connection = store$owns_connection,
    closed = closed,
    initialized = initialized,
    table_count = table_count,
    structural_digest = scalar_character(
      fingerprints$structural_digest
    ),
    source_digest = scalar_character(fingerprints$source_digest),
    build_digest = scalar_character(fingerprints$build_digest),
    stored = metadata
  )
}

#' Report DuckDB store capabilities
#'
#' @param store A `kg_store` object.
#'
#' @return A named list of static backend and connection capabilities.
#' @export
kg_capabilities <- function(store) {
  validate_kg_store(store, require_open = FALSE)
  store$capabilities
}

new_duckdb_capabilities <- function(read_only, owns_connection) {
  list(
    backend = "duckdb",
    transactions = TRUE,
    temporary_tables = TRUE,
    upsert = TRUE,
    lazy_tables = TRUE,
    read_only = read_only,
    writable = !read_only,
    owns_connection = owns_connection,
    single_owning_process = TRUE
  )
}
