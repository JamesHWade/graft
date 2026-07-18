#' Read records from one concrete class
#'
#' `kg_records()` exposes only a manifest-declared client class. It returns a
#' lazy dbplyr table and never collects implicitly.
#'
#' @param store An initialized `kg_store`.
#' @param class One concrete class name from the active manifest.
#'
#' @return A lazy dbplyr table.
#' @export
kg_records <- function(store, class) {
  contract <- validate_public_class(store, class)
  table <- scalar_character(contract$table)
  fields <- public_slot_names(contract)
  columns <- vapply(
    fields,
    \(.x) slot_column(contract, .x),
    character(1)
  )
  result <- dplyr::tbl(store$connection, table)
  result <- dplyr::select(
    result,
    dplyr::all_of(stats::setNames(columns, fields))
  )
  attr(result, "graft_record_class") <- class
  attr(result, "store_schema_digest") <- store_schema_digest(store)
  result
}

#' Look up an exact external identifier
#'
#' The input is normalized using the versioned namespace contract declared by
#' the active manifest. Only active primary and equivalent registry entries
#' match.
#'
#' @param store An initialized `kg_store`.
#' @param namespace A manifest-declared external-identifier namespace.
#' @param value One external identifier value.
#' @param class Optional concrete class restriction.
#'
#' @return A data frame containing exact registry matches and provenance.
#' @export
kg_lookup <- function(store, namespace, value, class = NULL) {
  validate_retrieval_store(store)
  namespace <- validate_scalar_text(namespace, "namespace")
  value <- validate_scalar_text(value, "value")
  versions <- store$schema$manifest$identifier_normalization_versions
  if (!namespace %in% names(versions)) {
    abort_validation_error(
      paste0(
        "Unknown identifier namespace `",
        namespace,
        "` for the active manifest."
      ),
      field = "namespace",
      rule = "manifest_identifier_namespace",
      observed_value = namespace
    )
  }
  eligible <- identifier_namespace_classes(store, namespace)
  if (length(eligible) == 0L) {
    abort_validation_error(
      paste0(
        "Identifier namespace `",
        namespace,
        "` is not declared by a public concrete class."
      ),
      field = "namespace",
      rule = "public_identifier_namespace",
      observed_value = namespace
    )
  }
  if (!is.null(class)) {
    validate_public_class(store, class)
    if (!class %in% eligible) {
      abort_validation_error(
        paste0(
          "Class `",
          class,
          "` does not declare identifier namespace `",
          namespace,
          "`."
        ),
        record_class = class,
        field = "namespace",
        rule = "class_identifier_namespace",
        observed_value = namespace
      )
    }
    eligible <- class
  }
  normalized <- normalize_manifest_identifier(
    store,
    namespace,
    value
  )
  if (is.na(normalized) || !nzchar(normalized)) {
    abort_validation_error(
      "`value` is empty after identifier normalization.",
      field = "value",
      rule = "normalized_identifier",
      observed_value = value,
      namespace = namespace
    )
  }
  placeholders <- paste(rep("?", length(eligible)), collapse = ", ")
  sql <- paste0(
    "SELECT record_id, class, namespace, value, normalized_value, ",
    "status, assigned_by, confidence, created_at FROM ",
    quote_identifier(store$connection, "_graft_identifiers"),
    " WHERE namespace = ? AND normalized_value = ?",
    " AND status IN ('primary', 'equivalent')",
    " AND class IN (",
    placeholders,
    ") ORDER BY class, record_id, status, created_at"
  )
  rows <- with_duckdb_error(
    "lookup_identifier",
    DBI::dbGetQuery(
      store$connection,
      sql,
      params = c(list(namespace, normalized), as.list(eligible))
    )
  )
  duplicate <- split(rows$record_id, rows$class)
  inconsistent <- names(Filter(
    \(.x) length(unique(.x)) > 1L,
    duplicate
  ))
  if (length(inconsistent) > 0L) {
    abort_identity_error(
      paste0(
        "The active identifier maps to multiple records in class `",
        inconsistent[[1L]],
        "`."
      ),
      record_class = inconsistent[[1L]],
      field = "value",
      rule = "unique_active_identifier",
      observed_value = value,
      namespace = namespace,
      normalized_value = normalized,
      matched_record_ids = unique(duplicate[[inconsistent[[1L]]]])
    )
  }
  bounded_data_frame(
    rows,
    store,
    limit = max(1L, length(eligible)),
    truncated = FALSE
  )
}

