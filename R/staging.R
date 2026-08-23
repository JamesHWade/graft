candidate_stage_version <- "graft-candidate-stage-v1"

plan_candidate_records <- function(store, batch, records, metadata) {
  normalized <- normalize_candidate_container(store, records)
  snapshot <- read_planning_snapshot(store, batch$producer, metadata)
  identity <- resolve_candidate_identities(
    store$schema$manifest,
    batch,
    normalized$staged,
    snapshot
  )
  staged <- identity$staged
  issues <- c(normalized$issues, identity$issues)
  validation <- validate_candidate_stages(
    store$schema$manifest,
    staged,
    snapshot,
    store$connection
  )
  staged <- validation$staged
  issues <- c(issues, validation$issues)
  planned <- plan_candidate_changes(
    staged,
    snapshot$current,
    snapshot$planned_at
  )
  issues <- bind_plan_issues(issues)
  list(
    records = lapply(planned$staged, \(.x) .x$data),
    changes = planned$changes,
    issues = issues,
    execution = list(
      format = candidate_stage_version,
      rows = planned$rows,
      records = lapply(planned$staged, \(.x) .x$data),
      identifiers = identity$identifiers,
      origins = identity$origins,
      references = validation$references
    ),
    registry_preconditions = list(
      identifier_digest = snapshot$identifier_digest,
      origin_digest = snapshot$origin_digest
    ),
    planned_at = snapshot$planned_at
  )
}

planning_query <- function(connection, sql, params = NULL) {
  DBI::dbGetQuery(connection, sql, params = params)
}

read_planning_snapshot <- function(store, producer, metadata) {
  connection <- store$connection
  DBI::dbWithTransaction(connection, {
    latest <- planning_query(
      connection,
      paste0(
        "SELECT MAX(committed_at) AS committed_at FROM ",
        quote_identifier(connection, "_graft_batches"),
        " WHERE status = 'committed'"
      )
    )
    current <- planning_query(
      connection,
      paste0(
        "SELECT h.record_id, h.class, h.revision_id, h.revision_number, ",
        "r.record_id AS ledger_record_id, r.class AS ledger_class, ",
        "r.revision_id AS ledger_revision_id, ",
        "r.revision_number AS ledger_revision_number, r.operation, ",
        "r.payload_json, r.content_digest FROM ",
        quote_identifier(connection, "_graft_record_heads"),
        " AS h LEFT JOIN ",
        quote_identifier(connection, "_graft_record_revisions"),
        " AS r ON r.record_id = h.record_id AND r.class = h.class ",
        "AND r.revision_id = h.revision_id ",
        "AND r.revision_number = h.revision_number ",
        "ORDER BY h.class, h.record_id"
      )
    )
    validate_planning_head_snapshot(current)
    identifiers <- planning_query(
      connection,
      planning_identifiers_sql(connection)
    )
    origins <- planning_query(
      connection,
      planning_origins_sql(connection),
      params = list(producer)
    )
    list(
      current = current,
      identifiers = identifiers,
      origins = origins,
      planned_at = commit_plan_snapshot_time(
        connection,
        metadata,
        latest = latest
      ),
      identifier_digest = planning_snapshot_digest(identifiers),
      origin_digest = planning_snapshot_digest(origins)
    )
  })
}

planning_identifiers_sql <- function(connection) {
  paste0(
    "SELECT record_id, class, namespace, value, normalized_value, status ",
    "FROM ",
    quote_identifier(connection, "_graft_identifiers"),
    " WHERE status IN ('primary', 'equivalent') ",
    "ORDER BY class, namespace, normalized_value, record_id"
  )
}

planning_origins_sql <- function(connection) {
  paste0(
    "SELECT record_id, class, producer, origin_key FROM ",
    quote_identifier(connection, "_graft_origins"),
    " WHERE producer = ? ORDER BY class, origin_key, record_id"
  )
}

planning_snapshot_digest <- function(rows) {
  graft_sha256(canonical_json(rows))
}

validate_planning_head_snapshot <- function(heads) {
  dangling <- is.na(heads$ledger_revision_id) |
    heads$ledger_record_id != heads$record_id |
    heads$ledger_class != heads$class |
    heads$ledger_revision_id != heads$revision_id |
    heads$ledger_revision_number != heads$revision_number
  if (any(dangling)) {
    abort_backend_error(
      "A record head does not resolve to its complete ledger revision.",
      operation = "plan_snapshot",
      record_ids = heads$record_id[dangling]
    )
  }
  invisible(heads)
}

