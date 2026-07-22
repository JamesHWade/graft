graft_retrieval_limits <- list(
  batches = 1000L,
  changes = 5000L,
  history = 1000L,
  integrity_issues = 1000L,
  find = 1000L,
  get_claims = 1000L,
  get_evidence = 2000L,
  identifiers = 1000L,
  claims = 1000L,
  evidence = 2000L,
  select = 1000L,
  competing_claims = 1000L,
  unresolved = 5000L,
  context_tokens = 10000L,
  graph_nodes = 500L,
  graph_edges = 2000L,
  graph_hops = 2L
)

validate_retrieval_store <- function(store, refresh = FALSE) {
  validate_initialized_store_for_ingest(
    store,
    write = FALSE,
    refresh = refresh
  )
}

validate_public_class <- function(
  store,
  class,
  roles = NULL,
  argument = "class"
) {
  validate_retrieval_store(store)
  if (
    !is.character(class) ||
      length(class) != 1L ||
      is.na(class) ||
      !nzchar(class)
  ) {
    abort_validation_error(
      paste0("`", argument, "` must be one non-empty concrete class name."),
      field = argument,
      rule = "public_concrete_class",
      observed_value = class
    )
  }
  contract <- store$schema$manifest$classes[[class]]
  if (is.null(contract)) {
    abort_validation_error(
      paste0("Unknown public concrete class `", class, "`."),
      record_class = class,
      field = argument,
      rule = "public_concrete_class",
      observed_value = class
    )
  }
  role <- scalar_character(contract$role)
  if (!is.null(roles) && !role %in% roles) {
    abort_validation_error(
      paste0(
        "Class `",
        class,
        "` has role `",
        role,
        "`, not one of: ",
        paste(roles, collapse = ", "),
        "."
      ),
      record_class = class,
      field = argument,
      rule = "class_role",
      observed_value = role,
      allowed_roles = roles
    )
  }
  contract
}

public_class_names <- function(store, roles = NULL) {
  validate_retrieval_store(store)
  classes <- store$schema$manifest$classes
  if (is.null(roles)) {
    return(names(classes))
  }
  names(Filter(
    \(.x) scalar_character(.x$role) %in% roles,
    classes
  ))
}

public_scalar_slots <- function(contract) {
  Filter(
    \(.x) {
      !scalar_logical(.x$multivalued) &&
        !scalar_logical(.x$sensitive) &&
        !is.na(scalar_character(.x$column))
    },
    contract$slots
  )
}

public_multivalue_slots <- function(contract) {
  Filter(
    \(.x) {
      scalar_logical(.x$multivalued) &&
        !scalar_logical(.x$sensitive)
    },
    contract$slots
  )
}

public_slot_names <- function(contract, multivalued = FALSE) {
  if (isTRUE(multivalued)) {
    return(names(Filter(
      \(.x) !scalar_logical(.x$sensitive),
      contract$slots
    )))
  }
  names(public_scalar_slots(contract))
}

slot_column <- function(contract, slot_name) {
  slot <- contract$slots[[slot_name]]
  if (is.null(slot)) {
    return(NA_character_)
  }
  scalar_character(slot$column)
}

validate_scalar_text <- function(
  value,
  argument,
  allow_empty = FALSE,
  condition = abort_validation_error
) {
  valid <- is.character(value) &&
    length(value) == 1L &&
    !is.na(value)
  if (valid && !allow_empty) {
    valid <- nzchar(value)
  }
  if (!valid) {
    condition(
      paste0("`", argument, "` must be one non-empty character value."),
      field = argument,
      rule = "scalar_character",
      observed_value = value
    )
  }
  value
}

validate_optional_scalar_text <- function(value, argument) {
  if (is.null(value)) {
    return(NULL)
  }
  validate_scalar_text(value, argument)
}

validate_result_limit <- function(
  limit,
  argument = "limit",
  hard_limit
) {
  valid <- is.numeric(limit) &&
    length(limit) == 1L &&
    !is.na(limit) &&
    is.finite(limit) &&
    limit >= 1 &&
    limit == floor(limit)
  if (!valid) {
    abort_limit_error(
      paste0("`", argument, "` must be one positive whole number."),
      argument = argument,
      requested_limit = limit,
      hard_limit = hard_limit
    )
  }
  limit <- as.integer(limit)
  if (limit > hard_limit) {
    abort_limit_error(
      paste0(
        "`",
        argument,
        "` may not exceed the hard cap of ",
        hard_limit,
        "."
      ),
      argument = argument,
      requested_limit = limit,
      hard_limit = hard_limit
    )
  }
  limit
}

store_schema_digest <- function(store) {
  scalar_character(
    store$schema$manifest$fingerprints$structural_digest
  )
}

