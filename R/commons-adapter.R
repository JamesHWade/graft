#' Create a detached Commons data source
#'
#' `graft_commons_data_source()` materializes accepted public tables and
#' definitions at one immutable boundary, then loads exact typed values and a
#' generated data-dict dictionary into `commons::data_source()`. The returned
#' Commons source owns its DuckDB connection and does not share Graft's backend.
#'
#' @param source An initialized `GraftStore` or immutable `GraftView`.
#' @param classes Optional public class names to materialize. The default is
#'   every public class in the active schema.
#'
#' @return A detached `commons_data_source` object.
#' @export
graft_commons_data_source <- function(source, classes = NULL) {
  read_source <- as_graft_read_store_internal(source, "source")
  validate_graft_retrieval(read_source)
  classes <- commons_selected_classes(read_source$schema$manifest, classes)
  if (!is_graft_snapshot_backend(read_source)) {
    boundary <- graft_snapshot(source)
    read_source <- as_graft_read_store_internal(
      graft_at(source, boundary),
      "source"
    )
  }
  materialized <- commons_materialize(read_source, classes)
  commons_validate_table_names(names(materialized$tables))
  dictionary <- commons_dictionary(
    read_source,
    classes,
    materialized$relations
  )
  path <- tempfile("graft-commons-", fileext = ".yaml")
  on.exit(unlink(path), add = TRUE)
  yaml::write_yaml(dictionary, path)
  commons_data_source_call(materialized$tables, path, materialized$types)
}

commons_selected_classes <- function(manifest, classes) {
  available <- setdiff(names(manifest$classes), graft_definition_class_name)
  if (is.null(classes)) {
    return(sort(available, method = "radix"))
  }
  if (
    !is.character(classes) ||
      length(classes) == 0L ||
      anyNA(classes) ||
      !all(nzchar(classes)) ||
      anyDuplicated(classes)
  ) {
    abort_validation_error(
      "`classes` must contain unique, non-empty public class names.",
      field = "classes",
      rule = "commons_classes",
      observed_value = classes
    )
  }
  unavailable <- setdiff(classes, available)
  if (length(unavailable) > 0L) {
    abort_validation_error(
      paste0(
        "Unknown or non-public Commons class selection: ",
        paste(unavailable, collapse = ", "),
        "."
      ),
      field = "classes",
      rule = "commons_classes",
      observed_value = unavailable
    )
  }
  sort(classes, method = "radix")
}

commons_materialize <- function(source, classes) {
  manifest <- source$schema$manifest
  tables <- stats::setNames(
    lapply(classes, function(class_name) {
      definition_target_frame(source, manifest$classes[[class_name]])
    }),
    classes
  )
  types <- stats::setNames(
    lapply(classes, function(class_name) {
      commons_class_types(manifest$classes[[class_name]])
    }),
    classes
  )
  relations <- Filter(
    function(relation) {
      owner <- scalar_character(relation$owner_class)
      slot_name <- scalar_character(relation$slot)
      slot <- manifest$classes[[owner]]$slots[[slot_name]]
      owner %in% classes && !scalar_logical(slot$sensitive)
    },
    manifest$relations
  )
  for (relation in relations) {
    view <- scalar_character(relation$view)
    tables[[view]] <- commons_relation_frame(source, relation)
    types[[view]] <- commons_relation_types(manifest, relation)
  }
  list(tables = tables, types = types, relations = relations)
}

commons_class_types <- function(contract) {
  columns <- definition_public_scalar_columns(contract)
  stats::setNames(
    vapply(
      columns,
      function(column) {
        safe_duckdb_type(scalar_character(
          contract$slots[[column]]$duckdb_type
        ))
      },
      ""
    ),
    columns
  )
}

