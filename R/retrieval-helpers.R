graft_retrieval_limits <- list(
  batches = 1000L,
  definitions = 1000L,
  calculation_rows = 1000L,
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
  graph_hops = 2L,
  okf_concepts = 10000L,
  okf_context_concepts = 100L,
  okf_context_chars = 100000L,
  okf_context_bytes = 20L * 1024L^2
)

validate_retrieval_store <- function(store, refresh = FALSE) {
  if (is_graft_snapshot_backend(store)) {
    validate_initialized_store(
      store$source_backend,
      write = FALSE,
      refresh = refresh
    )
    return(invisible(store))
  }
  validate_initialized_store(
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
        !is.na(scalar_character(.x$view_column))
    },
    contract$slots
  )
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