bounded_data_frame <- function(data, store, limit, truncated = FALSE) {
  stopifnot(is.data.frame(data))
  attr(data, "truncated") <- isTRUE(truncated)
  attr(data, "limit") <- as.integer(limit)
  attr(data, "store_schema_digest") <- store_schema_digest(store)
  data
}

trim_bounded_rows <- function(data, store, limit) {
  exceeds_limit <- nrow(data) > limit
  truncated <- isTRUE(attr(data, "truncated")) || exceeds_limit
  if (exceeds_limit) {
    data <- data[seq_len(limit), , drop = FALSE]
  }
  rownames(data) <- NULL
  bounded_data_frame(data, store, limit, truncated)
}

manifest_relation_for_slot <- function(store, record_class, slot) {
  matches <- Filter(
    \(.x) {
      identical(scalar_character(.x$owner_class), record_class) &&
        identical(scalar_character(.x$slot), slot)
    },
    store$schema$manifest$relations
  )
  if (length(matches) == 0L) {
    return(NULL)
  }
  matches[[1L]]
}

hydrate_public_record <- function(store, record_class, row) {
  contract <- validate_public_class(store, record_class)
  fields <- intersect(public_slot_names(contract), names(row))
  output <- as.list(row[1L, fields, drop = FALSE])
  multivalues <- public_multivalue_slots(contract)
  for (slot_name in names(multivalues)) {
    relation <- manifest_relation_for_slot(store, record_class, slot_name)
    if (is.null(relation)) {
      output[[slot_name]] <- list()
      next
    }
    kind <- scalar_character(relation$kind)
    owner_column <- if (identical(kind, "object")) "subject" else "owner_id"
    value_column <- if (identical(kind, "object")) "object" else "value"
    columns <- vapply(
      relation$columns,
      \(.x) scalar_character(.x$name),
      character(1)
    )
    order <- if ("position" %in% columns) {
      paste0(
        " ORDER BY ",
        quote_identifier(store$connection, "position"),
        ", ",
        quote_identifier(store$connection, value_column)
      )
    } else {
      paste0(
        " ORDER BY ",
        quote_identifier(store$connection, value_column)
      )
    }
    sql <- paste0(
      "SELECT ",
      quote_identifier(store$connection, value_column),
      " FROM ",
      quote_identifier(
        store$connection,
        scalar_character(relation$table)
      ),
      " WHERE ",
      quote_identifier(store$connection, owner_column),
      " = ?",
      order
    )
    values <- with_duckdb_error(
      "hydrate_relation",
      DBI::dbGetQuery(
        store$connection,
        sql,
        params = list(as.character(row$id[[1L]]))
      )
    )
    output[[slot_name]] <- unname(values[[value_column]])
  }
  output
}

record_locations <- function(store, id, classes = NULL) {
  validate_scalar_text(id, "id", condition = abort_reference_error)
  if (is.null(classes)) {
    classes <- public_class_names(store)
  }
  locations <- list()
  for (record_class in classes) {
    contract <- validate_public_class(store, record_class)
    table <- scalar_character(contract$table)
    sql <- paste0(
      "SELECT COUNT(*) AS n FROM ",
      quote_identifier(store$connection, table),
      " WHERE ",
      quote_identifier(store$connection, slot_column(contract, "id")),
      " = ?"
    )
    count <- with_duckdb_error(
      "record_location",
      DBI::dbGetQuery(
        store$connection,
        sql,
        params = list(id)
      )
    )$n[[1L]]
    if (count > 0L) {
      locations[[record_class]] <- as.integer(count)
    }
  }
  locations
}

bind_public_rows <- function(rows) {
  if (length(rows) == 0L) {
    return(data.frame())
  }
  dplyr::bind_rows(rows)
}

statement_classes <- function(store, shape = NULL) {
  classes <- store$schema$manifest$classes
  keep <- vapply(
    classes,
    function(contract) {
      is_statement <- identical(
        scalar_character(contract$role),
        "statement"
      )
      if (is.null(shape)) {
        return(is_statement)
      }
      is_statement &&
        identical(scalar_character(contract$statement_shape), shape)
    },
    logical(1)
  )
  names(classes)[keep]
}

role_classes <- function(store, role) {
  public_class_names(store, roles = role)
}

is_active_statement_sql <- function(store, contract, alias = NULL) {
  if (!"status" %in% names(public_scalar_slots(contract))) {
    return("TRUE")
  }
  column <- quote_identifier(store$connection, slot_column(contract, "status"))
  if (!is.null(alias)) {
    column <- paste0(
      quote_identifier(store$connection, alias),
      ".",
      column
    )
  }
  paste0("(", column, " IS NULL OR ", column, " = 'active')")
}
