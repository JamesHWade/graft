graft_measure_class_name <- "GraftMeasure"
graft_measure_view_name <- "graft_measure"

graft_measure_slot <- function(
  name,
  range = "string",
  duckdb_type = "VARCHAR",
  required = FALSE,
  identifier = FALSE
) {
  list(
    duckdb_type = duckdb_type,
    enum = NULL,
    external_identifier = NULL,
    identifier = identifier,
    maximum_value = NULL,
    meaning = NULL,
    minimum_value = NULL,
    multivalued = FALSE,
    name = name,
    object_reference = FALSE,
    ordered = FALSE,
    pattern = NULL,
    range = range,
    required = required,
    search_weight = NULL,
    sensitive = FALSE,
    view_column = name
  )
}

graft_measure_class_contract <- function() {
  list(
    ancestors = list(graft_measure_class_name, "GraftMetadata", "GraftRecord"),
    fixed_predicate = NULL,
    id_format = "linkml",
    id_policy = "require",
    is_a = "GraftMetadata",
    label_slot = "name",
    name = graft_measure_class_name,
    origin_key_slots = list(),
    qualifier_slots = list(),
    relations = list(),
    role = "metadata",
    search_slots = list("title", "description"),
    slots = list(
      id = graft_measure_slot(
        "id",
        range = "uriorcurie",
        required = TRUE,
        identifier = TRUE
      ),
      created_at = graft_measure_slot(
        "created_at",
        range = "datetime",
        duckdb_type = "TIMESTAMP"
      ),
      updated_at = graft_measure_slot(
        "updated_at",
        range = "datetime",
        duckdb_type = "TIMESTAMP"
      ),
      name = graft_measure_slot("name", required = TRUE),
      title = graft_measure_slot("title"),
      description = graft_measure_slot("description"),
      target_class = graft_measure_slot("target_class", required = TRUE),
      expr = graft_measure_slot("expr", required = TRUE),
      parameters = graft_measure_slot("parameters"),
      dimensions = graft_measure_slot("dimensions")
    ),
    statement_shape = NULL,
    type_uri = "https://w3id.org/graft/GraftMeasure",
    view = graft_measure_view_name
  )
}

augment_manifest_with_measures <- function(compiled) {
  manifest <- compiled$manifest
  if (!is.null(manifest$classes[[graft_measure_class_name]])) {
    return(compiled)
  }
  taken_views <- vapply(
    manifest$classes,
    \(class) scalar_character(class$view),
    character(1)
  )
  if (graft_measure_view_name %in% taken_views) {
    abort_schema_error(
      paste0(
        "The view name `",
        graft_measure_view_name,
        "` is reserved for the graft measure system class."
      ),
      field = "view",
      rule = "reserved_measure_view"
    )
  }
  manifest$classes[[graft_measure_class_name]] <- graft_measure_class_contract()
  manifest$fingerprints$structural_digest <- manifest_structural_digest(
    manifest
  )
  manifest$fingerprints$build_digest <- manifest_build_digest(manifest)
  compiled$manifest <- manifest
  compiled
}

measure_scalar_columns <- function(contract) {
  slots <- Filter(
    \(slot) !scalar_logical(slot$multivalued),
    contract$slots
  )
  names(slots)
}

measure_json_list <- function(text) {
  if (is.null(text) || is.na(text) || !nzchar(text)) {
    return(list())
  }
  parsed <- tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = \(error) error
  )
  if (rlang::is_condition(parsed) || !is.list(parsed)) {
    return(NULL)
  }
  parsed
}