identifier_namespace_classes <- function(store, namespace) {
  classes <- store$schema$manifest$classes
  keep <- vapply(
    classes,
    function(contract) {
      any(vapply(
        contract$slots,
        \(.x) {
          !scalar_logical(.x$sensitive) &&
            identical(
              scalar_character(.x$external_identifier),
              namespace
            )
        },
        logical(1)
      ))
    },
    logical(1)
  )
  names(classes)[keep]
}

normalize_manifest_identifier <- function(store, namespace, value) {
  version <- scalar_character(
    store$schema$manifest$identifier_normalization_versions[[namespace]]
  )
  if (!identical(version, "1")) {
    abort_schema_error(
      paste0(
        "Identifier normalization contract `",
        namespace,
        "` version `",
        version,
        "` is not supported by this graft runtime."
      ),
      namespace = namespace,
      normalization_version = version
    )
  }
  normalize_external_identifier(namespace, value)
}

#' List external identifiers for one record
#'
#' @param store An initialized `kg_store`.
#' @param id One internal record identifier.
#'
#' @return A bounded data frame of public identifier-registry details.
#' @export
kg_identifiers <- function(store, id) {
  validate_retrieval_store(store)
  id <- validate_scalar_text(id, "id", condition = abort_reference_error)
  limit <- graft_retrieval_limits$identifiers
  sql <- paste0(
    "SELECT record_id, class, namespace, value, normalized_value, ",
    "status, assigned_by, confidence, created_at FROM ",
    quote_identifier(store$connection, "_graft_identifiers"),
    " WHERE record_id = ?",
    " ORDER BY class, ",
    "CASE status WHEN 'primary' THEN 0 WHEN 'equivalent' THEN 1 ",
    "WHEN 'candidate' THEN 2 ELSE 3 END, namespace, normalized_value",
    " LIMIT ",
    limit + 1L
  )
  rows <- with_duckdb_error(
    "list_identifiers",
    DBI::dbGetQuery(store$connection, sql, params = list(id))
  )
  if (nrow(rows) > 0L) {
    public <- vapply(
      seq_len(nrow(rows)),
      function(index) {
        rows$class[[index]] %in%
          identifier_namespace_classes(
            store,
            rows$namespace[[index]]
          )
      },
      logical(1)
    )
    rows <- rows[public, , drop = FALSE]
  }
  trim_bounded_rows(rows, store, limit)
}

#' Hydrate exactly one record
#'
#' @param store An initialized `kg_store`.
#' @param id One internal record identifier.
#' @param include Related data to include. Supported values are
#'   `"identifiers"`, `"claims"`, and `"evidence"`.
#' @param limits Named limits for identifiers, claims, and evidence.
#'
#' @return A `kg_record` containing the record and requested related data.
#' @export
kg_get <- function(
  store,
  id,
  include = c("identifiers", "claims", "evidence"),
  limits = list(identifiers = 100L, claims = 50L, evidence = 100L)
) {
  validate_retrieval_store(store)
  id <- validate_scalar_text(id, "id", condition = abort_reference_error)
  include <- validate_get_include(include)
  limits <- validate_get_limits(limits)
  locations <- record_locations(store, id)
  if (length(locations) == 0L) {
    abort_reference_error(
      paste0("Record `", id, "` was not found."),
      record_id = id,
      field = "id",
      rule = "record_exists",
      observed_value = id
    )
  }
  if (length(locations) != 1L || unname(locations[[1L]]) != 1L) {
    abort_identity_error(
      paste0("Record `", id, "` is ambiguous across public classes."),
      record_id = id,
      field = "id",
      rule = "unique_record_location",
      observed_value = id,
      matched_classes = names(locations)
    )
  }
  record_class <- names(locations)[[1L]]
  contract <- validate_public_class(store, record_class)
  fields <- public_slot_names(contract)
  selected <- vapply(
    fields,
    function(field) {
      column <- quote_identifier(
        store$connection,
        slot_column(contract, field)
      )
      if (identical(field, slot_column(contract, field))) {
        return(column)
      }
      paste0(
        column,
        " AS ",
        quote_identifier(store$connection, field)
      )
    },
    character(1)
  )
  sql <- paste0(
    "SELECT ",
    paste(selected, collapse = ", "),
    " FROM ",
    quote_identifier(store$connection, scalar_character(contract$table)),
    " WHERE ",
    quote_identifier(store$connection, slot_column(contract, "id")),
    " = ?"
  )
  row <- with_duckdb_error(
    "get_record",
    DBI::dbGetQuery(store$connection, sql, params = list(id))
  )
  record <- hydrate_public_record(store, record_class, row)

  related <- list()
  truncation <- list()
  if ("identifiers" %in% include) {
    identifiers <- kg_identifiers(store, id)
    identifiers <- trim_bounded_rows(identifiers, store, limits$identifiers)
    related$identifiers <- identifiers
    truncation$identifiers <- isTRUE(attr(identifiers, "truncated"))
  }
  claims <- NULL
  if ("claims" %in% include || "evidence" %in% include) {
    claims <- kg_claims(store, id, limit = limits$claims)
    if ("claims" %in% include) {
      related$claims <- claims
      truncation$claims <- isTRUE(attr(claims, "truncated"))
    }
  }
  if ("evidence" %in% include) {
    evidence <- evidence_related_to_record(
      store,
      id,
      record_class,
      claims,
      limits$evidence
    )
    related$evidence <- evidence
    truncation$evidence <- isTRUE(attr(evidence, "truncated"))
  }
  new_kg_record(
    id = id,
    record_class = record_class,
    record = record,
    related = related,
    limits = limits[include],
    truncated = truncation,
    store_schema_digest = store_schema_digest(store)
  )
}