normalize_candidate_container <- function(store, records) {
  issues <- list()
  staged <- list()
  if (!is.list(records) || is.data.frame(records)) {
    issues[[1L]] <- new_plan_issue(
      field = "records",
      rule = "named_class_data_frames",
      message = "`records` must be a named list of data frames."
    )
    return(list(staged = staged, issues = issues))
  }
  record_names <- names(records)
  if (is.null(record_names)) {
    issues[[1L]] <- new_plan_issue(
      field = "records",
      rule = "unique_class_names",
      message = "`records` must have unique, non-empty class names."
    )
    return(list(staged = staged, issues = issues))
  }
  invalid_names <- which(is.na(record_names) | !nzchar(record_names))
  for (index in invalid_names) {
    issues[[length(issues) + 1L]] <- new_plan_issue(
      field = "records",
      rule = "unique_class_names",
      message = "A record class name is missing or empty."
    )
  }
  duplicated_names <- unique(record_names[duplicated(record_names)])
  for (record_class in duplicated_names) {
    issues[[length(issues) + 1L]] <- new_plan_issue(
      record_class = record_class,
      field = "records",
      rule = "unique_class_names",
      message = paste0(
        "Record class `",
        record_class,
        "` occurs more than once."
      )
    )
  }
  usable <- which(
    !is.na(record_names) &
      nzchar(record_names) &
      !record_names %in% duplicated_names
  )
  known <- names(store$schema$manifest$classes)
  for (index in usable) {
    record_class <- record_names[[index]]
    data <- records[[index]]
    if (!record_class %in% known) {
      issues[[length(issues) + 1L]] <- new_plan_issue(
        record_class = record_class,
        field = "records",
        rule = "known_concrete_class",
        message = paste0("Unknown concrete record class `", record_class, "`.")
      )
      next
    }
    if (!is.data.frame(data)) {
      issues[[length(issues) + 1L]] <- new_plan_issue(
        record_class = record_class,
        field = record_class,
        rule = "data_frame",
        message = paste0("`", record_class, "` must contain a data frame.")
      )
      next
    }
    class_result <- normalize_candidate_class(
      record_class,
      data,
      store$schema$manifest$classes[[record_class]]
    )
    staged[[record_class]] <- class_result$staged
    issues <- c(issues, class_result$issues)
  }
  list(staged = staged, issues = issues)
}

normalize_candidate_class <- function(record_class, data, contract) {
  issues <- list()
  if (anyDuplicated(names(data))) {
    issues[[1L]] <- new_plan_issue(
      record_class = record_class,
      field = "records",
      rule = "unique_field_names",
      message = paste0("`", record_class, "` contains duplicate fields.")
    )
    return(list(
      staged = empty_candidate_class(record_class, contract),
      issues = issues
    ))
  }
  allowed <- c(names(contract$slots), ".graft_origin_key")
  unknown <- setdiff(names(data), allowed)
  for (field in unknown) {
    issues[[length(issues) + 1L]] <- new_plan_issue(
      record_class = record_class,
      field = field,
      rule = "known_field",
      message = paste0("Unknown field `", record_class, ".", field, "`.")
    )
  }
  data <- data[setdiff(names(data), unknown)]
  normalized <- list()
  invalid_fields <- character()
  for (slot_name in names(contract$slots)) {
    slot <- contract$slots[[slot_name]]
    source <- if (slot_name %in% names(data)) data[[slot_name]] else NULL
    values <- if (scalar_logical(slot$multivalued)) {
      rep(list(missing_slot_vector(slot, 0L)), nrow(data))
    } else {
      missing_slot_vector(slot, nrow(data))
    }
    for (index in seq_len(nrow(data))) {
      result <- normalize_candidate_value(
        source,
        index,
        slot,
        record_class
      )
      if (!is.null(result$issue)) {
        issues[[length(issues) + 1L]] <- result$issue
        invalid_fields <- c(
          invalid_fields,
          candidate_field_key(index, slot_name)
        )
      }
      if (!is.null(result$value)) {
        values[[index]] <- result$value
      }
    }
    normalized[[slot_name]] <- if (scalar_logical(slot$multivalued)) {
      I(values)
    } else {
      values
    }
  }
  origin <- rep(NA_character_, nrow(data))
  if (".graft_origin_key" %in% names(data)) {
    source <- data[[".graft_origin_key"]]
    if (!is.character(source) && !is.factor(source)) {
      for (index in seq_len(nrow(data))) {
        issues[[length(issues) + 1L]] <- new_plan_issue(
          record_class = record_class,
          input_row = index,
          field = ".graft_origin_key",
          rule = "character",
          message = "`.graft_origin_key` must be a character value."
        )
      }
    } else {
      origin <- trimws(as.character(source))
      origin[is.na(origin) | !nzchar(origin)] <- NA_character_
    }
  }
  normalized <- as.data.frame(
    normalized,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    optional = TRUE
  )
  identities <- vector("list", nrow(normalized))
  for (index in seq_len(nrow(normalized))) {
    row <- normalized[index, , drop = FALSE]
    external <- external_identifiers_for_row(contract, row)
    for (slot_name in names(external$normalized_slots)) {
      normalized[[slot_name]][[index]] <- external$normalized_slots[[slot_name]]
    }
    derived <- derive_origin_key(contract, row)
    if (!is.na(origin[[index]])) {
      derived <- origin[[index]]
    }
    identities[[index]] <- list(
      supplied_id = scalar_character(row$id[[1L]]),
      origin_key = derived,
      identifiers = external$identifiers
    )
  }
  list(
    staged = list(
      class = record_class,
      contract = contract,
      data = normalized,
      input_row = seq_len(nrow(normalized)),
      invalid_fields = unique(invalid_fields),
      identities = identities
    ),
    issues = issues
  )
}

