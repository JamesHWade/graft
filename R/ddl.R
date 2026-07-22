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

validate_manifest_physical_names <- function(schema) {
  manifest <- schema$manifest
  table_names <- vapply(
    manifest$tables,
    \(.x) scalar_character(.x$name),
    character(1)
  )
  relation_names <- vapply(
    manifest$relations,
    \(.x) scalar_character(.x$table),
    character(1)
  )
  names <- c(table_names, relation_names)
  invalid <- names[
    is.na(names) |
      !nzchar(names) |
      startsWith(tolower(names), "_graft_")
  ]
  if (length(invalid) > 0L) {
    abort_schema_error(
      paste0(
        "Client physical objects may not use the reserved `_graft_` prefix: ",
        paste(unique(invalid), collapse = ", "),
        "."
      ),
      physical_objects = unique(invalid)
    )
  }
  duplicated_names <- unique(names[duplicated(tolower(names))])
  if (length(duplicated_names) > 0L) {
    abort_schema_error(
      paste0(
        "Manifest physical table names must be unique: ",
        paste(duplicated_names, collapse = ", "),
        "."
      ),
      physical_objects = duplicated_names
    )
  }
  invisible(schema)
}

create_manifest_tables <- function(connection, schema) {
  manifest <- schema$manifest
  for (table in manifest$tables) {
    create_manifest_table(connection, table)
  }
  for (relation in manifest$relations) {
    create_manifest_relation_table(connection, relation)
  }
  invisible(connection)
}

create_manifest_table <- function(connection, table) {
  table_name <- scalar_character(table$name)
  create_table(connection, table_name, table$columns)
  create_table_indexes(
    connection,
    table_name,
    manifest_table_indexes(table)
  )
  invisible(connection)
}

create_manifest_relation_table <- function(connection, relation) {
  table_name <- scalar_character(relation$table)
  create_table(
    connection,
    table_name,
    relation$columns,
    unique_constraints = relation_unique_constraints(relation)
  )
  create_table_indexes(
    connection,
    table_name,
    manifest_relation_indexes(relation)
  )
  invisible(connection)
}

manifest_table_indexes <- function(table) {
  reference_columns <- Filter(
    \(.x) !is.null(.x$foreign_key),
    table$columns
  )
  lapply(reference_columns, \(.x) scalar_character(.x$name))
}

manifest_relation_indexes <- function(relation) {
  index_columns <- intersect(
    c("owner_id", "subject", "object"),
    vapply(
      relation$columns,
      \(.x) scalar_character(.x$name),
      character(1)
    )
  )
  as.list(index_columns)
}

add_manifest_column <- function(connection, table, column) {
  if (!scalar_logical(column$nullable, default = TRUE)) {
    abort_schema_error(
      "Migration columns must be nullable.",
      table = table,
      column = scalar_character(column$name)
    )
  }
  sql <- paste0(
    "ALTER TABLE ",
    quote_identifier(connection, table),
    " ADD COLUMN ",
    column_definition_sql(connection, column)
  )
  DBI::dbExecute(connection, sql)
  if (!is.null(column$foreign_key)) {
    create_table_indexes(
      connection,
      table,
      list(scalar_character(column$name))
    )
  }
  invisible(connection)
}

relation_unique_constraints <- function(relation) {
  columns <- vapply(
    relation$columns,
    \(.x) scalar_character(.x$name),
    character(1)
  )
  ordered <- scalar_logical(relation$ordered)
  kind <- scalar_character(relation$kind)
  if (identical(kind, "object")) {
    if (ordered && all(c("subject", "position") %in% columns)) {
      return(list(c("subject", "position")))
    }
    if (all(c("subject", "object") %in% columns)) {
      return(list(c("subject", "object")))
    }
  }
  if (identical(kind, "value")) {
    if (ordered && all(c("owner_id", "position") %in% columns)) {
      return(list(c("owner_id", "position")))
    }
    if (all(c("owner_id", "value") %in% columns)) {
      return(list(c("owner_id", "value")))
    }
  }
  list()
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
      paste0("Unsupported manifest relational type `", type, "`."),
      relational_type = type
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
