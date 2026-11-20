# Proposed resolved-export admission and request-role conformance.
#
# This source-only fixture consumes the current data-dict JSON export. It does
# not parse expressions, compose translations, compile SQL, execute a backend,
# or construct a Commons object.

resolved_proposal_schema <- "graft-resolved-export/proposed/1"
resolved_proposal_export_version <- "0.1.0"
resolved_proposal_types <- c(
  "number",
  "string",
  "boolean",
  "date",
  "datetime",
  "interval"
)

resolved_proposal_abort <- function(
  message,
  subclass = "resolved_proposal_error"
) {
  rlang::abort(
    message,
    class = unique(c(subclass, "resolved_proposal_error")),
    call = rlang::caller_env()
  )
}

resolved_proposal_text <- function(value, name) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(value)
  ) {
    resolved_proposal_abort(
      paste0("`", name, "` must be one non-empty string."),
      "resolved_proposal_field_error"
    )
  }
  attributes(value) <- NULL
  value
}

resolved_proposal_names <- function(value, name) {
  if (is.null(value)) {
    return(character())
  }
  if (is.list(value)) {
    if (!is.null(names(value))) {
      resolved_proposal_abort(
        paste0("`", name, "` must be an array of strings."),
        "resolved_proposal_field_error"
      )
    }
    value <- vapply(value, resolved_proposal_text, character(1), name = name)
  }
  if (
    !is.character(value) ||
      anyNA(value) ||
      !all(nzchar(value)) ||
      anyDuplicated(value)
  ) {
    resolved_proposal_abort(
      paste0("`", name, "` must contain unique string names."),
      "resolved_proposal_field_error"
    )
  }
  value
}

resolved_proposal_records <- function(value, name, required = TRUE) {
  if (is.null(value)) {
    if (required) {
      resolved_proposal_abort(
        paste0("`", name, "` is required."),
        "resolved_proposal_schema_error"
      )
    }
    return(list())
  }
  if (!is.list(value) || is.object(value)) {
    resolved_proposal_abort(
      paste0("`", name, "` must be an array of objects."),
      "resolved_proposal_field_error"
    )
  }
  names_from_records <- vapply(
    value,
    function(record) {
      if (!is.list(record) || is.object(record)) {
        resolved_proposal_abort(
          paste0("Each record in `", name, "` must be an object."),
          "resolved_proposal_field_error"
        )
      }
      resolved_proposal_text(record$name, paste0(name, "$name"))
    },
    character(1)
  )
  if (anyDuplicated(names_from_records)) {
    resolved_proposal_abort(
      paste0("`", name, "` has duplicate names."),
      "resolved_proposal_reference_error"
    )
  }
  if (
    !is.null(names(value)) &&
      !identical(names(value), unname(names_from_records))
  ) {
    resolved_proposal_abort(
      paste0("`", name, "` names must match each record's `name`."),
      "resolved_proposal_field_error"
    )
  }
  names(value) <- names_from_records
  value
}

resolved_proposal_sha256 <- function(value, name) {
  value <- resolved_proposal_text(value, name)
  if (!grepl("^[a-f0-9]{64}$", value)) {
    resolved_proposal_abort(
      paste0("`", name, "` must be a lowercase SHA-256 digest."),
      "resolved_proposal_identity_error"
    )
  }
  value
}

resolved_proposal_binding <- function(value, name) {
  if (!is.list(value) || is.object(value)) {
    resolved_proposal_abort(
      paste0("`", name, "` must contain a host path and SHA-256 digest."),
      "resolved_proposal_identity_error"
    )
  }
  path <- resolved_proposal_text(value$path, paste0(name, "$path"))
  expected <- resolved_proposal_sha256(value$sha256, paste0(name, "$sha256"))
  if (!file.exists(path) || dir.exists(path)) {
    resolved_proposal_abort(
      paste0("Host binding `", name, "` does not point to a file."),
      "resolved_proposal_identity_error"
    )
  }
  actual <- digest::digest(file = path, algo = "sha256")
  if (!identical(actual, expected)) {
    resolved_proposal_abort(
      paste0("Host binding `", name, "` has a SHA-256 mismatch."),
      "resolved_proposal_identity_error"
    )
  }
  list(path = path, sha256 = expected)
}