empty_candidate_class <- function(record_class, contract) {
  data <- lapply(contract$slots, function(slot) {
    if (scalar_logical(slot$multivalued)) {
      return(I(list()))
    }
    missing_slot_vector(slot, 0L)
  })
  list(
    class = record_class,
    contract = contract,
    data = as.data.frame(data, check.names = FALSE, optional = TRUE),
    input_row = integer(),
    invalid_fields = character(),
    identities = list()
  )
}

normalize_candidate_value <- function(source, index, slot, record_class) {
  slot_name <- scalar_character(slot$name)
  multivalued <- scalar_logical(slot$multivalued)
  if (is.null(source)) {
    return(list(value = if (multivalued) NULL else NULL, issue = NULL))
  }
  if (multivalued && !is.list(source)) {
    return(list(
      value = NULL,
      issue = new_plan_issue(
        record_class = record_class,
        input_row = index,
        field = slot_name,
        rule = "list_column",
        message = paste0(
          "Multivalued field `",
          record_class,
          ".",
          slot_name,
          "` must be a list-column."
        )
      )
    ))
  }
  raw <- if (is.list(source) && !inherits(source, "POSIXt")) {
    source[[index]]
  } else {
    source[index]
  }
  if (is.null(raw) || length(raw) == 0L) {
    return(list(value = NULL, issue = NULL))
  }
  if (!multivalued && length(raw) != 1L) {
    return(list(
      value = NULL,
      issue = new_plan_issue(
        record_class = record_class,
        input_row = index,
        field = slot_name,
        rule = "scalar_column",
        message = paste0(
          "Scalar field `",
          record_class,
          ".",
          slot_name,
          "` must contain one value."
        )
      )
    ))
  }
  missing_candidate <- if (is.factor(raw)) as.character(raw) else raw
  if (
    !multivalued &&
      !scalar_logical(slot$identifier) &&
      is_missing_value(missing_candidate)
  ) {
    return(list(value = NULL, issue = NULL))
  }
  if (scalar_logical(slot$object_reference)) {
    if (is.factor(raw)) {
      raw <- as.character(raw)
    }
    if (!is.character(raw)) {
      return(list(
        value = NULL,
        issue = new_plan_issue(
          record_class = record_class,
          input_row = index,
          field = slot_name,
          rule = "object_reference_type",
          message = paste0(
            "Object field `",
            record_class,
            ".",
            slot_name,
            "` must contain identifiers."
          )
        )
      ))
    }
    return(list(value = as.character(raw), issue = NULL))
  }
  converted <- coerce_candidate_vector(raw, slot)
  if (is.null(converted) || length(converted) != length(raw)) {
    type <- validation_slot_type(slot)
    range <- scalar_character(slot$range)
    issue_type <- if (
      identical(type, "VARCHAR") &&
        range %in% c("uri", "uriorcurie")
    ) {
      range
    } else {
      tolower(type)
    }
    return(list(
      value = NULL,
      issue = new_plan_issue(
        record_class = record_class,
        input_row = index,
        field = slot_name,
        rule = paste0("type_", issue_type),
        message = paste0(
          "Field `",
          record_class,
          ".",
          slot_name,
          "` cannot be coerced to ",
          type,
          "."
        )
      )
    ))
  }
  if (
    !multivalued &&
      !scalar_logical(slot$identifier) &&
      is_missing_value(converted)
  ) {
    return(list(value = NULL, issue = NULL))
  }
  list(value = converted, issue = NULL)
}

