#' List accepted measures
#'
#' `graft_measures()` returns the measure definitions accepted into the
#' store: governed, named calculations that evaluate over accepted state.
#' A `GraftView` lists only measures accepted at its pinned boundary.
#'
#' @param store An initialized `GraftStore` or immutable `GraftView`.
#'
#' @return A bounded data frame with one row per accepted measure and
#'   list-columns for declared parameters and dimensions.
#' @export
graft_measures <- function(store) {
  store <- as_graft_read_store_internal(store, "store")
  validate_graft_retrieval(store)
  limit <- graft_retrieval_limits$measures
  rows <- graft_current_rows(
    store,
    classes = graft_measure_class_name,
    limit = limit
  )
  measures <- lapply(seq_len(nrow(rows)), function(index) {
    payload <- jsonlite::fromJSON(
      rows$payload_json[[index]],
      simplifyVector = FALSE
    )
    data.frame(
      id = rows$record_id[[index]],
      name = scalar_character(payload$name),
      title = scalar_character(payload$title),
      description = scalar_character(payload$description),
      target_class = scalar_character(payload$target_class),
      expr = scalar_character(payload$expr),
      parameters = I(list(measure_parameter_frame(payload$parameters))),
      dimensions = I(list(measure_dimension_names(payload$dimensions))),
      revision_id = rows$revision_id[[index]],
      stringsAsFactors = FALSE
    )
  })
  result <- bind_public_rows(measures)
  if (nrow(result) > 0L) {
    result <- result[order(result$name), , drop = FALSE]
  }
  trim_bounded_rows(result, store, limit)
}

