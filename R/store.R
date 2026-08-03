open_store_backend <- function(
  schema,
  path = ":memory:",
  read_only = FALSE,
  connection = NULL,
  okf = c("managed", "disabled"),
  okf_path = NULL
) {
  if (!is_compiled_schema(schema)) {
    abort_schema_error("Internal store setup requires a compiled schema.")
  }
  validate_read_only(read_only)
  okf <- rlang::arg_match(okf)

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

  okf_path <- resolve_managed_okf_path(path, okf, okf_path)
  capabilities <- duckdb_capabilities(
    read_only = read_only,
    owns_connection = owns_connection
  )
  store <- new_store_backend(
    schema = schema,
    connection = connection,
    owns_connection = owns_connection,
    read_only = read_only,
    path = path,
    capabilities = capabilities,
    okf_mode = okf,
    okf_path = okf_path
  )
  if (owns_connection) {
    reg.finalizer(
      store,
      function(store) {
        disconnect_owned_backend(store, finalizer = TRUE)
      },
      onexit = TRUE
    )
  }
  store
}

resolve_managed_okf_path <- function(store_path, okf, okf_path) {
  if (identical(okf, "disabled")) {
    if (!is.null(okf_path)) {
      abort_validation_error(
        "`okf_path` cannot be supplied when `okf = \"disabled\"`.",
        field = "okf_path",
        rule = "disabled_okf_path",
        observed_value = okf_path
      )
    }
    return(NULL)
  }
  if (!is.null(okf_path)) {
    return(okf_normalize_path(okf_path))
  }
  if (
    identical(store_path, ":memory:") ||
      identical(store_path, "<caller-supplied>")
  ) {
    return(NULL)
  }
  extension <- tools::file_ext(store_path)
  stem <- if (nzchar(extension)) {
    tools::file_path_sans_ext(store_path)
  } else {
    store_path
  }
  okf_normalize_path(paste0(stem, ".okf"))
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
  validate_store_backend(store)
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

initialize_store_backend <- function(store) {
  validate_store_backend(store)
  validate_manifest_integrity(store$schema)

  if (duckdb_table_exists(store$connection, "_graft_store")) {
    if (isTRUE(store$read_only)) {
      verify_initialized_store(store)
      verify_projection_views(store$connection, store$schema)
    } else {
      with_duckdb_error(
        "initialize_existing_store",
        DBI::dbWithTransaction(store$connection, {
          verify_initialized_store(store)
          rebuild_projection_views(store$connection, store$schema)
        })
      )
    }
    mark_store_verified(store)
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
      insert_store_metadata(store)
      register_initial_schema(store)
      rebuild_projection_views(store$connection, store$schema)
    })
  )
  mark_store_verified(store)
  invisible(store)
}

close_store_backend <- function(store) {
  validate_store_backend(store, require_open = FALSE)
  if (isTRUE(store$closed)) {
    return(invisible(store))
  }
  if (isTRUE(store$owns_connection)) {
    disconnect_owned_backend(store)
  } else {
    store$closed <- TRUE
  }
  invisible(store)
}

disconnect_owned_backend <- function(store, finalizer = FALSE) {
  if (!is_store_backend(store) || isTRUE(store$closed)) {
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

duckdb_capabilities <- function(read_only, owns_connection) {
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
