#' List accepted definitions
#'
#' `graft_definitions()` returns the composable metric, filter, and derived
#' definitions accepted into the store. A `GraftView` lists only definitions
#' accepted at its pinned boundary.
#'
#' @param source An initialized `GraftStore` or immutable `GraftView`.
#' @param target Optional public-table name used to filter the catalog.
#'
#' @return A bounded data frame with one row per accepted definition and
#'   list-columns for direct dependencies and eligible public columns.
#' @export
graft_definitions <- function(source, target = NULL) {
  source <- as_graft_read_store_internal(source, "source")
  definition_catalog(source, target)
}

definition_catalog <- function(source, target = NULL, bounded = TRUE) {
  validate_graft_retrieval(source)
  if (!is.null(target)) {
    target <- validate_scalar_text(target, "target")
    definition_target_contract(source$schema$manifest, target)
  }
  limit <- graft_retrieval_limits$definitions
  rows <- definition_current_rows(
    source,
    targets = target,
    limit = if (bounded) limit else NULL
  )
  if (nrow(rows) == 0L) {
    result <- empty_definition_catalog()
    if (bounded) {
      return(trim_bounded_rows(result, source, limit))
    }
    return(result)
  }
  payloads <- lapply(
    rows$payload_json,
    jsonlite::fromJSON,
    simplifyVector = FALSE
  )
  catalog <- lapply(seq_len(nrow(rows)), function(index) {
    payload <- payloads[[index]]
    data.frame(
      id = rows$record_id[[index]],
      revision_id = rows$revision_id[[index]],
      name = scalar_character(payload$name),
      target = scalar_character(payload$target),
      expr = scalar_character(payload$expr),
      label = scalar_character(payload$label),
      description = scalar_character(payload$description),
      details = scalar_character(payload$details),
      stringsAsFactors = FALSE
    )
  }) |>
    dplyr::bind_rows()
  analyses <- definition_catalog_analyses(source, catalog)
  catalog$kind <- vapply(analyses, `[[`, character(1), "kind")
  catalog$dependencies <- lapply(analyses, `[[`, "dependencies")
  catalog$columns <- lapply(catalog$target, function(target_name) {
    definition_public_scalar_columns(definition_target_contract(
      source$schema$manifest,
      target_name
    ))
  })
  catalog <- catalog[
    c(
      "id",
      "revision_id",
      "name",
      "target",
      "kind",
      "expr",
      "label",
      "description",
      "details",
      "dependencies",
      "columns"
    )
  ]
  catalog <- catalog[
    order(catalog$target, catalog$name, method = "radix"),
    ,
    drop = FALSE
  ]
  if (bounded) {
    return(trim_bounded_rows(catalog, source, limit))
  }
  rownames(catalog) <- NULL
  catalog
}

definition_current_rows <- function(
  source,
  targets = NULL,
  names = NULL,
  limit = NULL
) {
  where <- "class = ?"
  params <- list(graft_definition_class_name)
  add_payload_filter <- function(field, values) {
    values <- unique(as.character(values))
    if (length(values) == 0L) {
      return(FALSE)
    }
    fragments <- vapply(
      values,
      \(value) paste0('"', field, '":', canonical_json(value)),
      ""
    )
    where <<- c(
      where,
      paste0(
        "(",
        paste(
          rep("strpos(payload_json, ?) > 0", length(values)),
          collapse = " OR "
        ),
        ")"
      )
    )
    params <<- c(params, unname(as.list(fragments)))
    TRUE
  }
  if (!is.null(targets) && !add_payload_filter("target", targets)) {
    return(data.frame())
  }
  if (!is.null(names) && !add_payload_filter("name", names)) {
    return(data.frame())
  }
  limit_sql <- if (is.null(limit)) {
    ""
  } else {
    paste0(" LIMIT ", limit + 1L)
  }
  retrieval_query(
    source$connection,
    paste0(
      "SELECT * FROM (",
      graft_read_source_sql(source),
      ") definitions WHERE ",
      paste(where, collapse = " AND "),
      " ORDER BY class, record_id, revision_id",
      limit_sql
    ),
    params = params
  )
}