coerce_candidate_vector <- function(x, slot) {
  switch(
    validation_slot_type(slot),
    VARCHAR = if (scalar_character(slot$range) %in% c("uri", "uriorcurie")) {
      coerce_linkml_reference(x, scalar_character(slot$range))
    } else if (is.factor(x)) {
      as.character(x)
    } else if (is.character(x)) {
      x
    },
    DOUBLE = coerce_numeric(x, integer = FALSE),
    DECIMAL = coerce_exact_numeric(x, integer = FALSE),
    BIGINT = coerce_exact_numeric(x, integer = TRUE),
    BOOLEAN = coerce_logical(x),
    DATE = coerce_date(x),
    TIMESTAMP = coerce_timestamp(
      x,
      datetime_format = scalar_character(slot$datetime_format)
    ),
    TIME = coerce_time(x),
    NULL
  )
}

validate_candidate_stages <- function(manifest, staged, snapshot, connection) {
  issues <- list()
  for (record_class in names(staged)) {
    result <- validate_candidate_class(
      manifest,
      staged[[record_class]],
      snapshot,
      connection
    )
    staged[[record_class]] <- result$staged
    issues <- c(issues, result$issues)
  }
  references <- validate_candidate_references(manifest, staged, snapshot)
  list(
    staged = staged,
    issues = c(issues, references$issues),
    references = references$references
  )
}

validate_candidate_class <- function(manifest, staged, snapshot, connection) {
  issues <- list()
  for (slot_name in names(staged$contract$slots)) {
    slot <- staged$contract$slots[[slot_name]]
    for (index in seq_len(nrow(staged$data))) {
      if (candidate_field_key(index, slot_name) %in% staged$invalid_fields) {
        next
      }
      value <- staged$data[[slot_name]][[index]]
      missing <- is_missing_value(
        value,
        multivalued = scalar_logical(slot$multivalued)
      )
      if (
        scalar_logical(slot$required) &&
          missing &&
          !identical(slot_name, "id")
      ) {
        issues[[length(issues) + 1L]] <- new_plan_issue(
          record_class = staged$class,
          input_row = index,
          record_id = staged$data$id[[index]],
          field = slot_name,
          rule = "required",
          message = paste0(
            "Required field `",
            staged$class,
            ".",
            slot_name,
            "` is missing."
          )
        )
        next
      }
      if (missing) {
        next
      }
      if (anyNA(value)) {
        issues[[length(issues) + 1L]] <- new_plan_issue(
          record_class = staged$class,
          input_row = index,
          record_id = staged$data$id[[index]],
          field = slot_name,
          rule = "non_missing_collection_values",
          message = paste0(
            "Field `",
            staged$class,
            ".",
            slot_name,
            "` contains a missing collection value."
          )
        )
        next
      }
      issues <- c(
        issues,
        validate_candidate_constraints(
          manifest,
          staged,
          slot,
          value,
          index
        )
      )
    }
  }
  issues <- c(issues, validate_candidate_invariants(staged))
  if (identical(staged$class, graft_definition_class_name)) {
    issues <- c(
      issues,
      validate_definition_candidates(
        manifest,
        staged,
        snapshot$current,
        connection
      )
    )
  }
  list(staged = staged, issues = issues)
}