resolved_proposal_json_normalize <- function(value) {
  if (!is.list(value)) {
    return(value)
  }
  normalized <- lapply(value, resolved_proposal_json_normalize)
  if (is.null(names(value))) {
    return(normalized)
  }
  names(normalized) <- names(value)
  normalized[order(names(normalized))]
}

resolved_proposal_validate_export_binding <- function(export, binding) {
  parsed <- tryCatch(
    jsonlite::fromJSON(binding$path, simplifyVector = FALSE),
    error = function(error) NULL
  )
  if (is.null(parsed)) {
    resolved_proposal_abort(
      "The host-bound export is not readable JSON.",
      "resolved_proposal_identity_error"
    )
  }
  if (
    !identical(
      resolved_proposal_json_normalize(parsed),
      resolved_proposal_json_normalize(export)
    )
  ) {
    resolved_proposal_abort(
      "The supplied raw export does not match the host-bound export bytes.",
      "resolved_proposal_identity_error"
    )
  }
}

resolved_proposal_validation <- function(validation, bindings) {
  if (is.null(validation)) {
    validation <- bindings$validation
  }
  if (!is.list(validation) || is.object(validation)) {
    resolved_proposal_abort(
      "A host data-validation observation is required; profiling is not validation.",
      "resolved_proposal_validation_error"
    )
  }
  if (
    !identical(validation$status, "pass") ||
      !identical(validation$level, "data") ||
      !identical(validation$profiling, FALSE)
  ) {
    resolved_proposal_abort(
      "Admission requires a successful data-validation observation, not profiling or spec validation.",
      "resolved_proposal_validation_error"
    )
  }
  validation
}