definition_catalog_analyses <- function(source, catalog) {
  analyses <- vector("list", nrow(catalog))
  for (target in unique(catalog$target)) {
    indexes <- which(catalog$target == target)
    contract <- definition_target_contract(source$schema$manifest, target)
    columns <- definition_public_scalar_columns(contract)
    compiler <- new.env(parent = emptyenv())
    compiler$catalog <- catalog[indexes, , drop = FALSE]
    compiler$columns <- columns
    compiler$target <- target
    compiler$compiled <- list()
    compiler$active <- character()
    source_sql <- definition_empty_source_sql(source$connection, contract)
    shapes <- stats::setNames(
      rep(NA_character_, length(indexes)),
      catalog$id[indexes]
    )
    analyze <- function(index) {
      id <- catalog$id[[index]]
      if (!is.na(shapes[[id]])) {
        return(analyses[[index]])
      }
      basic <- definition_expr_analyze(
        catalog$expr[[index]],
        columns,
        catalog$name[indexes]
      )
      if (nrow(basic$issues) > 0L) {
        abort_backend_error(
          "An accepted definition no longer compiles.",
          operation = "definition_catalog",
          definition_id = id,
          issues = basic$issues
        )
      }
      dependency_shapes <- vapply(
        basic$dependencies,
        function(name) {
          dependency <- indexes[catalog$name[indexes] == name]
          if (length(dependency) != 1L) {
            abort_backend_error(
              "An accepted definition dependency is missing or ambiguous.",
              operation = "definition_catalog",
              definition_id = id,
              dependency = name
            )
          }
          analyze(dependency)
          shapes[[catalog$id[[dependency]]]]
        },
        character(1)
      )
      shape <- if (
        basic$has_aggregate ||
          any(dependency_shapes == "aggregate")
      ) {
        "aggregate"
      } else if (
        basic$has_row_reference ||
          any(dependency_shapes == "row")
      ) {
        "row"
      } else {
        "constant"
      }
      compiled <- tryCatch(
        definition_compile_row(catalog[index, , drop = FALSE], compiler),
        error = function(error) {
          abort_backend_error(
            "An accepted definition no longer compiles.",
            operation = "definition_catalog",
            definition_id = id,
            parent = error
          )
        }
      )
      type <- tryCatch(
        definition_describe_sql(source$connection, compiled$sql, source_sql),
        error = function(error) {
          abort_backend_error(
            "An accepted definition no longer type-checks.",
            operation = "definition_catalog",
            definition_id = id,
            parent = error
          )
        }
      )
      basic$kind <- if (shape %in% c("aggregate", "constant")) {
        "metric"
      } else if (grepl("^BOOLEAN", toupper(type))) {
        "filter"
      } else {
        "derived"
      }
      shapes[[id]] <<- shape
      analyses[[index]] <<- basic
      basic
    }
    for (index in indexes) {
      analyze(index)
    }
  }
  analyses
}

definition_target_contract <- function(manifest, target) {
  contract <- definition_target_contract_or_null(manifest, target)
  if (is.null(contract)) {
    abort_validation_error(
      paste0("Unknown public definition target `", target, "`."),
      field = "target",
      rule = "definition_target",
      observed_value = target
    )
  }
  contract
}

empty_definition_catalog <- function() {
  result <- data.frame(
    id = character(),
    revision_id = character(),
    name = character(),
    target = character(),
    kind = character(),
    expr = character(),
    label = character(),
    description = character(),
    details = character(),
    stringsAsFactors = FALSE
  )
  result$dependencies <- list()
  result$columns <- list()
  result
}

abort_calculation_error <- function(message, ..., call = rlang::caller_env()) {
  graft_abort(
    "graft_calculation_error",
    message,
    ...,
    call = call
  )
}