commons_relation_types <- function(manifest, relation) {
  owner <- scalar_character(relation$owner_class)
  slot_name <- scalar_character(relation$slot)
  slot <- manifest$classes[[owner]]$slots[[slot_name]]
  if (identical(scalar_character(relation$kind), "object")) {
    return(c(
      id = "VARCHAR",
      subject = "VARCHAR",
      object = "VARCHAR",
      position = "BIGINT",
      created_at = "TIMESTAMP"
    ))
  }
  c(
    owner_id = "VARCHAR",
    position = "BIGINT",
    value = safe_duckdb_type(scalar_character(slot$duckdb_type))
  )
}

commons_relation_frame <- function(source, relation) {
  owner <- scalar_character(relation$owner_class)
  rows <- retrieval_query(
    source$connection,
    paste0(
      "SELECT record_id, payload_json, recorded_at FROM (",
      graft_read_source_sql(source),
      ") commons_source WHERE class = ? ORDER BY record_id"
    ),
    params = list(owner)
  )
  payloads <- lapply(rows$payload_json, projection_parse_payload)
  projection_multivalue_rows(
    rows,
    payloads,
    source$schema,
    relation
  )
}

commons_dictionary <- function(source, classes, relations) {
  manifest <- source$schema$manifest
  original <- manifest$dictionary$document
  relation_targets <- vapply(
    relations,
    \(relation) scalar_character(relation$view),
    ""
  )
  targets <- unique(c(classes, relation_targets))
  definitions <- lapply(
    targets,
    \(target) definition_catalog(source, target, bounded = FALSE)
  ) |>
    dplyr::bind_rows()
  tables <- lapply(classes, function(class_name) {
    contract <- manifest$classes[[class_name]]
    original_table <- commons_original_table(original, class_name)
    commons_class_dictionary_table(
      class_name,
      contract,
      original_table,
      definitions[definitions$target == class_name, , drop = FALSE],
      manifest
    )
  })
  relation_tables <- lapply(relations, function(relation) {
    commons_relation_dictionary_table(
      manifest,
      relation,
      definitions[
        definitions$target == scalar_character(relation$view),
        ,
        drop = FALSE
      ]
    )
  })
  document <- list(
    `$version` = "0.1.0",
    name = commons_dictionary_prose(original, "name"),
    description = commons_dictionary_prose(original, "description"),
    details = commons_dictionary_prose(original, "details"),
    tables = c(tables, relation_tables),
    relationships = commons_dictionary_relationships(original, classes),
    glossary = if (is.null(original)) NULL else original$glossary
  )
  commons_compact(document)
}

commons_original_table <- function(document, class_name) {
  if (is.null(document) || is.null(document$tables)) {
    return(NULL)
  }
  indexes <- which(vapply(
    document$tables,
    \(table) identical(scalar_character(table$name), class_name),
    logical(1)
  ))
  if (length(indexes) != 1L) NULL else document$tables[[indexes]]
}

commons_class_dictionary_table <- function(
  class_name,
  contract,
  original,
  definitions,
  manifest
) {
  columns <- lapply(
    definition_public_scalar_columns(contract),
    function(slot_name) {
      original_column <- commons_original_column(original, slot_name)
      commons_dictionary_column(
        slot_name,
        contract$slots[[slot_name]],
        original_column,
        manifest
      )
    }
  )
  table <- list(
    name = class_name,
    label = if (is.null(original)) NULL else original$label,
    description = if (is.null(original)) NULL else original$description,
    details = if (is.null(original)) NULL else original$details,
    columns = columns,
    definitions = lapply(seq_len(nrow(definitions)), function(index) {
      commons_definition_dictionary_row(definitions[index, , drop = FALSE])
    })
  )
  commons_compact(table)
}

commons_original_column <- function(table, slot_name) {
  if (is.null(table) || is.null(table$columns)) {
    return(NULL)
  }
  indexes <- which(vapply(
    table$columns,
    \(column) identical(scalar_character(column$name), slot_name),
    logical(1)
  ))
  if (length(indexes) != 1L) NULL else table$columns[[indexes]]
}