resolved_proposal_validate_export <- function(export) {
  if (!is.list(export) || is.object(export)) {
    resolved_proposal_abort(
      "The raw upstream export must be a JSON object.",
      "resolved_proposal_schema_error"
    )
  }
  if (!identical(export[["$version"]], resolved_proposal_export_version)) {
    resolved_proposal_abort(
      paste0(
        "Unsupported upstream export format; expected `$version` `",
        resolved_proposal_export_version,
        "`."
      ),
      "resolved_proposal_schema_error"
    )
  }
  tables <- resolved_proposal_records(export$tables, "export$tables")
  if (!length(tables)) {
    resolved_proposal_abort(
      "The raw upstream export must contain at least one table.",
      "resolved_proposal_schema_error"
    )
  }
  for (table_name in names(tables)) {
    table <- tables[[table_name]]
    columns <- resolved_proposal_records(
      table$columns,
      paste0("export table ", table_name, "$columns")
    )
    # This bounded fixture admits the scalar column types it exercises. Richer
    # nested types require an upstream typed contract, not a type-string parser.
    column_types <- c(
      resolved_proposal_types,
      "number(id)",
      "number(quantity)",
      "enum"
    )
    for (column in columns) {
      if (
        !is.character(column$type) ||
          length(column$type) != 1L ||
          !column$type %in% column_types
      ) {
        resolved_proposal_abort(
          paste0(
            "Column `",
            table_name,
            "$",
            column$name,
            "` needs a supported type."
          ),
          "resolved_proposal_type_error"
        )
      }
    }
    definitions <- resolved_proposal_records(
      table$definitions,
      paste0("export table ", table_name, "$definitions"),
      required = FALSE
    )
    if (anyDuplicated(c(names(columns), names(definitions)))) {
      resolved_proposal_abort(
        paste0(
          "Table `",
          table_name,
          "` has a column/definition name collision."
        ),
        "resolved_proposal_reference_error"
      )
    }
    for (definition_name in names(definitions)) {
      definition <- definitions[[definition_name]]
      resolved_proposal_text(
        definition$expression,
        paste0("definition ", table_name, "$", definition_name, "$expression")
      )
      kind <- resolved_proposal_text(
        definition$kind,
        paste0("definition ", table_name, "$", definition_name, "$kind")
      )
      if (!kind %in% c("filter", "metric", "derived")) {
        resolved_proposal_abort(
          paste0(
            "Definition `",
            table_name,
            "$",
            definition_name,
            "` has an unsupported kind."
          ),
          "resolved_proposal_type_error"
        )
      }
      if (
        !is.character(definition$type) ||
          length(definition$type) != 1L ||
          is.na(definition$type) ||
          !definition$type %in% resolved_proposal_types
      ) {
        resolved_proposal_abort(
          paste0(
            "Definition `",
            table_name,
            "$",
            definition_name,
            "` needs a supported typed `type`."
          ),
          "resolved_proposal_type_error"
        )
      }
      if (identical(kind, "filter") && !identical(definition$type, "boolean")) {
        resolved_proposal_abort(
          paste0(
            "Filter `",
            table_name,
            "$",
            definition_name,
            "` must have boolean type."
          ),
          "resolved_proposal_type_error"
        )
      }
      if (!is.null(definition$language)) {
        language <- resolved_proposal_text(
          definition$language,
          paste0("definition ", table_name, "$", definition_name, "$language")
        )
        if (
          !language %in% c("sql", "r", "python") ||
            is.null(definition$canonical)
        ) {
          resolved_proposal_abort(
            paste0(
              "Definition `",
              table_name,
              "$",
              definition_name,
              "` has incomplete language metadata."
            ),
            "resolved_proposal_translation_error"
          )
        }
        resolved_proposal_text(
          definition$canonical,
          paste0("definition ", table_name, "$", definition_name, "$canonical")
        )
      }
      if (!is.null(definition$fidelity)) {
        if (
          !is.character(definition$fidelity) ||
            length(definition$fidelity) != 1L ||
            is.na(definition$fidelity) ||
            !definition$fidelity %in%
              c("exact", "guarded", "divergent", "unsupported")
        ) {
          resolved_proposal_abort(
            paste0(
              "Definition `",
              table_name,
              "$",
              definition_name,
              "` has unsupported fidelity metadata."
            ),
            "resolved_proposal_translation_error"
          )
        }
      }
      column_refs <- resolved_proposal_names(
        definition$columns,
        paste0("definition ", table_name, "$", definition_name, "$columns")
      )
      missing_columns <- setdiff(column_refs, names(columns))
      if (length(missing_columns)) {
        resolved_proposal_abort(
          paste0(
            "Definition `",
            table_name,
            "$",
            definition_name,
            "` references missing columns: ",
            paste(missing_columns, collapse = ", "),
            "."
          ),
          "resolved_proposal_reference_error"
        )
      }
      refs <- resolved_proposal_names(
        definition$definitions,
        paste0("definition ", table_name, "$", definition_name, "$definitions")
      )
      missing_refs <- setdiff(refs, names(definitions))
      if (length(missing_refs)) {
        resolved_proposal_abort(
          paste0(
            "Definition `",
            table_name,
            "$",
            definition_name,
            "` references missing definitions: ",
            paste(missing_refs, collapse = ", "),
            "."
          ),
          "resolved_proposal_reference_error"
        )
      }
      translations <- definition$translations
      if (!is.list(translations) || !length(translations)) {
        resolved_proposal_abort(
          paste0(
            "Definition `",
            table_name,
            "$",
            definition_name,
            "` needs translations metadata."
          ),
          "resolved_proposal_translation_error"
        )
      }
      targets <- vapply(
        translations,
        function(translation) {
          if (!is.list(translation) || is.object(translation)) {
            resolved_proposal_abort(
              paste0(
                "Translations for `",
                table_name,
                "$",
                definition_name,
                "` must be objects."
              ),
              "resolved_proposal_translation_error"
            )
          }
          target <- resolved_proposal_text(
            translation$target,
            paste0(
              "translation for ",
              table_name,
              "$",
              definition_name,
              "$target"
            )
          )
          has_code <- !is.null(translation$code)
          has_error <- !is.null(translation$error)
          if (identical(has_code, has_error)) {
            resolved_proposal_abort(
              paste0(
                "Translation `",
                target,
                "` has exactly one of `code` or `error`."
              ),
              "resolved_proposal_translation_error"
            )
          }
          if (has_code) {
            resolved_proposal_text(translation$code, "translation code")
          } else {
            resolved_proposal_text(translation$error, "translation error")
          }
          if (!is.null(translation$notes)) {
            resolved_proposal_names(translation$notes, "translation notes")
          }
          target
        },
        character(1)
      )
      if (anyDuplicated(targets)) {
        resolved_proposal_abort(
          paste0(
            "Definition `",
            table_name,
            "$",
            definition_name,
            "` has duplicate translation targets."
          ),
          "resolved_proposal_translation_error"
        )
      }
    }
    graph <- lapply(definitions, function(definition) {
      resolved_proposal_names(definition$definitions, "definition dependencies")
    })
    names(graph) <- names(definitions)
    pending <- names(graph)
    resolved <- character()
    while (length(pending)) {
      ready <- pending[vapply(
        pending,
        function(name) {
          all(graph[[name]] %in% resolved)
        },
        logical(1)
      )]
      if (!length(ready)) {
        resolved_proposal_abort(
          paste0(
            "Definitions on table `",
            table_name,
            "` contain a cyclic dependency."
          ),
          "resolved_proposal_reference_error"
        )
      }
      resolved <- c(resolved, ready)
      pending <- setdiff(pending, ready)
    }
    tables[[table_name]]$columns <- columns
    tables[[table_name]]$definitions <- definitions
  }
  tables
}

