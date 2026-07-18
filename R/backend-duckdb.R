duckdb_connect <- function(path, read_only) {
  tryCatch(
    DBI::dbConnect(
      duckdb::duckdb(),
      dbdir = path,
      read_only = read_only
    ),
    error = function(error) {
      abort_backend_error(
        paste0(
          "Could not connect to DuckDB at `",
          path,
          "`: ",
          conditionMessage(error)
        ),
        operation = "connect",
        store_path = path,
        parent = error
      )
    }
  )
}

duckdb_disconnect <- function(connection) {
  tryCatch(
    DBI::dbDisconnect(connection, shutdown = TRUE),
    error = function(error) {
      abort_backend_error(
        paste0(
          "Could not disconnect the DuckDB connection: ",
          conditionMessage(error)
        ),
        operation = "disconnect",
        parent = error
      )
    }
  )
}

with_duckdb_error <- function(operation, code) {
  tryCatch(
    code,
    error = function(error) {
      if (inherits(error, "graft_error")) {
        stop(error)
      }
      abort_backend_error(
        paste0(
          "DuckDB operation `",
          operation,
          "` failed: ",
          conditionMessage(error)
        ),
        operation = operation,
        parent = error
      )
    }
  )
}

duckdb_path <- function(path) {
  if (identical(path, ":memory:")) {
    return(path)
  }
  normalizePath(path.expand(path), winslash = "/", mustWork = FALSE)
}

duckdb_connection_path <- function(connection) {
  info <- tryCatch(
    DBI::dbGetInfo(connection),
    error = \(.x) list()
  )
  path <- scalar_character(info$dbname, default = NA_character_)
  if (is.na(path)) {
    return("<caller-supplied>")
  }
  duckdb_path(path)
}

duckdb_table_names <- function(connection) {
  with_duckdb_error(
    "list_tables",
    as.character(DBI::dbListTables(connection))
  )
}

duckdb_table_exists <- function(connection, table) {
  with_duckdb_error(
    "table_exists",
    isTRUE(DBI::dbExistsTable(connection, table))
  )
}