measure_parameter_frame <- function(parameters) {
  parsed <- measure_json_list(scalar_character(parameters))
  if (is.null(parsed) || length(parsed) == 0L) {
    return(data.frame(
      name = character(),
      type = character(),
      description = character(),
      column = character(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(
    rbind,
    lapply(parsed, function(parameter) {
      data.frame(
        name = scalar_character(parameter$name),
        type = scalar_character(parameter$type),
        description = scalar_character(parameter$description),
        column = scalar_character(parameter$column),
        stringsAsFactors = FALSE
      )
    })
  )
}

measure_dimension_names <- function(dimensions) {
  parsed <- measure_json_list(scalar_character(dimensions))
  if (is.null(parsed)) {
    return(character())
  }
  vapply(parsed, scalar_character, character(1))
}

abort_measure_error <- function(message, ..., call = rlang::caller_env()) {
  graft_abort(
    "graft_measure_error",
    message,
    ...,
    call = call
  )
}

#' Evaluate an accepted measure
#'
#' `graft_measure()` evaluates one accepted measure over current accepted
#' state, or over the pinned boundary of a `GraftView`. Supplied arguments
#' bind to the measure's declared parameters as equality predicates, and
#' `by` may name only declared dimensions. Evaluation is read-only and
#' deterministic: the same boundary, definition, and arguments always
#' return the same answer.
#'
#' @param store An initialized `GraftStore` or immutable `GraftView`.
#' @param name The name of one accepted measure.
#' @param arguments A named list of values for declared parameters.
#' @param by Optional character vector of declared dimensions to group by.
#'
#' @return A data frame with one `value` column, preceded by one column per
#'   `by` dimension, carrying `measure_id`, `revision_id`, and
#'   `store_schema_digest` attributes.
#' @export
graft_measure <- function(store, name, arguments = list(), by = NULL) {
  read_store <- as_graft_read_store_internal(store, "store")
  validate_graft_retrieval(read_store)
  name <- validate_scalar_text(name, "name")
  if (
    !is.list(arguments) || (length(arguments) > 0L && is.null(names(arguments)))
  ) {
    abort_measure_error(
      "`arguments` must be a named list of parameter values.",
      field = "arguments",
      rule = "measure_arguments_named"
    )
  }
  measures <- graft_measures(store)
  measure <- measures[measures$name == name, , drop = FALSE]
  if (nrow(measure) == 0L) {
    abort_measure_error(
      paste0(
        "No accepted measure is named `",
        name,
        "`. Accepted measures: ",
        if (nrow(measures) == 0L) {
          "none"
        } else {
          paste0("`", measures$name, "`", collapse = ", ")
        },
        "."
      ),
      field = "name",
      rule = "measure_exists",
      observed_value = name
    )
  }
  if (nrow(measure) > 1L) {
    abort_measure_error(
      paste0("More than one accepted measure is named `", name, "`."),
      field = "name",
      rule = "measure_unique",
      observed_value = name
    )
  }
  parameters <- measure$parameters[[1L]]
  dimensions <- measure$dimensions[[1L]]
  unknown_arguments <- setdiff(names(arguments), parameters$name)
  if (length(unknown_arguments) > 0L) {
    abort_measure_error(
      paste0(
        "Unknown measure argument",
        if (length(unknown_arguments) > 1L) "s" else "",
        " ",
        paste0("`", unknown_arguments, "`", collapse = ", "),
        ". Declared parameters: ",
        if (nrow(parameters) == 0L) {
          "none"
        } else {
          paste0("`", parameters$name, "`", collapse = ", ")
        },
        "."
      ),
      field = "arguments",
      rule = "measure_argument_declared"
    )
  }
  by <- if (is.null(by)) character() else as.character(by)
  unknown_by <- setdiff(by, dimensions)
  if (length(unknown_by) > 0L) {
    abort_measure_error(
      paste0(
        "Unknown measure dimension",
        if (length(unknown_by) > 1L) "s" else "",
        " ",
        paste0("`", unknown_by, "`", collapse = ", "),
        ". Declared dimensions: ",
        if (length(dimensions) == 0L) {
          "none"
        } else {
          paste0("`", dimensions, "`", collapse = ", ")
        },
        "."
      ),
      field = "by",
      rule = "measure_dimension_declared"
    )
  }
  target_contract <- read_store$schema$manifest$classes[[
    measure$target_class
  ]]
  if (is.null(target_contract)) {
    abort_measure_error(
      paste0(
        "The accepted measure targets unknown class `",
        measure$target_class,
        "`; this indicates a graft bug."
      ),
      field = "target_class",
      rule = "measure_target_class"
    )
  }
  columns <- measure_scalar_columns(target_contract)
  checked <- measure_expr_check(measure$expr, columns)
  if (nrow(checked$issues) > 0L) {
    abort_measure_error(
      paste0(
        "The accepted measure expression no longer compiles; ",
        "this indicates a graft bug: ",
        checked$issues$message[[1L]]
      ),
      field = "expr",
      rule = "measure_expr_integrity"
    )
  }
  result <- measure_evaluate(
    read_store,
    contract = target_contract,
    sql = checked$sql,
    parameters = parameters,
    arguments = arguments,
    by = by
  )
  result <- trim_bounded_rows(
    result,
    read_store,
    graft_retrieval_limits$measure_rows
  )
  attr(result, "measure_id") <- measure$id
  attr(result, "revision_id") <- measure$revision_id
  attr(result, "store_schema_digest") <- store_schema_digest(read_store)
  result
}

measure_evaluate <- function(store, contract, sql, parameters, arguments, by) {
  connection <- store$connection
  projections <- vapply(
    measure_scalar_columns(contract),
    function(column) {
      slot <- contract$slots[[column]]
      paste0(
        "CAST(json_extract_string(payload_json, '$.",
        column,
        "') AS ",
        safe_duckdb_type(scalar_character(slot$duckdb_type)),
        ") AS ",
        quote_identifier(connection, column)
      )
    },
    character(1)
  )
  predicates <- character()
  params <- list()
  for (argument in names(arguments)) {
    column <- parameters$column[parameters$name == argument][[1L]]
    predicates <- c(
      predicates,
      paste0(quote_identifier(connection, column), " = ?")
    )
    params <- c(params, list(arguments[[argument]]))
  }
  grouped <- vapply(
    by,
    \(column) as.character(quote_identifier(connection, column)),
    character(1)
  )
  query <- paste0(
    "WITH measure_target AS (SELECT ",
    paste(projections, collapse = ", "),
    " FROM (",
    graft_read_source_sql(store),
    ") measure_source WHERE class = ?",
    ") SELECT ",
    paste(c(grouped, paste0(sql, " AS value")), collapse = ", "),
    " FROM measure_target",
    if (length(predicates) > 0L) {
      paste0(" WHERE ", paste(predicates, collapse = " AND "))
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
      ""
    }
  )
  retrieval_query(
    connection,
    query,
    params = c(list(scalar_character(contract$name)), params)
  )
}