resolved_proposal_grain <- function(grain, tables) {
  if (
    !is.list(grain) ||
      is.object(grain) ||
      !identical(grain$status, "proposed") ||
      !identical(grain$origin, "fixture-only")
  ) {
    resolved_proposal_abort(
      "Hand-authored grain metadata must be marked `status = \"proposed\"` and `origin = \"fixture-only\"`.",
      "resolved_proposal_metadata_error"
    )
  }
  proposed_tables <- grain$tables
  if (!is.list(proposed_tables) || is.null(names(proposed_tables))) {
    resolved_proposal_abort(
      "Proposed grain metadata must contain named table entries.",
      "resolved_proposal_metadata_error"
    )
  }
  table_names <- unname(vapply(tables, `[[`, character(1), "name"))
  if (!identical(sort(names(proposed_tables)), sort(table_names))) {
    resolved_proposal_abort(
      "Proposed grain metadata must cover exactly the exported tables.",
      "resolved_proposal_metadata_error"
    )
  }
  result <- vector("list", length(table_names))
  names(result) <- table_names
  for (table in tables) {
    table_name <- table$name
    definitions <- resolved_proposal_records(
      table$definitions,
      paste0("export table ", table_name, "$definitions"),
      required = FALSE
    )
    proposed <- proposed_tables[[table_name]]$definitions
    if (!is.list(proposed) || is.null(names(proposed))) {
      resolved_proposal_abort(
        paste0(
          "Proposed grain metadata for table `",
          table_name,
          "` needs named definitions."
        ),
        "resolved_proposal_metadata_error"
      )
    }
    if (!identical(sort(names(proposed)), sort(names(definitions)))) {
      resolved_proposal_abort(
        paste0(
          "Proposed grain metadata must cover exactly the definitions on table `",
          table_name,
          "`."
        ),
        "resolved_proposal_metadata_error"
      )
    }
    result[[table_name]] <- lapply(names(definitions), function(name) {
      entry <- proposed[[name]]
      if (
        !is.list(entry) ||
          is.null(entry$grain) ||
          !entry$grain %in% c("scalar", "row", "aggregate", "mixed")
      ) {
        resolved_proposal_abort(
          paste0(
            "Proposed grain for `",
            table_name,
            "$",
            name,
            "` is missing or unsupported."
          ),
          "resolved_proposal_metadata_error"
        )
      }
      if (
        !is.null(entry$value_type) &&
          !identical(entry$value_type, definitions[[name]]$type)
      ) {
        resolved_proposal_abort(
          paste0(
            "Proposed value type for `",
            table_name,
            "$",
            name,
            "` disagrees with the export type."
          ),
          "resolved_proposal_type_error"
        )
      }
      list(grain = entry$grain, value_type = entry$value_type)
    })
    names(result[[table_name]]) <- names(definitions)
  }
  list(status = "proposed", origin = "fixture-only", tables = result)
}