validate_get_include <- function(include) {
  allowed <- c("identifiers", "claims", "evidence")
  if (
    !is.character(include) ||
      anyNA(include) ||
      any(!nzchar(include)) ||
      anyDuplicated(include)
  ) {
    abort_validation_error(
      "`include` must contain unique related-data names.",
      field = "include",
      rule = "unique_supported_values",
      observed_value = include
    )
  }
  unknown <- setdiff(include, allowed)
  if (length(unknown) > 0L) {
    abort_validation_error(
      paste0(
        "Unsupported `include` value(s): ",
        paste(unknown, collapse = ", "),
        "."
      ),
      field = "include",
      rule = "supported_values",
      observed_value = unknown
    )
  }
  include
}

validate_get_limits <- function(limits) {
  defaults <- list(identifiers = 100L, claims = 50L, evidence = 100L)
  if (!is.list(limits) || (length(limits) > 0L && is.null(names(limits)))) {
    abort_limit_error(
      "`limits` must be a named list.",
      argument = "limits",
      requested_limit = limits
    )
  }
  unknown <- setdiff(names(limits), names(defaults))
  if (length(unknown) > 0L || any(!nzchar(names(limits)))) {
    abort_limit_error(
      paste0(
        "Unknown related-data limit(s): ",
        paste(unknown, collapse = ", "),
        "."
      ),
      argument = "limits",
      requested_limit = limits
    )
  }
  defaults[names(limits)] <- limits
  defaults$identifiers <- validate_result_limit(
    defaults$identifiers,
    "limits$identifiers",
    graft_retrieval_limits$identifiers
  )
  defaults$claims <- validate_result_limit(
    defaults$claims,
    "limits$claims",
    graft_retrieval_limits$get_claims
  )
  defaults$evidence <- validate_result_limit(
    defaults$evidence,
    "limits$evidence",
    graft_retrieval_limits$get_evidence
  )
  defaults
}