validate_candidate_constraints <- function(
  manifest,
  staged,
  slot,
  value,
  index
) {
  issues <- list()
  slot_name <- scalar_character(slot$name)
  fixed_predicate <- scalar_character(staged$contract$fixed_predicate)
  if (
    identical(slot_name, "predicate") &&
      !is.na(fixed_predicate) &&
      any(as.character(value) != fixed_predicate)
  ) {
    issues[[length(issues) + 1L]] <- new_plan_issue(
      record_class = staged$class,
      input_row = index,
      record_id = staged$data$id[[index]],
      field = slot_name,
      rule = "fixed_predicate",
      message = paste0(
        "Field `",
        staged$class,
        ".predicate` must equal its fixed predicate `",
        fixed_predicate,
        "`."
      )
    )
  }
  enum_name <- scalar_character(slot$enum)
  if (!is.na(enum_name)) {
    allowed <- vapply(
      manifest$enums[[enum_name]]$permissible_values,
      \(.x) scalar_character(.x$value),
      character(1)
    )
    if (length(setdiff(as.character(value), allowed)) > 0L) {
      issues[[length(issues) + 1L]] <- new_plan_issue(
        record_class = staged$class,
        input_row = index,
        record_id = staged$data$id[[index]],
        field = slot_name,
        rule = "enum_membership",
        message = paste0(
          "Field `",
          staged$class,
          ".",
          slot_name,
          "` has an unknown value."
        )
      )
    }
  }
  pattern <- scalar_character(slot$pattern)
  if (!is.na(pattern) && !all(grepl(pattern, as.character(value)))) {
    issues[[length(issues) + 1L]] <- new_plan_issue(
      record_class = staged$class,
      input_row = index,
      record_id = staged$data$id[[index]],
      field = slot_name,
      rule = "pattern",
      message = paste0(
        "Field `",
        staged$class,
        ".",
        slot_name,
        "` does not match its pattern."
      )
    )
  }
  numeric_value <- suppressWarnings(as.numeric(value))
  if (
    !is.null(slot$minimum_value) &&
      any(
        numeric_value < as.numeric(slot$minimum_value),
        na.rm = TRUE
      )
  ) {
    issues[[length(issues) + 1L]] <- new_plan_issue(
      record_class = staged$class,
      input_row = index,
      record_id = staged$data$id[[index]],
      field = slot_name,
      rule = "minimum_value",
      message = paste0(
        "Field `",
        staged$class,
        ".",
        slot_name,
        "` is below its bound."
      )
    )
  }
  if (
    !is.null(slot$maximum_value) &&
      any(
        numeric_value > as.numeric(slot$maximum_value),
        na.rm = TRUE
      )
  ) {
    issues[[length(issues) + 1L]] <- new_plan_issue(
      record_class = staged$class,
      input_row = index,
      record_id = staged$data$id[[index]],
      field = slot_name,
      rule = "maximum_value",
      message = paste0(
        "Field `",
        staged$class,
        ".",
        slot_name,
        "` is above its bound."
      )
    )
  }
  issues
}

validate_candidate_invariants <- function(staged) {
  issues <- list()
  data <- staged$data
  is_statement <- identical(
    scalar_character(staged$contract$role),
    "statement"
  )
  for (index in seq_len(nrow(data))) {
    if (
      is_statement &&
        all(c("valid_from", "valid_to") %in% names(data))
    ) {
      from <- data$valid_from[[index]]
      to <- data$valid_to[[index]]
      if (!is.na(from) && !is.na(to) && from > to) {
        issues[[length(issues) + 1L]] <- new_plan_issue(
          record_class = staged$class,
          input_row = index,
          record_id = data$id[[index]],
          field = "valid_from,valid_to",
          rule = "valid_time_order",
          message = "`valid_from` must be before or equal to `valid_to`."
        )
      }
    }
    if (
      identical(scalar_character(staged$contract$statement_shape), "semantic")
    ) {
      entity <- data$object_entity[[index]]
      value <- data$object_value[[index]]
      if (sum(c(!is_missing_value(entity), !is_missing_value(value))) != 1L) {
        issues[[length(issues) + 1L]] <- new_plan_issue(
          record_class = staged$class,
          input_row = index,
          record_id = data$id[[index]],
          field = "object_entity,object_value",
          rule = "exactly_one_semantic_object",
          message = "A semantic statement must have exactly one object field."
        )
      }
      if (
        !is_missing_value(value) &&
          is_missing_value(data$object_datatype[[index]])
      ) {
        issues[[length(issues) + 1L]] <- new_plan_issue(
          record_class = staged$class,
          input_row = index,
          record_id = data$id[[index]],
          field = "object_datatype",
          rule = "semantic_literal_datatype",
          message = "A semantic literal object requires `object_datatype`."
        )
      }
    }
    if (is_statement && "superseded_by" %in% names(data)) {
      target <- data$superseded_by[[index]]
      if (!is.na(target) && identical(target, data$id[[index]])) {
        issues[[length(issues) + 1L]] <- new_plan_issue(
          record_class = staged$class,
          input_row = index,
          record_id = data$id[[index]],
          field = "superseded_by",
          rule = "no_self_supersession",
          message = "A statement may not supersede itself."
        )
      }
    }
  }
  issues
}