commons_dictionary_column <- function(name, slot, original, manifest) {
  column <- list(
    name = name,
    type = commons_definition_type(slot),
    label = if (is.null(original)) NULL else original$label,
    description = if (is.null(original)) NULL else original$description,
    details = if (is.null(original)) NULL else original$details,
    units = if (is.null(original)) NULL else original$units,
    constraints = if (is.null(original)) NULL else original$constraints
  )
  enum <- scalar_character(slot$enum)
  if (!is.na(enum)) {
    values <- manifest$enums[[enum]]$permissible_values
    column$values <- vapply(
      values,
      \(value) {
        scalar_character(value$value)
      },
      character(1)
    )
  }
  commons_compact(column)
}

commons_definition_type <- function(slot) {
  enum <- scalar_character(slot$enum)
  if (!is.na(enum)) {
    return("enum")
  }
  switch(
    toupper(scalar_character(slot$duckdb_type, "VARCHAR")),
    BOOLEAN = "boolean",
    DATE = "date",
    TIMESTAMP = "datetime",
    DOUBLE = "number",
    FLOAT = "number",
    DECIMAL = "number",
    BIGINT = "number",
    INTEGER = "number",
    "string"
  )
}

commons_definition_dictionary_row <- function(definition) {
  commons_compact(list(
    name = definition$name[[1L]],
    expr = definition$expr[[1L]],
    label = definition$label[[1L]],
    description = definition$description[[1L]],
    details = definition$details[[1L]]
  ))
}

commons_relation_dictionary_table <- function(manifest, relation, definitions) {
  owner <- scalar_character(relation$owner_class)
  slot <- manifest$classes[[owner]]$slots[[scalar_character(relation$slot)]]
  columns <- if (identical(scalar_character(relation$kind), "object")) {
    list(
      list(name = "id", type = "string"),
      list(name = "subject", type = "string"),
      list(name = "object", type = commons_definition_type(slot)),
      list(name = "position", type = "number"),
      list(name = "created_at", type = "datetime")
    )
  } else {
    list(
      list(name = "owner_id", type = "string"),
      list(name = "position", type = "number"),
      list(name = "value", type = commons_definition_type(slot))
    )
  }
  list(
    name = scalar_character(relation$view),
    description = paste0(
      "Normalized accepted values for `",
      scalar_character(relation$name),
      "`."
    ),
    columns = columns,
    definitions = lapply(seq_len(nrow(definitions)), function(index) {
      commons_definition_dictionary_row(definitions[index, , drop = FALSE])
    })
  )
}

commons_dictionary_relationships <- function(document, classes) {
  if (is.null(document) || is.null(document$relationships)) {
    return(NULL)
  }
  Filter(
    function(relationship) {
      tables <- commons_relationship_tables(document, relationship)
      length(tables) > 0L && all(tables %in% classes)
    },
    document$relationships
  )
}

commons_relationship_tables <- function(document, relationship) {
  pairs <- relationship$pairs
  if (!is.null(pairs) && length(pairs) > 0L) {
    return(unique(unlist(
      lapply(pairs, function(pair) {
        c(pair$left$table, pair$right$table)
      }),
      use.names = FALSE
    )))
  }
  join <- scalar_character(relationship$join)
  if (is.na(join) || is.null(document$tables)) {
    return(character())
  }
  table_names <- vapply(
    document$tables,
    \(table) scalar_character(table$name),
    ""
  )
  references <- regmatches(
    join,
    gregexpr(
      "[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\\.",
      join,
      perl = TRUE
    )
  )[[1L]]
  references <- sub("[[:space:]]*\\.$", "", references)
  unique(table_names[table_names %in% references])
}

commons_dictionary_prose <- function(document, field) {
  if (is.null(document)) NULL else document[[field]]
}

commons_compact <- function(value) {
  value[
    !vapply(
      value,
      function(item) {
        is.null(item) ||
          (is.atomic(item) && length(item) == 1L && is.na(item))
      },
      logical(1)
    )
  ]
}