#' Evaluate accepted definitions
#'
#' `graft_calculate()` composes accepted metrics with same-table dimensions,
#' filters, and simple predicates over current accepted state or the immutable
#' boundary of a `GraftView`.
#'
#' @param source An initialized `GraftStore` or immutable `GraftView`.
#' @param metrics One or more accepted metric names.
#' @param dimensions Optional public columns or accepted derived definitions.
#' @param filters Optional accepted filter definitions.
#' @param where Optional list of simple `column`, `op`, and string `value`
#'   predicates combined with AND.
#'
#' @return A data frame with dimensions followed by metrics in request order.
#' @export
graft_calculate <- function(
  source,
  metrics,
  dimensions = NULL,
  filters = NULL,
  where = NULL
) {
  read_source <- as_graft_read_store_internal(source, "source")
  validate_graft_retrieval(read_source)
  if (!is_graft_snapshot_backend(read_source)) {
    read_source <- as_graft_read_store_internal(
      graft_at(source, graft_snapshot(source)),
      "source"
    )
  }
  metrics <- definition_name_argument(metrics, "metrics", required = TRUE)
  dimensions <- definition_name_argument(dimensions, "dimensions")
  filters <- definition_name_argument(filters, "filters")
  catalog <- definition_calculation_catalog(read_source, metrics)
  selected_metrics <- definition_resolve_many(
    catalog,
    metrics,
    kind = "metric",
    argument = "metrics"
  )
  targets <- unique(selected_metrics$target)
  if (length(targets) != 1L) {
    abort_calculation_error(
      "All requested metrics must target the same public table.",
      field = "metrics",
      rule = "calculation_single_target",
      observed_value = targets
    )
  }
  target <- targets[[1L]]
  contract <- definition_target_contract(read_source$schema$manifest, target)
  columns <- definition_public_scalar_columns(contract)
  selected_filters <- definition_resolve_many(
    catalog,
    filters,
    kind = "filter",
    target = target,
    argument = "filters"
  )
  selected_dimensions <- definition_resolve_dimensions(
    catalog,
    dimensions,
    target,
    columns
  )
  compiler <- new.env(parent = emptyenv())
  compiler$catalog <- catalog
  compiler$columns <- columns
  compiler$target <- target
  compiler$compiled <- list()
  compiler$active <- character()
  metric_code <- lapply(
    seq_len(nrow(selected_metrics)),
    \(index) definition_compile_row(selected_metrics[index, ], compiler)
  )
  filter_code <- lapply(
    seq_len(nrow(selected_filters)),
    \(index) definition_compile_row(selected_filters[index, ], compiler)
  )
  dimension_code <- lapply(selected_dimensions, function(dimension) {
    if (identical(dimension$kind, "column")) {
      return(list(
        sql = as.character(quote_identifier(
          read_source$connection,
          dimension$name
        )),
        definition_ids = character()
      ))
    }
    definition_compile_row(dimension$row, compiler)
  })
  where <- definition_where_predicates(
    where,
    contract,
    read_source$schema$manifest
  )
  frame <- definition_target_frame(read_source, contract, typed = FALSE)
  view_name <- "_graft_definition_target"
  duckdb::duckdb_register(read_source$connection, view_name, frame)
  on.exit(
    duckdb::duckdb_unregister(read_source$connection, view_name),
    add = TRUE
  )
  source_sql <- definition_target_source_sql(
    read_source$connection,
    view_name,
    contract
  )
  dimension_select <- Map(
    function(dimension, code) {
      paste0(
        code$sql,
        " AS ",
        quote_identifier(read_source$connection, dimension$name)
      )
    },
    selected_dimensions,
    dimension_code
  )
  metric_select <- Map(
    function(index, code) {
      paste0(
        code$sql,
        " AS ",
        quote_identifier(
          read_source$connection,
          selected_metrics$name[[index]]
        )
      )
    },
    seq_len(nrow(selected_metrics)),
    metric_code
  )
  predicates <- c(
    vapply(filter_code, `[[`, character(1), "sql"),
    where$sql
  )
  grouped <- vapply(dimension_code, `[[`, character(1), "sql")
  limit <- graft_retrieval_limits$calculation_rows
  query <- paste0(
    "SELECT ",
    paste(c(dimension_select, metric_select), collapse = ", "),
    " FROM ",
    "(",
    source_sql,
    ") definition_target",
    if (length(predicates) > 0L) {
      paste0(" WHERE ", paste0("(", predicates, ")", collapse = " AND "))
    } else {
      ""
    },
    if (length(grouped) > 0L) {
      paste0(
        " GROUP BY ",
        paste(grouped, collapse = ", "),
        " ORDER BY ",
        paste(grouped, collapse = ", ")
      )
    } else {
      " HAVING COUNT(*) >= 0"
    },
    " LIMIT ",
    limit + 1L
  )
  result <- tryCatch(
    retrieval_query(read_source$connection, query, params = where$params),
    error = function(error) {
      abort_calculation_error(
        "The accepted calculation could not be evaluated.",
        rule = "calculation_execution",
        parent = error
      )
    }
  )
  if (nrow(result) > limit) {
    abort_calculation_error(
      paste0(
        "The grouped calculation exceeds the hard row bound of ",
        limit,
        "."
      ),
      rule = "calculation_row_bound",
      limit = limit
    )
  }
  definition_ids <- unique(c(
    unlist(lapply(metric_code, `[[`, "definition_ids"), use.names = FALSE),
    unlist(lapply(filter_code, `[[`, "definition_ids"), use.names = FALSE),
    unlist(lapply(dimension_code, `[[`, "definition_ids"), use.names = FALSE)
  ))
  receipt_definitions <- catalog[
    match(definition_ids, catalog$id),
    c("id", "revision_id", "kind"),
    drop = FALSE
  ]
  receipt_definitions <- receipt_definitions[
    order(receipt_definitions$id, method = "radix"),
    ,
    drop = FALSE
  ]
  rownames(result) <- NULL
  attr(result, "definitions") <- receipt_definitions
  attr(result, "store_schema_digest") <- store_schema_digest(read_source)
  result
}