#' Perform a bounded structured selection
#'
#' `kg_select()` validates every class, field, filter, ordering clause, and
#' value against the active manifest. It does not accept SQL.
#'
#' @param store An initialized `kg_store`.
#' @param class One concrete class.
#' @param fields One or more public scalar fields to return.
#' @param filters A list of filter clauses with `field`, `operator`, and, when
#'   required, `value`.
#' @param order_by A list of ordering clauses with `field` and optional
#'   `direction` (`"asc"` or `"desc"`).
#' @param limit Maximum rows to collect, up to the hard package cap.
#'
#' @return A bounded, collected data frame.
#' @export
kg_select <- function(
  store,
  class,
  fields,
  filters = list(),
  order_by = list(),
  limit = 100
) {
  contract <- validate_public_class(store, class)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$select
  )
  fields <- validate_select_fields(contract, fields)
  filters <- normalize_query_clauses(filters, "filters")
  order_by <- normalize_query_clauses(order_by, "order_by")
  built_filters <- lapply(
    filters,
    compile_select_filter,
    store = store,
    contract = contract
  )
  built_order <- lapply(
    order_by,
    compile_select_order,
    store = store,
    contract = contract
  )
  selected <- vapply(
    fields,
    function(field) {
      column <- quote_identifier(
        store$connection,
        slot_column(contract, field)
      )
      if (identical(field, slot_column(contract, field))) {
        return(column)
      }
      paste0(
        column,
        " AS ",
        quote_identifier(store$connection, field)
      )
    },
    character(1)
  )
  where <- if (length(built_filters) == 0L) {
    ""
  } else {
    paste0(
      " WHERE ",
      paste(vapply(built_filters, `[[`, "", "sql"), collapse = " AND ")
    )
  }
  if (length(built_order) == 0L && "id" %in% names(contract$slots)) {
    built_order <- list(list(
      sql = paste0(
        quote_identifier(store$connection, slot_column(contract, "id")),
        " ASC"
      )
    ))
  }
  ordering <- if (length(built_order) == 0L) {
    ""
  } else {
    paste0(
      " ORDER BY ",
      paste(vapply(built_order, `[[`, "", "sql"), collapse = ", ")
    )
  }
  sql <- paste0(
    "SELECT ",
    paste(selected, collapse = ", "),
    " FROM ",
    quote_identifier(store$connection, scalar_character(contract$table)),
    where,
    ordering,
    " LIMIT ",
    limit + 1L
  )
  params <- unlist(
    lapply(built_filters, `[[`, "params"),
    recursive = FALSE,
    use.names = FALSE
  )
  rows <- with_duckdb_error(
    "structured_select",
    DBI::dbGetQuery(store$connection, sql, params = params)
  )
  trim_bounded_rows(rows, store, limit)
}

validate_select_fields <- function(contract, fields) {
  available <- public_slot_names(contract)
  if (
    !is.character(fields) ||
      length(fields) == 0L ||
      anyNA(fields) ||
      any(!nzchar(fields)) ||
      anyDuplicated(fields)
  ) {
    abort_validation_error(
      "`fields` must contain unique public scalar field names.",
      record_class = scalar_character(contract$name),
      field = "fields",
      rule = "public_scalar_fields",
      observed_value = fields
    )
  }
  unknown <- setdiff(fields, available)
  if (length(unknown) > 0L) {
    abort_validation_error(
      paste0(
        "Unknown, multivalued, or sensitive field(s): ",
        paste(unknown, collapse = ", "),
        "."
      ),
      record_class = scalar_character(contract$name),
      field = unknown[[1L]],
      rule = "public_scalar_field",
      observed_value = unknown
    )
  }
  fields
}

normalize_query_clauses <- function(clauses, argument) {
  if (!is.list(clauses)) {
    abort_validation_error(
      paste0("`", argument, "` must be a list of structured clauses."),
      field = argument,
      rule = "structured_clauses",
      observed_value = clauses
    )
  }
  if (
    length(clauses) > 0L &&
      !is.null(names(clauses)) &&
      "field" %in% names(clauses)
  ) {
    clauses <- list(clauses)
  }
  valid <- vapply(clauses, is.list, logical(1))
  if (any(!valid)) {
    abort_validation_error(
      paste0("Every `", argument, "` clause must be a named list."),
      field = argument,
      rule = "structured_clause",
      observed_value = clauses
    )
  }
  clauses
}

