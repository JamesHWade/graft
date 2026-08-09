ddl_column <- function(
  name,
  type,
  nullable = TRUE,
  primary_key = FALSE
) {
  list(
    name = name,
    type = type,
    nullable = nullable,
    primary_key = primary_key
  )
}

create_table <- function(
  connection,
  table,
  columns,
  unique_constraints = NULL
) {
  column_sql <- vapply(
    columns,
    \(.x) column_definition_sql(connection, .x),
    character(1)
  )
  constraint_sql <- vapply(
    unique_constraints,
    function(fields) {
      paste0(
        "UNIQUE (",
        paste(quote_identifier(connection, fields), collapse = ", "),
        ")"
      )
    },
    character(1)
  )
  sql <- paste0(
    "CREATE TABLE ",
    quote_identifier(connection, table),
    " (",
    paste(c(column_sql, constraint_sql), collapse = ", "),
    ")"
  )
  DBI::dbExecute(connection, sql)
  invisible(connection)
}

column_definition_sql <- function(connection, column) {
  name <- scalar_character(column$name)
  type <- safe_duckdb_type(scalar_character(column$type))
  primary_key <- scalar_logical(column$primary_key)
  nullable <- scalar_logical(column$nullable, default = TRUE)
  constraints <- character()
  if (primary_key) {
    constraints <- "PRIMARY KEY"
  } else if (!nullable) {
    constraints <- "NOT NULL"
  }
  paste(
    c(quote_identifier(connection, name), type, constraints),
    collapse = " "
  )
}

safe_duckdb_type <- function(type) {
  type <- toupper(trimws(type))
  allowed <- c(
    "BOOLEAN",
    "DATE",
    "TIME",
    "TIMESTAMP",
    "BIGINT",
    "DOUBLE",
    "DECIMAL",
    "VARCHAR"
  )
  if (!type %in% allowed) {
    abort_schema_error(
      paste0("Unsupported manifest DuckDB type `", type, "`."),
      duckdb_type = type
    )
  }
  type
}

quote_identifier <- function(connection, identifier) {
  as.character(DBI::dbQuoteIdentifier(connection, identifier))
}

create_table_indexes <- function(connection, table, indexes) {
  if (length(indexes) == 0L) {
    return(invisible(connection))
  }
  for (fields in indexes) {
    fields <- as.character(fields)
    if (length(fields) == 0L || anyNA(fields)) {
      next
    }
    index_name <- graft_index_name(table, fields)
    sql <- paste0(
      "CREATE INDEX ",
      quote_identifier(connection, index_name),
      " ON ",
      quote_identifier(connection, table),
      " (",
      paste(quote_identifier(connection, fields), collapse = ", "),
      ")"
    )
    DBI::dbExecute(connection, sql)
  }
  invisible(connection)
}

graft_index_name <- function(table, fields) {
  paste(c("graft_idx", table, fields), collapse = "_")
}