definition_name_argument <- function(value, argument, required = FALSE) {
  if (is.null(value)) {
    value <- character()
  }
  if (is.factor(value)) {
    value <- as.character(value)
  }
  valid <- is.character(value) &&
    !anyNA(value) &&
    all(nzchar(value)) &&
    !anyDuplicated(value)
  if (!valid || (required && length(value) == 0L)) {
    abort_calculation_error(
      paste0(
        "`",
        argument,
        "` must contain ",
        if (required) "one or more " else "unique ",
        "non-empty definition names."
      ),
      field = argument,
      rule = "calculation_names",
      observed_value = value
    )
  }
  value
}

definition_calculation_catalog <- function(source, references) {
  selectors <- lapply(
    references,
    definition_reference_parts,
    argument = "metrics"
  )
  rows <- definition_current_rows(
    source,
    names = unique(vapply(selectors, `[[`, character(1), "name"))
  )
  if (nrow(rows) == 0L) {
    return(empty_definition_catalog())
  }
  payloads <- lapply(
    rows$payload_json,
    jsonlite::fromJSON,
    simplifyVector = FALSE
  )
  candidates <- data.frame(
    target = vapply(payloads, \(payload) scalar_character(payload$target), ""),
    name = vapply(payloads, \(payload) scalar_character(payload$name), ""),
    stringsAsFactors = FALSE
  )
  matched <- vapply(
    seq_len(nrow(candidates)),
    function(index) {
      any(vapply(
        selectors,
        function(selector) {
          identical(selector$name, candidates$name[[index]]) &&
            (is.null(selector$target) ||
              identical(selector$target, candidates$target[[index]]))
        },
        logical(1)
      ))
    },
    logical(1)
  )
  targets <- sort(unique(candidates$target[matched]), method = "radix")
  if (length(targets) == 0L) {
    return(empty_definition_catalog())
  }
  catalogs <- lapply(
    targets,
    \(target) definition_catalog(source, target, bounded = FALSE)
  )
  catalog <- dplyr::bind_rows(catalogs)
  catalog[
    order(catalog$target, catalog$name, method = "radix"),
    ,
    drop = FALSE
  ]
}

definition_reference_parts <- function(reference, argument) {
  parts <- strsplit(reference, "::", fixed = TRUE)[[1L]]
  if (length(parts) > 2L || !all(nzchar(parts))) {
    abort_calculation_error(
      paste0("Invalid definition reference `", reference, "`."),
      field = argument,
      rule = "definition_reference",
      observed_value = reference
    )
  }
  list(
    target = if (length(parts) == 2L) parts[[1L]] else NULL,
    name = if (length(parts) == 2L) parts[[2L]] else parts[[1L]]
  )
}

definition_resolve_many <- function(
  catalog,
  references,
  kind,
  target = NULL,
  argument
) {
  if (length(references) == 0L) {
    return(catalog[integer(), , drop = FALSE])
  }
  rows <- lapply(references, function(reference) {
    definition_resolve_one(
      catalog,
      reference,
      kind = kind,
      target = target,
      argument = argument
    )
  })
  dplyr::bind_rows(rows)
}