compile_select_filter <- function(clause, store, contract) {
  allowed_operators <- c(
    "eq",
    "ne",
    "in",
    "contains",
    "starts_with",
    "gt",
    "gte",
    "lt",
    "lte",
    "is_null",
    "not_null"
  )
  if (
    is.null(names(clause)) ||
      !"field" %in% names(clause) ||
      !"operator" %in% names(clause)
  ) {
    abort_validation_error(
      "Every filter requires `field` and `operator`.",
      field = "filters",
      rule = "filter_shape",
      observed_value = clause
    )
  }
  unknown_members <- setdiff(names(clause), c("field", "operator", "value"))
  if (length(unknown_members) > 0L) {
    abort_validation_error(
      paste0(
        "Unknown filter member(s): ",
        paste(unknown_members, collapse = ", "),
        "."
      ),
      field = "filters",
      rule = "filter_shape",
      observed_value = unknown_members
    )
  }
  field <- validate_scalar_text(clause$field, "filters$field")
  validate_select_fields(contract, field)
  operator <- validate_scalar_text(clause$operator, "filters$operator")
  if (!operator %in% allowed_operators) {
    abort_validation_error(
      paste0("Unsupported filter operator `", operator, "`."),
      record_class = scalar_character(contract$name),
      field = field,
      rule = "supported_filter_operator",
      observed_value = operator,
      allowed_operators = allowed_operators
    )
  }
  slot <- contract$slots[[field]]
  column <- quote_identifier(
    store$connection,
    slot_column(contract, field)
  )
  if (operator %in% c("is_null", "not_null")) {
    if ("value" %in% names(clause) && !is.null(clause$value)) {
      abort_validation_error(
        paste0("Operator `", operator, "` does not accept `value`."),
        record_class = scalar_character(contract$name),
        field = field,
        rule = "filter_value_absent",
        observed_value = clause$value
      )
    }
    return(list(
      sql = paste0(
        column,
        if (operator == "is_null") " IS NULL" else " IS NOT NULL"
      ),
      params = list()
    ))
  }
  if (!"value" %in% names(clause)) {
    abort_validation_error(
      paste0("Operator `", operator, "` requires `value`."),
      record_class = scalar_character(contract$name),
      field = field,
      rule = "filter_value_present",
      observed_value = NULL
    )
  }
  value <- validate_filter_value(
    clause$value,
    slot,
    operator,
    contract,
    store
  )
  switch(
    operator,
    eq = list(sql = paste0(column, " = ?"), params = list(value)),
    ne = list(sql = paste0(column, " <> ?"), params = list(value)),
    `in` = list(
      sql = paste0(
        column,
        " IN (",
        paste(rep("?", length(value)), collapse = ", "),
        ")"
      ),
      params = as.list(value)
    ),
    contains = list(
      sql = paste0("LOWER(CAST(", column, " AS VARCHAR)) LIKE ? ESCAPE '\\'"),
      params = list(paste0("%", escape_like(tolower(value)), "%"))
    ),
    starts_with = list(
      sql = paste0("LOWER(CAST(", column, " AS VARCHAR)) LIKE ? ESCAPE '\\'"),
      params = list(paste0(escape_like(tolower(value)), "%"))
    ),
    gt = list(sql = paste0(column, " > ?"), params = list(value)),
    gte = list(sql = paste0(column, " >= ?"), params = list(value)),
    lt = list(sql = paste0(column, " < ?"), params = list(value)),
    lte = list(sql = paste0(column, " <= ?"), params = list(value))
  )
}

validate_filter_value <- function(value, slot, operator, contract, store) {
  expected_length <- if (identical(operator, "in")) NULL else 1L
  if (
    is.null(value) ||
      length(value) == 0L ||
      anyNA(value) ||
      (!is.null(expected_length) && length(value) != expected_length)
  ) {
    abort_validation_error(
      "`value` has invalid cardinality or missing values.",
      record_class = scalar_character(contract$name),
      field = scalar_character(slot$name),
      rule = "filter_value_cardinality",
      observed_value = value
    )
  }
  type <- toupper(scalar_character(slot$relational_type, "VARCHAR"))
  valid <- switch(
    type,
    VARCHAR = is.character(value) || is.factor(value),
    BOOLEAN = is.logical(value),
    BIGINT = is.numeric(value) &&
      all(is.finite(value)) &&
      all(value == floor(value)),
    DOUBLE = is.numeric(value) && all(is.finite(value)),
    DATE = inherits(value, "Date"),
    TIMESTAMP = inherits(value, "POSIXt"),
    FALSE
  )
  if (!valid) {
    abort_validation_error(
      paste0(
        "Filter value for `",
        scalar_character(slot$name),
        "` does not match manifest type `",
        type,
        "`."
      ),
      record_class = scalar_character(contract$name),
      field = scalar_character(slot$name),
      rule = "filter_value_type",
      observed_value = value,
      expected_type = type
    )
  }
  if (
    operator %in% c("contains", "starts_with") && !identical(type, "VARCHAR")
  ) {
    abort_validation_error(
      paste0("Operator `", operator, "` requires a text field."),
      record_class = scalar_character(contract$name),
      field = scalar_character(slot$name),
      rule = "text_filter_operator",
      observed_value = operator
    )
  }
  enum <- scalar_character(slot$enum)
  if (!is.na(enum) && operator %in% c("eq", "ne", "in")) {
    allowed <- vapply(
      store$schema$manifest$enums[[enum]]$permissible_values,
      \(.x) scalar_character(.x$value),
      character(1)
    )
    if (length(allowed) > 0L && any(!as.character(value) %in% allowed)) {
      abort_validation_error(
        "Filter value is not a permissible enum value.",
        record_class = scalar_character(contract$name),
        field = scalar_character(slot$name),
        rule = "enum",
        observed_value = value,
        allowed_values = allowed
      )
    }
  }
  if (is.factor(value)) {
    value <- as.character(value)
  }
  value
}