resolved_proposal_bindings <- function(bindings, table_names) {
  if (!is.list(bindings) || is.object(bindings)) {
    resolved_proposal_abort(
      "Host bindings must include dictionary, sources, export, and report.",
      "resolved_proposal_identity_error"
    )
  }
  sources <- bindings$sources
  if (
    is.null(bindings$dictionary) ||
      is.null(sources) ||
      is.null(bindings$export) ||
      is.null(bindings$report)
  ) {
    resolved_proposal_abort(
      "Host bindings must include `dictionary`, `sources`, `export`, and `report`.",
      "resolved_proposal_identity_error"
    )
  }
  if (
    !is.list(sources) ||
      is.null(names(sources)) ||
      !identical(sort(names(sources)), sort(table_names))
  ) {
    resolved_proposal_abort(
      "Host source bindings must cover exactly the exported tables.",
      "resolved_proposal_identity_error"
    )
  }
  list(
    dictionary = resolved_proposal_binding(
      bindings$dictionary,
      "host dictionary"
    ),
    sources = lapply(names(sources), function(name) {
      resolved_proposal_binding(
        sources[[name]],
        paste0("host source `", name, "`")
      )
    }) |>
      setNames(names(sources)),
    export = resolved_proposal_binding(bindings$export, "host export"),
    report = resolved_proposal_binding(bindings$report, "host report")
  )
}

resolved_proposal_translation <- function(definition, target, table, name) {
  matches <- vapply(
    definition$translations,
    function(translation) {
      identical(translation$target, target)
    },
    logical(1)
  )
  if (!any(matches)) {
    resolved_proposal_abort(
      paste0(
        "Definition `",
        table,
        "$",
        name,
        "` has no `",
        target,
        "` translation."
      ),
      "resolved_proposal_translation_error"
    )
  }
  translation <- definition$translations[[which(matches)[[1L]]]]
  if (!is.null(translation$error)) {
    resolved_proposal_abort(
      paste0(
        "Definition `",
        table,
        "$",
        name,
        "` refuses backend `",
        target,
        "`: ",
        translation$error
      ),
      "resolved_proposal_translation_error"
    )
  }
  translation
}

resolved_proposal_admit <- function(
  export,
  grain,
  bindings,
  backend = "duckdb",
  validation = NULL
) {
  tables <- resolved_proposal_validate_export(export)
  grain_map <- resolved_proposal_grain(grain, tables)
  identity <- resolved_proposal_bindings(bindings, names(tables))
  resolved_proposal_validate_export_binding(export, identity$export)
  validation <- resolved_proposal_validation(validation, bindings)
  target <- if (identical(backend, "duckdb")) "SQL(duckdb)" else backend
  if (!identical(target, "SQL(duckdb)")) {
    resolved_proposal_abort(
      paste0(
        "Unsupported proposed backend target `",
        target,
        "`; only `SQL(duckdb)` is supported."
      ),
      "resolved_proposal_backend_error"
    )
  }
  for (table_name in names(tables)) {
    definitions <- tables[[table_name]]$definitions
    for (name in names(definitions)) {
      definition <- definitions[[name]]
      resolved_proposal_translation(definition, target, table_name, name)
      proposed <- grain_map$tables[[table_name]][[name]]
      if (identical(proposed$grain, "mixed")) {
        resolved_proposal_abort(
          paste0(
            "Mixed-grain definition `",
            table_name,
            "$",
            name,
            "` is not admitted."
          ),
          "resolved_proposal_grain_error"
        )
      }
      if (
        proposed$grain %in%
          c("scalar", "aggregate") &&
          !identical(definition$kind, "metric")
      ) {
        resolved_proposal_abort(
          paste0(
            "Metric-grain definition `",
            table_name,
            "$",
            name,
            "` must retain kind `metric`."
          ),
          "resolved_proposal_grain_error"
        )
      }
      if (
        identical(proposed$grain, "row") &&
          !definition$kind %in% c("filter", "derived")
      ) {
        resolved_proposal_abort(
          paste0(
            "Row definition `",
            table_name,
            "$",
            name,
            "` has an incompatible kind."
          ),
          "resolved_proposal_grain_error"
        )
      }
      if (
        identical(proposed$grain, "row") &&
          identical(definition$kind, "filter") &&
          !identical(definition$type, "boolean")
      ) {
        resolved_proposal_abort(
          paste0(
            "Filter `",
            table_name,
            "$",
            name,
            "` must have boolean type."
          ),
          "resolved_proposal_type_error"
        )
      }
    }
  }
  proposal_tables <- tables
  for (table_name in names(proposal_tables)) {
    definitions <- proposal_tables[[table_name]]$definitions
    for (name in names(definitions)) {
      definitions[[name]]$grain <- grain_map$tables[[table_name]][[name]]$grain
      definitions[[name]]$proposed_metadata <- grain_map$tables[[table_name]][[
        name
      ]]
    }
    proposal_tables[[table_name]]$definitions <- definitions
  }
  list(
    schema = resolved_proposal_schema,
    status = "proposed",
    format = resolved_proposal_export_version,
    executable = FALSE,
    composition = "unavailable-in-current-export",
    backend = list(name = "duckdb", target = target),
    identity = identity,
    validation = validation,
    export = export,
    grain = grain_map,
    tables = proposal_tables
  )
}