commons_data_source_call <- function(tables, dictionary, types) {
  data_source <- commons_data_source_function()
  connection <- commons_materialized_connection(tables, types)
  succeeded <- FALSE
  on.exit({
    if (!succeeded) {
      DBI::dbDisconnect(connection, shutdown = TRUE)
    }
  })
  source <- do.call(
    data_source,
    list(
      connection,
      tables = names(tables),
      dictionary = dictionary
    )
  )
  source$graft_connection_handle <- commons_connection_handle(connection)
  succeeded <- TRUE
  source
}

commons_validate_table_names <- function(table_names) {
  if (
    anyNA(table_names) ||
      !all(nzchar(table_names)) ||
      anyDuplicated(table_names)
  ) {
    abort_validation_error(
      "Commons table names must be unique and non-empty.",
      field = "classes",
      rule = "commons_table_names",
      observed_value = table_names
    )
  }
  invisible(table_names)
}

commons_data_source_function <- function() {
  rlang::check_installed(
    "commons",
    version = "0.0.0.9002",
    reason = "to create a detached Commons data source"
  )
  data_source <- getExportedValue("commons", "data_source")
  arguments <- names(formals(data_source))
  required <- c("...", "tables", "exclude", "dictionary")
  if (!identical(arguments, required)) {
    abort_validation_error(
      "The installed Commons `data_source()` contract is not supported.",
      field = "commons",
      rule = "commons_data_source_contract",
      observed_value = arguments,
      expected_value = required
    )
  }
  data_source
}

commons_materialized_connection <- function(tables, types) {
  commons_validate_materialized_types(tables, types)
  directory <- file.path(tempdir(), "graft-commons-duckdb")
  dir.create(directory, showWarnings = FALSE, recursive = TRUE)
  connection <- DBI::dbConnect(
    duckdb::duckdb(
      shared_home = FALSE,
      config = list(extension_directory = directory)
    )
  )
  succeeded <- FALSE
  on.exit({
    if (!succeeded) {
      DBI::dbDisconnect(connection, shutdown = TRUE)
    }
  })
  DBI::dbExecute(
    connection,
    paste0(
      "SET home_directory=",
      DBI::dbQuoteString(connection, directory),
      ";"
    )
  )
  for (name in names(tables)) {
    columns <- lapply(
      names(types[[name]]),
      \(column) ddl_column(column, types[[name]][[column]])
    )
    create_table(connection, name, columns)
    if (nrow(tables[[name]]) > 0L) {
      DBI::dbAppendTable(
        connection,
        name,
        as.data.frame(tables[[name]])
      )
    }
  }
  DBI::dbExecute(
    connection,
    paste(
      "SET allow_community_extensions = false;",
      "SET allow_unsigned_extensions = false;",
      "SET autoinstall_known_extensions = false;",
      "SET autoload_known_extensions = false;",
      "SET enable_external_access = false;",
      "SET disabled_filesystems = 'LocalFileSystem';",
      "SET lock_configuration = true;"
    )
  )
  succeeded <- TRUE
  connection
}

commons_validate_materialized_types <- function(tables, types) {
  valid <- is.list(types) &&
    identical(names(types), names(tables)) &&
    all(vapply(
      names(tables),
      function(name) {
        table_types <- types[[name]]
        is.character(table_types) &&
          identical(names(table_types), names(tables[[name]]))
      },
      logical(1)
    ))
  if (!valid) {
    abort_backend_error(
      "The detached Commons table types do not match the materialized data.",
      operation = "commons_materialize"
    )
  }
  invisible(types)
}

commons_connection_handle <- function(connection) {
  handle <- new.env(parent = emptyenv())
  handle$connection <- connection
  reg.finalizer(
    handle,
    function(environment) {
      try(
        DBI::dbDisconnect(environment$connection, shutdown = TRUE),
        silent = TRUE
      )
    },
    onexit = TRUE
  )
  handle
}