definition_resolve_one <- function(
  catalog,
  reference,
  kind,
  target = NULL,
  argument
) {
  parts <- definition_reference_parts(reference, argument)
  qualified_target <- parts$target
  name <- parts$name
  if (
    !is.null(target) &&
      !is.null(qualified_target) &&
      !identical(target, qualified_target)
  ) {
    abort_calculation_error(
      paste0("Definition `", reference, "` does not target `", target, "`."),
      field = argument,
      rule = "calculation_single_target",
      observed_value = reference
    )
  }
  candidates <- catalog[catalog$name == name, , drop = FALSE]
  effective_target <- if (!is.null(qualified_target)) {
    qualified_target
  } else {
    target
  }
  if (!is.null(effective_target)) {
    candidates <- candidates[
      candidates$target == effective_target,
      ,
      drop = FALSE
    ]
  }
  if (nrow(candidates) == 0L) {
    abort_calculation_error(
      paste0("No accepted definition resolves `", reference, "`."),
      field = argument,
      rule = "definition_exists",
      observed_value = reference
    )
  }
  if (nrow(candidates) > 1L) {
    abort_calculation_error(
      paste0(
        "Definition `",
        reference,
        "` is ambiguous; qualify it as `target::name`."
      ),
      field = argument,
      rule = "definition_ambiguous",
      observed_value = reference
    )
  }
  if (!identical(candidates$kind[[1L]], kind)) {
    abort_calculation_error(
      paste0(
        "Definition `",
        reference,
        "` is `",
        candidates$kind[[1L]],
        "`, not `",
        kind,
        "`."
      ),
      field = argument,
      rule = "definition_kind",
      observed_value = candidates$kind[[1L]],
      expected_value = kind
    )
  }
  candidates
}

definition_resolve_dimensions <- function(
  catalog,
  dimensions,
  target,
  columns
) {
  lapply(dimensions, function(reference) {
    if (!grepl("::", reference, fixed = TRUE) && reference %in% columns) {
      return(list(name = reference, kind = "column", row = NULL))
    }
    row <- definition_resolve_one(
      catalog,
      reference,
      kind = "derived",
      target = target,
      argument = "dimensions"
    )
    list(name = row$name[[1L]], kind = "derived", row = row)
  })
}

definition_compile_row <- function(row, compiler) {
  id <- row$id[[1L]]
  cached <- compiler$compiled[[id]]
  if (!is.null(cached)) {
    return(cached)
  }
  if (id %in% compiler$active) {
    abort_calculation_error(
      "An accepted definition dependency cycle reached evaluation.",
      rule = "definition_cycle",
      definition_id = id
    )
  }
  compiler$active <- c(compiler$active, id)
  on.exit(
    {
      compiler$active <- setdiff(compiler$active, id)
    },
    add = TRUE
  )
  local_names <- compiler$catalog$name[
    compiler$catalog$target == compiler$target
  ]
  analysis <- definition_expr_analyze(
    row$expr[[1L]],
    compiler$columns,
    local_names
  )
  if (nrow(analysis$issues) > 0L) {
    abort_calculation_error(
      "An accepted definition no longer compiles; this indicates a Graft bug.",
      rule = "definition_integrity",
      definition_id = id,
      issues = analysis$issues
    )
  }
  sql <- analysis$sql
  definition_ids <- id
  for (dependency in analysis$dependencies) {
    dependency_row <- compiler$catalog[
      compiler$catalog$target == compiler$target &
        compiler$catalog$name == dependency,
      ,
      drop = FALSE
    ]
    if (nrow(dependency_row) != 1L) {
      abort_calculation_error(
        paste0("Accepted definition dependency `", dependency, "` is missing."),
        rule = "definition_dependency",
        definition_id = id,
        dependency = dependency
      )
    }
    compiled <- definition_compile_row(dependency_row, compiler)
    sql <- gsub(
      definition_sql_identifier(dependency),
      paste0("(", compiled$sql, ")"),
      sql,
      fixed = TRUE
    )
    definition_ids <- c(definition_ids, compiled$definition_ids)
  }
  result <- list(sql = sql, definition_ids = unique(definition_ids))
  compiler$compiled[[id]] <- result
  result
}

