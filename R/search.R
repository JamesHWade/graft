#' Search manifest-declared record text
#'
#' Search is case-insensitive and uses only each class's declared label and
#' search slots. Results are deterministically ranked and bounded.
#'
#' @param store An initialized `kg_store`.
#' @param query One non-empty search string.
#' @param class Optional concrete class restriction.
#' @param limit Maximum results to return.
#'
#' @return A bounded data frame with stable IDs, classes, labels, and scores.
#' @export
kg_find <- function(store, query, class = NULL, limit = 20) {
  validate_retrieval_store(store)
  query <- trimws(validate_scalar_text(query, "query"))
  if (!nzchar(query)) {
    abort_validation_error(
      "`query` may not contain only whitespace.",
      field = "query",
      rule = "non_empty_search_query",
      observed_value = query
    )
  }
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$find
  )
  if (is.null(class)) {
    classes <- public_class_names(store)
  } else {
    validate_public_class(store, class)
    classes <- class
  }
  normalized <- tolower(query)
  sql_parts <- list()
  for (record_class in classes) {
    contract <- validate_public_class(store, record_class)
    search <- unique(c(
      scalar_character(contract$label_slot),
      empty_character(contract$search_slots)
    ))
    search <- search[
      !is.na(search) &
        search %in% names(public_scalar_slots(contract))
    ]
    if (length(search) == 0L) {
      next
    }
    label_slot <- scalar_character(contract$label_slot)
    if (
      is.na(label_slot) ||
        !label_slot %in% names(public_scalar_slots(contract))
    ) {
      label_slot <- search[[1L]]
    }
    weights <- search_field_weights(contract, search, label_slot)
    expressions <- vapply(
      seq_along(search),
      function(index) {
        search_score_expression(
          store,
          contract,
          search[[index]],
          weights[[index]],
          normalized
        )
      },
      character(1)
    )
    score <- paste0("(", paste(expressions, collapse = " + "), ")")
    label_column <- quote_identifier(
      store$connection,
      slot_column(contract, label_slot)
    )
    id_column <- quote_identifier(
      store$connection,
      slot_column(contract, "id")
    )
    sql_parts[[record_class]] <- paste0(
      "SELECT ",
      as.character(DBI::dbQuoteString(store$connection, record_class)),
      " AS class, ",
      id_column,
      " AS id, CAST(",
      label_column,
      " AS VARCHAR) AS label, ",
      score,
      " AS score FROM ",
      quote_identifier(store$connection, scalar_character(contract$table)),
      " WHERE ",
      score,
      " > 0"
    )
  }
  if (length(sql_parts) == 0L) {
    empty <- data.frame(
      id = character(),
      class = character(),
      label = character(),
      score = numeric(),
      stringsAsFactors = FALSE
    )
    return(bounded_data_frame(empty, store, limit, FALSE))
  }
  sql <- paste0(
    "SELECT id, class, label, score FROM (",
    paste(sql_parts, collapse = " UNION ALL "),
    ") AS graft_search ORDER BY score DESC, class ASC, id ASC LIMIT ",
    limit + 1L
  )
  rows <- with_duckdb_error(
    "find_records",
    DBI::dbGetQuery(store$connection, sql)
  )
  trim_bounded_rows(rows, store, limit)
}

search_field_weights <- function(contract, fields, label_slot) {
  weights <- vapply(
    seq_along(fields),
    function(index) {
      declared <- suppressWarnings(as.numeric(
        scalar_character(contract$slots[[fields[[index]]]]$search_weight)
      ))
      if (length(declared) == 1L && is.finite(declared) && declared > 0) {
        return(declared)
      }
      as.numeric(length(fields) - index + 1L)
    },
    numeric(1)
  )
  weights[fields == label_slot] <- weights[fields == label_slot] +
    max(weights) +
    1
  weights
}

search_score_expression <- function(
  store,
  contract,
  field,
  weight,
  normalized
) {
  column <- quote_identifier(
    store$connection,
    slot_column(contract, field)
  )
  normalized_column <- paste0(
    "LOWER(TRIM(CAST(",
    column,
    " AS VARCHAR)))"
  )
  exact <- as.character(DBI::dbQuoteString(
    store$connection,
    normalized
  ))
  prefix <- as.character(DBI::dbQuoteString(
    store$connection,
    paste0(escape_like(normalized), "%")
  ))
  contains <- as.character(DBI::dbQuoteString(
    store$connection,
    paste0("%", escape_like(normalized), "%")
  ))
  paste0(
    "CASE WHEN ",
    normalized_column,
    " = ",
    exact,
    " THEN ",
    weight * 3,
    " WHEN ",
    normalized_column,
    " LIKE ",
    prefix,
    " ESCAPE '\\' THEN ",
    weight * 2,
    " WHEN ",
    normalized_column,
    " LIKE ",
    contains,
    " ESCAPE '\\' THEN ",
    weight,
    " ELSE 0 END"
  )
}