validate_measure_candidates <- function(manifest, staged) {
  issues <- list()
  data <- staged$data
  add_issue <- function(index, field, rule, message) {
    issues[[length(issues) + 1L]] <<- new_plan_issue(
      record_class = staged$class,
      input_row = index,
      record_id = scalar_character(data$id[[index]]),
      field = field,
      rule = rule,
      message = message
    )
  }
  for (index in seq_len(nrow(data))) {
    target <- scalar_character(data$target_class[[index]])
    contract <- manifest$classes[[target]]
    if (
      is.na(target) ||
        is.null(contract) ||
        identical(target, graft_measure_class_name)
    ) {
      if (!is.na(target)) {
        add_issue(
          index,
          "target_class",
          "measure_target_class",
          paste0("`", target, "` is not a measurable contract class.")
        )
      }
      next
    }
    columns <- measure_scalar_columns(contract)
    expr <- scalar_character(data$expr[[index]])
    if (!is.na(expr)) {
      checked <- measure_expr_check(expr, columns)
      for (row in seq_len(nrow(checked$issues))) {
        add_issue(
          index,
          "expr",
          checked$issues$rule[[row]],
          checked$issues$message[[row]]
        )
      }
    }
    parameters <- measure_json_list(scalar_character(
      data$parameters[[index]]
    ))
    if (is.null(parameters)) {
      add_issue(
        index,
        "parameters",
        "measure_parameter_json",
        "`parameters` must be a JSON array of parameter objects."
      )
    } else {
      for (parameter in parameters) {
        fields <- c("name", "type", "description", "column")
        complete <- is.list(parameter) &&
          all(vapply(
            parameter[fields],
            \(value) is_nonempty_string(value),
            logical(1)
          ))
        if (!complete) {
          add_issue(
            index,
            "parameters",
            "measure_parameter_contract",
            paste(
              "Each parameter needs non-empty `name`, `type`,",
              "`description`, and `column` strings."
            )
          )
          next
        }
        if (!(parameter$column %in% columns)) {
          add_issue(
            index,
            "parameters",
            "measure_parameter_column",
            paste0(
              "Parameter `",
              parameter$name,
              "` binds to unknown column `",
              parameter$column,
              "` of class `",
              target,
              "`."
            )
          )
        }
      }
    }
    dimensions <- measure_json_list(scalar_character(
      data$dimensions[[index]]
    ))
    if (is.null(dimensions)) {
      add_issue(
        index,
        "dimensions",
        "measure_dimension_json",
        "`dimensions` must be a JSON array of column names."
      )
    } else {
      for (dimension in dimensions) {
        if (!is_nonempty_string(dimension) || !(dimension %in% columns)) {
          add_issue(
            index,
            "dimensions",
            "measure_dimension_column",
            paste0(
              "Dimension `",
              if (is_nonempty_string(dimension)) dimension else "",
              "` is not a scalar column of class `",
              target,
              "`."
            )
          )
        }
      }
    }
  }
  issues
}

contract_measure_records <- function(manifest) {
  document <- manifest$dictionary$document
  if (is.null(document)) {
    return(NULL)
  }
  rows <- list()
  for (table in document$tables) {
    definitions <- table$definitions
    if (is.null(definitions)) {
      next
    }
    for (definition in definitions) {
      rows[[length(rows) + 1L]] <- data.frame(
        id = paste0("measure:", scalar_character(definition$name)),
        name = scalar_character(definition$name),
        title = scalar_character(definition$label),
        description = scalar_character(definition$description),
        target_class = scalar_character(table$name),
        expr = scalar_character(definition$expr),
        parameters = "[]",
        dimensions = "[]",
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0L) {
    return(NULL)
  }
  do.call(rbind, rows)
}

seed_contract_measures <- function(store, compiled_schema) {
  records <- contract_measure_records(compiled_schema$manifest)
  if (is.null(records)) {
    return(invisible(store))
  }
  graft_ingest(
    store,
    stats::setNames(list(records), graft_measure_class_name),
    graft_provenance(
      producer = "contract",
      idempotency_key = paste0(
        "contract-measures:",
        compiled_schema$manifest$fingerprints$source_digest
      )
    )
  )
  invisible(store)
}