definition_sql_identifier <- function(name) {
  paste0('"', gsub('"', '""', name, fixed = TRUE), '"')
}

definition_where_predicates <- function(where, contract, manifest) {
  if (is.null(where)) {
    return(list(sql = character(), params = list()))
  }
  if (!is.list(where) || is.data.frame(where)) {
    abort_calculation_error(
      "`where` must be a list of predicate objects.",
      field = "where",
      rule = "calculation_where"
    )
  }
  sql <- character()
  params <- list()
  for (index in seq_along(where)) {
    predicate <- where[[index]]
    if (
      !is.list(predicate) ||
        is.object(predicate) ||
        length(names(predicate)) != 3L ||
        !setequal(names(predicate), c("column", "op", "value")) ||
        !is_nonempty_string(predicate$column) ||
        !is_nonempty_string(predicate$op) ||
        !is.character(predicate$value) ||
        length(predicate$value) != 1L ||
        is.na(predicate$value)
    ) {
      abort_calculation_error(
        "Every `where` predicate needs string `column`, `op`, and `value` fields.",
        field = "where",
        rule = "calculation_where",
        predicate_index = index
      )
    }
    if (!predicate$op %in% c("=", "!=", "<", "<=", ">", ">=")) {
      abort_calculation_error(
        paste0("Unsupported `where` operator `", predicate$op, "`."),
        field = "where",
        rule = "calculation_where_operator",
        predicate_index = index
      )
    }
    slot <- contract$slots[[predicate$column]]
    if (
      is.null(slot) ||
        !predicate$column %in% definition_public_scalar_columns(contract)
    ) {
      abort_calculation_error(
        paste0("Unknown public predicate column `", predicate$column, "`."),
        field = "where",
        rule = "calculation_where_column",
        predicate_index = index
      )
    }
    sql <- c(
      sql,
      paste0(
        '"',
        gsub('"', '""', predicate$column, fixed = TRUE),
        '" ',
        predicate$op,
        " ?"
      )
    )
    params <- c(
      params,
      list(definition_where_value(predicate$value, slot, manifest))
    )
  }
  list(sql = sql, params = params)
}

definition_where_value <- function(value, slot, manifest) {
  enum <- scalar_character(slot$enum)
  if (!is.na(enum)) {
    permissible <- vapply(
      manifest$enums[[enum]]$permissible_values,
      \(item) scalar_character(item$value),
      character(1)
    )
    if (!value %in% permissible) {
      abort_calculation_error(
        paste0("Predicate value `", value, "` is not in enum `", enum, "`."),
        field = "where",
        rule = "calculation_where_value",
        observed_value = value,
        expected_type = enum
      )
    }
    return(value)
  }
  type <- toupper(scalar_character(slot$duckdb_type, "VARCHAR"))
  converted <- switch(
    type,
    DOUBLE = definition_where_number(value),
    FLOAT = definition_where_number(value),
    DECIMAL = definition_where_number(value),
    BIGINT = definition_where_integer(value, type),
    INTEGER = definition_where_integer(value, type),
    BOOLEAN = if (tolower(value) %in% c("true", "false")) {
      identical(tolower(value), "true")
    } else {
      NA
    },
    DATE = definition_where_date(value),
    TIME = definition_where_time(value),
    TIMESTAMP = definition_where_timestamp(value),
    value
  )
  if (
    length(converted) != 1L ||
      is.na(converted) ||
      (is.numeric(converted) && !is.finite(converted))
  ) {
    abort_calculation_error(
      paste0("Predicate value `", value, "` is invalid for `", type, "`."),
      field = "where",
      rule = "calculation_where_value",
      observed_value = value,
      expected_type = type
    )
  }
  converted
}

definition_where_date <- function(value) {
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value)) {
    return(as.Date(NA))
  }
  parsed <- tryCatch(
    suppressWarnings(as.Date(value)),
    error = \(condition) as.Date(NA)
  )
  if (is.na(parsed) || !identical(format(parsed, "%Y-%m-%d"), value)) {
    return(as.Date(NA))
  }
  parsed
}

definition_where_time <- function(value) {
  if (
    !grepl(
      "^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?$",
      value
    )
  ) {
    return(NA_character_)
  }
  value
}