resolved_proposal_request <- function(
  proposal,
  metrics = character(),
  dimensions = character(),
  filters = character(),
  table = NULL
) {
  if (
    !is.list(proposal) ||
      !identical(proposal$status, "proposed") ||
      !identical(proposal$executable, FALSE)
  ) {
    resolved_proposal_abort(
      "`proposal` must be an admitted non-executable proposed record.",
      "resolved_proposal_request_error"
    )
  }
  tables <- proposal$tables
  if (is.null(table)) {
    if (length(tables) != 1L) {
      resolved_proposal_abort(
        "A table is required when a proposal contains multiple tables.",
        "resolved_proposal_request_error"
      )
    }
    table <- names(tables)[[1L]]
  }
  table <- resolved_proposal_text(table, "table")
  if (is.null(tables[[table]])) {
    resolved_proposal_abort(
      paste0("Unknown proposal table `", table, "`."),
      "resolved_proposal_request_error"
    )
  }
  metrics <- resolved_proposal_names(metrics, "metrics")
  dimensions <- resolved_proposal_names(dimensions, "dimensions")
  filters <- resolved_proposal_names(filters, "filters")
  requested <- c(metrics, dimensions, filters)
  if (!length(requested) || anyDuplicated(requested)) {
    resolved_proposal_abort(
      "A request must select unique metric, dimension, or filter names.",
      "resolved_proposal_request_error"
    )
  }
  definitions <- tables[[table]]$definitions
  missing <- setdiff(requested, names(definitions))
  if (length(missing)) {
    resolved_proposal_abort(
      paste0(
        "Request references missing definitions: ",
        paste(missing, collapse = ", "),
        "."
      ),
      "resolved_proposal_request_error"
    )
  }
  roles <- c(
    setNames(rep("metric", length(metrics)), metrics),
    setNames(rep("dimension", length(dimensions)), dimensions),
    setNames(rep("filter", length(filters)), filters)
  )
  for (name in requested) {
    definition <- definitions[[name]]
    if (identical(definition$grain, "mixed")) {
      resolved_proposal_abort(
        paste0("Mixed-grain definition `", table, "$", name, "` is refused."),
        "resolved_proposal_grain_error"
      )
    }
    role <- roles[[name]]
    valid <- if (identical(role, "metric")) {
      definition$grain %in%
        c("scalar", "aggregate") &&
        identical(definition$kind, "metric")
    } else if (identical(role, "dimension")) {
      identical(definition$grain, "row") &&
        identical(definition$kind, "derived")
    } else {
      identical(definition$grain, "row") &&
        identical(definition$kind, "filter") &&
        identical(definition$type, "boolean")
    }
    if (!valid) {
      label <- if (identical(role, "metric")) {
        "scalar or aggregate metric"
      } else if (identical(role, "dimension")) {
        "row-grain dimension"
      } else {
        "row-grain boolean filter"
      }
      resolved_proposal_abort(
        paste0("Definition `", table, "$", name, "` is not a ", label, "."),
        "resolved_proposal_role_error"
      )
    }
    resolved_proposal_translation(
      definition,
      proposal$backend$target,
      table,
      name
    )
  }
  closure <- character()
  visit <- function(name) {
    if (name %in% closure) {
      return(invisible(NULL))
    }
    for (dependency in resolved_proposal_names(
      definitions[[name]]$definitions,
      "dependencies"
    )) {
      visit(dependency)
    }
    closure <<- c(closure, name)
    invisible(NULL)
  }
  for (name in requested) {
    visit(name)
  }
  list(
    schema = resolved_proposal_schema,
    status = "proposed",
    executable = FALSE,
    composition = "unavailable-in-current-export",
    table = table,
    backend = proposal$backend,
    roles = list(metrics = metrics, dimensions = dimensions, filters = filters),
    dependency_closure = closure,
    definitions = definitions[closure],
    identity = proposal$identity,
    validation = proposal$validation
  )
}
