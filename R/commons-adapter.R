#' Create a detached Commons data source
#'
#' `graft_commons_data_source()` materializes accepted public tables and
#' definitions at one immutable boundary, then passes ordinary data frames and
#' a generated data-dict dictionary to `commons::data_source()`. The returned
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
  dictionary <- commons_dictionary(
    read_source,
    classes,
    materialized$relations
  )
  path <- tempfile("graft-commons-", fileext = ".yaml")
  on.exit(unlink(path), add = TRUE)
  yaml::write_yaml(dictionary, path)
  commons_data_source_call(materialized$tables, path)
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
      any(!nzchar(classes)) ||
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
    tables[[scalar_character(relation$view)]] <-
      commons_relation_frame(source, relation)
  }
  list(tables = tables, relations = relations)
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
  definitions <- definition_catalog(source)
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
      pairs <- relationship$pairs
      if (is.null(pairs)) {
        return(FALSE)
      }
      tables <- unlist(
        lapply(pairs, function(pair) {
          c(pair$left$table, pair$right$table)
        }),
        use.names = FALSE
      )
      length(tables) > 0L && all(tables %in% classes)
    },
    document$relationships
  )
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

commons_data_source_call <- function(tables, dictionary) {
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
  do.call(data_source, c(tables, list(dictionary = dictionary)))
}