compile_select_order <- function(clause, store, contract) {
  if (is.null(names(clause)) || !"field" %in% names(clause)) {
    abort_validation_error(
      "Every ordering clause requires `field`.",
      field = "order_by",
      rule = "order_shape",
      observed_value = clause
    )
  }
  unknown_members <- setdiff(names(clause), c("field", "direction"))
  if (length(unknown_members) > 0L) {
    abort_validation_error(
      paste0(
        "Unknown ordering member(s): ",
        paste(unknown_members, collapse = ", "),
        "."
      ),
      field = "order_by",
      rule = "order_shape",
      observed_value = unknown_members
    )
  }
  field <- validate_scalar_text(clause$field, "order_by$field")
  validate_select_fields(contract, field)
  direction <- if (is.null(clause$direction)) {
    "asc"
  } else {
    validate_scalar_text(clause$direction, "order_by$direction")
  }
  direction <- tolower(direction)
  if (!direction %in% c("asc", "desc")) {
    abort_validation_error(
      "`direction` must be \"asc\" or \"desc\".",
      record_class = scalar_character(contract$name),
      field = field,
      rule = "order_direction",
      observed_value = direction
    )
  }
  list(
    sql = paste(
      quote_identifier(
        store$connection,
        slot_column(contract, field)
      ),
      toupper(direction)
    )
  )
}

escape_like <- function(value) {
  value <- gsub("\\\\", "\\\\\\\\", value)
  value <- gsub("%", "\\\\%", value, fixed = TRUE)
  gsub("_", "\\\\_", value, fixed = TRUE)
}

#' List unresolved mentions
#'
#' @param store An initialized `kg_store`.
#' @param class Optional concrete mention class.
#' @param source_id Optional source record restriction.
#' @param limit Maximum rows to return.
#'
#' @return A bounded data frame of mention records with null `entity_id`.
#' @export
kg_unresolved <- function(
  store,
  class = NULL,
  source_id = NULL,
  limit = 1000
) {
  validate_retrieval_store(store)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$unresolved
  )
  if (is.null(class)) {
    classes <- role_classes(store, "mention")
  } else {
    validate_public_class(store, class, roles = "mention")
    classes <- class
  }
  source_id <- validate_optional_scalar_text(source_id, "source_id")
  rows <- list()
  for (record_class in classes) {
    contract <- validate_public_class(store, record_class, roles = "mention")
    fields <- public_slot_names(contract)
    if (!"entity_id" %in% fields) {
      next
    }
    selected <- paste(
      quote_identifier(store$connection, fields),
      collapse = ", "
    )
    where <- paste0(
      quote_identifier(store$connection, slot_column(contract, "entity_id")),
      " IS NULL"
    )
    params <- list()
    if (!is.null(source_id)) {
      if (!"source_id" %in% fields) {
        next
      }
      where <- paste0(
        where,
        " AND ",
        quote_identifier(store$connection, slot_column(contract, "source_id")),
        " = ?"
      )
      params <- list(source_id)
    }
    sql <- paste0(
      "SELECT ? AS class, ",
      selected,
      " FROM ",
      quote_identifier(store$connection, scalar_character(contract$table)),
      " WHERE ",
      where,
      " ORDER BY ",
      quote_identifier(store$connection, slot_column(contract, "id")),
      " LIMIT ",
      limit + 1L
    )
    rows[[record_class]] <- with_duckdb_error(
      "unresolved_mentions",
      DBI::dbGetQuery(
        store$connection,
        sql,
        params = c(list(record_class), params)
      )
    )
  }
  result <- bind_public_rows(rows)
  if (nrow(result) > 0L) {
    result <- result[order(result$class, result$id), , drop = FALSE]
  }
  trim_bounded_rows(result, store, limit)
}