definition_where_timestamp <- function(value) {
  pattern <- paste0(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ]",
    "[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?",
    "([Zz]|[+-][0-9]{2}:[0-9]{2})?$"
  )
  if (!grepl(pattern, value)) {
    return(as.POSIXct(NA, tz = "UTC"))
  }
  normalized <- sub("[Tt ]", "T", value)
  normalized <- sub("[Zz]$", "+0000", normalized)
  normalized <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", normalized)
  format <- if (grepl("[+-][0-9]{4}$", normalized)) {
    "%Y-%m-%dT%H:%M:%OS%z"
  } else {
    "%Y-%m-%dT%H:%M:%OS"
  }
  suppressWarnings(as.POSIXct(normalized, format = format, tz = "UTC"))
}

definition_where_number <- function(value) {
  if (!grepl("^[+-]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?$", value)) {
    return(NA_character_)
  }
  value
}

definition_where_integer <- function(value, type) {
  if (!grepl("^[+-]?[0-9]+$", value)) {
    return(NA_character_)
  }
  negative <- startsWith(value, "-")
  digits <- sub("^[+-]", "", value)
  digits <- sub("^0+", "", digits)
  if (!nzchar(digits)) {
    digits <- "0"
  }
  limit <- switch(
    type,
    INTEGER = if (negative) "2147483648" else "2147483647",
    BIGINT = if (negative) "9223372036854775808" else "9223372036854775807"
  )
  if (
    nchar(digits) > nchar(limit) ||
      (nchar(digits) == nchar(limit) && digits > limit)
  ) {
    return(NA_character_)
  }
  value
}

definition_target_frame <- function(source, contract, typed = TRUE) {
  relation <- contract[["relation", exact = TRUE]]
  if (!is.null(relation)) {
    frame <- commons_relation_frame(source, relation)
    if (!typed) {
      frame[] <- lapply(frame, as.character)
    }
    return(frame)
  }
  rows <- retrieval_query(
    source$connection,
    paste0(
      "SELECT payload_json FROM (",
      graft_read_source_sql(source),
      ") definition_source WHERE class = ?"
    ),
    params = list(scalar_character(contract$name))
  )
  columns <- definition_public_scalar_columns(contract)
  payloads <- lapply(
    rows$payload_json,
    jsonlite::fromJSON,
    simplifyVector = FALSE,
    bigint_as_char = !typed
  )
  values <- lapply(columns, function(column) {
    slot <- contract$slots[[column]]
    raw <- lapply(payloads, \(payload) payload[[column]])
    definition_column_values(
      raw,
      scalar_character(slot$duckdb_type),
      typed = typed
    )
  })
  stats::setNames(data.frame(values, stringsAsFactors = FALSE), columns)
}

definition_column_values <- function(raw, duckdb_type, typed = TRUE) {
  scalars <- vapply(
    raw,
    function(value) {
      if (is.null(value) || length(value) != 1L) {
        NA_character_
      } else {
        as.character(value)
      }
    },
    character(1)
  )
  if (!typed) {
    return(scalars)
  }
  type <- toupper(duckdb_type)
  if (type %in% c("DOUBLE", "FLOAT", "DECIMAL", "BIGINT", "INTEGER")) {
    return(suppressWarnings(as.numeric(scalars)))
  }
  if (identical(type, "BOOLEAN")) {
    return(as.logical(scalars))
  }
  if (identical(type, "DATE")) {
    return(as.Date(scalars))
  }
  if (identical(type, "TIMESTAMP")) {
    return(as.POSIXct(scalars, tz = "UTC"))
  }
  scalars
}

definition_target_source_sql <- function(connection, view_name, contract) {
  columns <- definition_public_scalar_columns(contract)
  selections <- vapply(
    columns,
    function(column) {
      identifier <- quote_identifier(connection, column)
      type <- safe_duckdb_type(scalar_character(
        contract$slots[[column]]$duckdb_type
      ))
      paste0("CAST(", identifier, " AS ", type, ") AS ", identifier)
    },
    character(1)
  )
  paste0(
    "SELECT ",
    paste(selections, collapse = ", "),
    " FROM ",
    quote_identifier(connection, view_name)
  )
}