validate_candidate_references <- function(manifest, staged, snapshot) {
  issues <- list()
  rows <- list()
  staged_classes <- list()
  for (record_class in names(staged)) {
    ids <- staged[[record_class]]$data$id
    for (record_id in unique(ids[!is.na(ids)])) {
      staged_classes[[record_id]] <- unique(c(
        staged_classes[[record_id]],
        record_class
      ))
    }
  }
  available <- snapshot$current$operation != "delete"
  current_classes <- split(
    as.character(snapshot$current$class[available]),
    as.character(snapshot$current$record_id[available])
  )
  for (record_class in names(staged)) {
    class_staged <- staged[[record_class]]
    reference_slots <- Filter(
      \(.x) scalar_logical(.x$object_reference),
      class_staged$contract$slots
    )
    for (slot_name in names(reference_slots)) {
      slot <- reference_slots[[slot_name]]
      expected <- scalar_character(slot$range)
      for (index in seq_len(nrow(class_staged$data))) {
        targets <- class_staged$data[[slot_name]][[index]]
        if (is_missing_value(targets, multivalued = TRUE)) {
          next
        }
        targets <- as.character(targets)
        if (!scalar_logical(slot$ordered) && anyDuplicated(targets)) {
          issues[[length(issues) + 1L]] <- new_plan_issue(
            record_class = record_class,
            input_row = index,
            record_id = class_staged$data$id[[index]],
            field = slot_name,
            rule = "unique_relation_target",
            message = paste0(
              "Unordered relation `",
              record_class,
              ".",
              slot_name,
              "` has a duplicate target."
            )
          )
        }
        for (position in seq_along(targets)) {
          target <- targets[[position]]
          actual <- unique(c(
            staged_classes[[target]],
            current_classes[[target]]
          ))
          format <- reference_id_format(manifest, expected)
          if (!valid_reference_id(target, format)) {
            issues[[length(issues) + 1L]] <- new_plan_issue(
              record_class = record_class,
              input_row = index,
              record_id = class_staged$data$id[[index]],
              field = slot_name,
              rule = "internal_reference_id",
              message = paste0(
                "Reference `",
                target,
                "` has an invalid identifier format."
              ),
              condition_class = "graft_reference_error"
            )
          } else if (length(actual) == 0L) {
            issues[[length(issues) + 1L]] <- new_plan_issue(
              record_class = record_class,
              input_row = index,
              record_id = class_staged$data$id[[index]],
              field = slot_name,
              rule = "reference_exists",
              message = paste0(
                "Reference target `",
                target,
                "` does not exist."
              ),
              condition_class = "graft_reference_error"
            )
          } else if (
            !any(vapply(
              actual,
              \(.x) reference_class_compatible(manifest, expected, .x),
              logical(1)
            ))
          ) {
            issues[[length(issues) + 1L]] <- new_plan_issue(
              record_class = record_class,
              input_row = index,
              record_id = class_staged$data$id[[index]],
              field = slot_name,
              rule = "reference_class",
              message = paste0(
                "Reference target `",
                target,
                "` is not compatible with `",
                expected,
                "`."
              ),
              condition_class = "graft_reference_error"
            )
          }
          rows[[length(rows) + 1L]] <- data.frame(
            class = record_class,
            input_row = as.integer(index),
            record_id = scalar_character(class_staged$data$id[[index]], ""),
            field = slot_name,
            target_id = target,
            expected_class = expected,
            position = as.integer(position),
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  references <- if (length(rows) == 0L) {
    empty_candidate_references()
  } else {
    do.call(rbind, rows)
  }
  list(references = references, issues = issues)
}

reference_id_format <- function(manifest, expected) {
  contract <- manifest$classes[[expected]]
  if (!is.null(contract)) {
    return(scalar_character(contract$id_format, "graft"))
  }
  formats <- unique(vapply(
    Filter(
      \(.x) expected %in% empty_character(.x$ancestors),
      manifest$classes
    ),
    \(.x) scalar_character(.x$id_format, "graft"),
    character(1)
  ))
  if (length(formats) == 1L) formats[[1L]] else "mixed"
}

valid_reference_id <- function(target, format) {
  if (identical(format, "graft")) {
    return(is_graft_id(target))
  }
  is.character(target) &&
    length(target) == 1L &&
    !is.na(target) &&
    nzchar(trimws(target))
}

reference_class_compatible <- function(manifest, expected, actual) {
  identical(expected, actual) ||
    expected %in% empty_character(manifest$classes[[actual]]$ancestors)
}

plan_candidate_changes <- function(staged, current, planned_at) {
  capacity <- as.integer(sum(vapply(
    staged,
    \(.x) nrow(.x$data),
    integer(1)
  )))
  row_class <- character(capacity)
  row_input <- integer(capacity)
  row_record_id <- character(capacity)
  row_action <- character(capacity)
  row_payload_json <- character(capacity)
  row_content_digest <- character(capacity)
  row_changed_fields_json <- character(capacity)
  row_expected_revision_id <- rep(NA_character_, capacity)
  row_expected_revision_number <- rep(NA_real_, capacity)
  row_expected_content_digest <- rep(NA_character_, capacity)
  row_identity_reason <- character(capacity)
  row_identity_evidence <- character(capacity)
  change_fields <- character(capacity)
  cursor <- 0L
  current_index <- paste(current$class, current$record_id, sep = "\u001f")
  empty_evidence <- canonical_json(list())
  for (record_class in names(staged)) {
    class_staged <- staged[[record_class]]
    created_at <- if ("created_at" %in% names(class_staged$data)) {
      class_staged$data$created_at
    } else {
      NULL
    }
    updated_at <- if ("updated_at" %in% names(class_staged$data)) {
      class_staged$data$updated_at
    } else {
      NULL
    }
    for (index in seq_len(nrow(class_staged$data))) {
      record_id <- class_staged$data$id[[index]]
      if (is.na(record_id) || !nzchar(record_id)) {
        next
      }
      key <- paste(record_class, record_id, sep = "\u001f")
      current_row <- match(key, current_index)
      has_current <- !is.na(current_row) &&
        !is.na(current$record_id[[current_row]])
      prior <- if (!has_current) {
        NULL
      } else {
        parse_revision_payload(current$payload_json[[current_row]])
      }
      payload <- candidate_record_payload(class_staged, index)
      digest <- logical_record_content_digest(payload)
      deleted <- has_current &&
        identical(current$operation[[current_row]], "delete")
      action <- if (!has_current) {
        "insert"
      } else if (deleted) {
        "update"
      } else if (identical(digest, current$content_digest[[current_row]])) {
        "match"
      } else {
        "update"
      }
      if (!is.null(created_at)) {
        created_at[[index]] <- if (is.null(prior)) {
          planned_at
        } else {
          projection_coerce_timestamps(
            scalar_character(prior$created_at)
          )[[1L]]
        }
        payload["created_at"] <- list(plan_canonical_slot_value(
          created_at[[index]],
          class_staged$contract$slots$created_at
        ))
      }
      if (!is.null(updated_at)) {
        updated_at[[index]] <- if (identical(action, "match")) {
          projection_coerce_timestamps(
            scalar_character(prior$updated_at)
          )[[1L]]
        } else {
          planned_at
        }
        payload["updated_at"] <- list(plan_canonical_slot_value(
          updated_at[[index]],
          class_staged$contract$slots$updated_at
        ))
      }
      changed <- if (identical(action, "match")) {
        character()
      } else {
        logical_record_changed_fields(payload, prior)
      }
      cursor <- cursor + 1L
      row_class[[cursor]] <- record_class
      row_input[[cursor]] <- as.integer(index)
      row_record_id[[cursor]] <- record_id
      row_action[[cursor]] <- action
      row_payload_json[[cursor]] <- canonical_json(payload)
      row_content_digest[[cursor]] <- digest
      row_changed_fields_json[[cursor]] <- changed_fields_json(changed)
      row_identity_reason[[cursor]] <- scalar_character(
        class_staged$identities[[index]]$identity_reason,
        "unresolved"
      )
      row_identity_evidence[[cursor]] <- scalar_character(
        class_staged$identities[[index]]$identity_evidence,
        empty_evidence
      )
      change_fields[[cursor]] <- paste(changed, collapse = ", ")
      if (has_current) {
        row_expected_revision_id[[cursor]] <- current$revision_id[[current_row]]
        row_expected_revision_number[[cursor]] <- as.numeric(
          current$revision_number[[current_row]]
        )
        row_expected_content_digest[[cursor]] <- current$content_digest[[
          current_row
        ]]
      }
    }
    if (!is.null(created_at)) {
      class_staged$data$created_at <- created_at
    }
    if (!is.null(updated_at)) {
      class_staged$data$updated_at <- updated_at
    }
    staged[[record_class]] <- class_staged
  }
  if (cursor == 0L) {
    return(list(
      staged = staged,
      rows = empty_candidate_rows(),
      changes = empty_plan_changes()
    ))
  }
  used <- seq_len(cursor)
  rows <- data.frame(
    class = row_class[used],
    input_row = row_input[used],
    record_id = row_record_id[used],
    action = row_action[used],
    payload_json = row_payload_json[used],
    content_digest = row_content_digest[used],
    changed_fields_json = row_changed_fields_json[used],
    expected_revision_id = row_expected_revision_id[used],
    expected_revision_number = row_expected_revision_number[used],
    expected_content_digest = row_expected_content_digest[used],
    identity_reason = row_identity_reason[used],
    identity_evidence = row_identity_evidence[used],
    stringsAsFactors = FALSE
  )
  changes <- data.frame(
    class = row_class[used],
    input_row = row_input[used],
    record_id = row_record_id[used],
    action = row_action[used],
    changed_fields = change_fields[used],
    expected_revision_id = row_expected_revision_id[used],
    expected_revision_number = row_expected_revision_number[used],
    expected_content_digest = row_expected_content_digest[used],
    proposed_content_digest = row_content_digest[used],
    identity_reason = row_identity_reason[used],
    identity_evidence = row_identity_evidence[used],
    stringsAsFactors = FALSE
  )
  list(
    staged = staged,
    rows = rows,
    changes = changes
  )
}

candidate_record_payload <- function(staged, index) {
  payload <- stats::setNames(
    vector("list", length(staged$contract$slots)),
    names(staged$contract$slots)
  )
  for (slot_name in names(staged$contract$slots)) {
    payload[slot_name] <- list(plan_canonical_slot_value(
      staged$data[[slot_name]][[index]],
      staged$contract$slots[[slot_name]]
    ))
  }
  payload
}

plan_canonical_slot_value <- function(value, slot) {
  if (!scalar_logical(slot$multivalued)) {
    return(plan_canonical_slot_scalar(value, slot))
  }
  if (is.null(value) || length(value) == 0L) {
    return(list())
  }
  values <- lapply(value, plan_canonical_slot_scalar, slot = slot)
  if (!scalar_logical(slot$ordered)) {
    keys <- vapply(values, canonical_json, character(1))
    values <- values[order(keys, method = "radix")]
  }
  unname(values)
}

plan_canonical_slot_scalar <- function(value, slot) {
  if (is.null(value) || length(value) == 0L || is.na(value)) {
    return(NULL)
  }
  if (scalar_logical(slot$object_reference)) {
    return(as.character(value))
  }
  switch(
    validation_slot_type(slot),
    BOOLEAN = as.logical(value),
    BIGINT = as.character(value),
    DOUBLE = as.numeric(value),
    DECIMAL = as.character(value),
    DATE = as.Date(value),
    TIMESTAMP = format_candidate_timestamp(value),
    as.character(value)
  )
}

format_candidate_timestamp <- function(value) {
  seconds <- as.numeric(as.POSIXct(value, tz = "UTC"))
  if (is.na(seconds)) {
    return(NA_character_)
  }
  whole_seconds <- floor(seconds)
  microseconds <- round((seconds - whole_seconds) * 1e6)
  if (microseconds == 1e6) {
    whole_seconds <- whole_seconds + 1
    microseconds <- 0
  }
  paste0(
    format(
      as.POSIXct(whole_seconds, origin = "1970-01-01", tz = "UTC"),
      format = "%Y-%m-%dT%H:%M:%S",
      tz = "UTC"
    ),
    sprintf(".%06dZ", microseconds)
  )
}

new_plan_issue <- function(
  record_class = "",
  input_row = NA_integer_,
  record_id = NA_character_,
  field,
  rule,
  message,
  condition_class = "graft_validation_error"
) {
  data.frame(
    class = scalar_character(record_class, ""),
    input_row = as.integer(input_row),
    record_id = scalar_character(record_id, ""),
    field = scalar_character(field, ""),
    rule = scalar_character(rule, ""),
    message = message,
    condition_class = condition_class,
    stringsAsFactors = FALSE
  )
}

bind_plan_issues <- function(issues) {
  if (length(issues) == 0L) {
    return(empty_plan_issues())
  }
  result <- do.call(rbind, issues)
  rownames(result) <- NULL
  order_index <- order(
    result$class,
    is.na(result$input_row),
    result$input_row,
    result$field,
    result$rule,
    result$message,
    method = "radix"
  )
  result[order_index, , drop = FALSE]
}

candidate_field_key <- function(index, field) {
  paste(index, field, sep = "\u001f")
}

empty_candidate_rows <- function() {
  data.frame(
    class = character(),
    input_row = integer(),
    record_id = character(),
    action = character(),
    payload_json = character(),
    content_digest = character(),
    changed_fields_json = character(),
    expected_revision_id = character(),
    expected_revision_number = numeric(),
    expected_content_digest = character(),
    identity_reason = character(),
    identity_evidence = character(),
    stringsAsFactors = FALSE
  )
}

empty_candidate_references <- function() {
  data.frame(
    class = character(),
    input_row = integer(),
    record_id = character(),
    field = character(),
    target_id = character(),
    expected_class = character(),
    position = integer(),
    stringsAsFactors = FALSE
  )
}
