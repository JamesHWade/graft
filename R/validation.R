#' Validate records without writing them
#'
#' Preflight validation performs the same normalization, identity, shape, and
#' reference checks used by [kg_ingest()] without creating a batch or mutating
#' the store.
#'
#' @param store An initialized `kg_store`.
#' @param records A named list of concrete-class data frames.
#'
#' @return A `kg_validation_report`.
#' @export
kg_validate_data <- function(store, records) {
  validate_initialized_store_for_ingest(store, write = FALSE)
  batch <- new_kg_batch(
    batch_id = new_graft_id(),
    producer = "graft-preflight",
    producer_version = NA_character_,
    source_run_id = NA_character_,
    idempotency_key = NA_character_,
    metadata = list()
  )
  failure <- tryCatch(
    {
      prepare_ingest_records(store, batch, records)
      NULL
    },
    graft_validation_error = identity,
    graft_identity_error = identity,
    graft_reference_error = identity,
    graft_schema_error = identity
  )
  if (is.null(failure)) {
    new_kg_validation_report()
  } else {
    new_kg_validation_report(list(failure))
  }
}

prepare_ingest_records <- function(store, batch, records, now = ingest_now()) {
  records <- validate_records_container(store, records)
  state <- new_identity_state()
  staged <- list()
  for (record_class in names(records)) {
    staged[[record_class]] <- normalize_class_records(
      store,
      batch,
      record_class,
      records[[record_class]],
      state,
      now
    )
  }
  validate_staged_records(store, batch, staged)
  staged
}

validate_records_container <- function(store, records) {
  if (!is.list(records) || is.data.frame(records)) {
    abort_validation_error(
      "`records` must be a named list of data frames.",
      field = "records",
      rule = "named_class_data_frames",
      observed_value = records
    )
  }
  record_names <- names(records)
  if (
    is.null(record_names) ||
      anyNA(record_names) ||
      any(!nzchar(record_names)) ||
      anyDuplicated(record_names)
  ) {
    abort_validation_error(
      "`records` must have unique, non-empty concrete class names.",
      field = "records",
      rule = "unique_class_names",
      observed_value = record_names
    )
  }
  known <- names(store$schema$manifest$classes)
  unknown <- setdiff(record_names, known)
  if (length(unknown) > 0L) {
    abort_validation_error(
      paste0(
        "Unknown concrete record class(es): ",
        paste(unknown, collapse = ", "),
        "."
      ),
      record_class = unknown[[1L]],
      field = "records",
      rule = "known_concrete_class",
      observed_value = unknown
    )
  }
  invalid <- record_names[
    !vapply(records, is.data.frame, logical(1))
  ]
  if (length(invalid) > 0L) {
    abort_validation_error(
      paste0(
        "Every record class must contain a data frame; `",
        invalid[[1L]],
        "` does not."
      ),
      record_class = invalid[[1L]],
      field = invalid[[1L]],
      rule = "data_frame",
      observed_value = records[[invalid[[1L]]]]
    )
  }
  records
}

normalize_class_records <- function(
  store,
  batch,
  record_class,
  data,
  state,
  now
) {
  contract <- store$schema$manifest$classes[[record_class]]
  slots <- contract$slots
  allowed <- c(names(slots), ".graft_origin_key")
  unknown <- setdiff(names(data), allowed)
  if (length(unknown) > 0L) {
    abort_validation_error(
      paste0(
        "Unknown field(s) for `",
        record_class,
        "`: ",
        paste(unknown, collapse = ", "),
        "."
      ),
      record_class = record_class,
      field = unknown[[1L]],
      rule = "known_field",
      observed_value = unknown
    )
  }
  if (anyDuplicated(names(data))) {
    abort_validation_error(
      paste0("`", record_class, "` contains duplicate column names."),
      record_class = record_class,
      field = "records",
      rule = "unique_field_names",
      observed_value = names(data)
    )
  }

  scalar_slots <- Filter(
    \(.x) !scalar_logical(.x$multivalued),
    slots
  )
  multivalue_slots <- Filter(
    \(.x) scalar_logical(.x$multivalued),
    slots
  )
  for (slot_name in names(multivalue_slots)) {
    if (!slot_name %in% names(data)) {
      data[[slot_name]] <- rep(list(NULL), nrow(data))
    } else if (!is.list(data[[slot_name]])) {
      abort_validation_error(
        paste0(
          "Multivalued field `",
          record_class,
          ".",
          slot_name,
          "` must be a list-column."
        ),
        record_class = record_class,
        field = slot_name,
        rule = "list_column",
        observed_value = data[[slot_name]]
      )
    } else {
      slot <- multivalue_slots[[slot_name]]
      data[[slot_name]] <- lapply(
        seq_along(data[[slot_name]]),
        function(index) {
          value <- data[[slot_name]][[index]]
          if (is.null(value) || length(value) == 0L) {
            return(NULL)
          }
          if (scalar_logical(slot$object_reference)) {
            if (is.factor(value)) {
              return(as.character(value))
            }
            if (!is.character(value)) {
              abort_validation_error(
                paste0(
                  "Object field `",
                  record_class,
                  ".",
                  slot_name,
                  "` must contain internal graft IDs."
                ),
                record_class = record_class,
                input_row = index,
                field = slot_name,
                rule = "object_reference_type",
                observed_value = value
              )
            }
            return(value)
          }
          coerce_slot_vector(value, slot, record_class)
        }
      )
    }
  }
  for (slot_name in names(scalar_slots)) {
    if (!slot_name %in% names(data)) {
      data[[slot_name]] <- missing_slot_vector(
        scalar_slots[[slot_name]],
        nrow(data)
      )
    } else if (
      is.list(data[[slot_name]]) &&
        !inherits(
          data[[slot_name]],
          "POSIXt"
        )
    ) {
      abort_validation_error(
        paste0(
          "Scalar field `",
          record_class,
          ".",
          slot_name,
          "` may not be a list-column."
        ),
        record_class = record_class,
        field = slot_name,
        rule = "scalar_column",
        observed_value = data[[slot_name]]
      )
    } else {
      data[[slot_name]] <- coerce_slot_vector(
        data[[slot_name]],
        scalar_slots[[slot_name]],
        record_class
      )
    }
  }
  if (".graft_origin_key" %in% names(data)) {
    key <- data[[".graft_origin_key"]]
    if (!is.character(key) && !is.factor(key)) {
      abort_validation_error(
        "`.graft_origin_key` must be a character column.",
        record_class = record_class,
        field = ".graft_origin_key",
        rule = "character",
        observed_value = key
      )
    }
    data[[".graft_origin_key"]] <- as.character(key)
  }

  identities <- vector("list", nrow(data))
  for (index in seq_len(nrow(data))) {
    row <- data[index, , drop = FALSE]
    identity <- resolve_record_identity(
      store,
      batch,
      record_class,
      contract,
      row,
      index,
      state
    )
    data$id[[index]] <- identity$record_id
    for (slot_name in names(identity$normalized_slots)) {
      data[[slot_name]][[index]] <- identity$normalized_slots[[slot_name]]
    }
    identities[[index]] <- identity
  }

  physical_slots <- vapply(
    store$schema$manifest$tables[[record_class]]$columns,
    \(.x) scalar_character(.x$slot, scalar_character(.x$name)),
    character(1)
  )
  physical <- data[physical_slots]
  names(physical) <- vapply(
    store$schema$manifest$tables[[record_class]]$columns,
    \(.x) scalar_character(.x$name),
    character(1)
  )
  disposition <- character(nrow(physical))
  for (index in seq_len(nrow(physical))) {
    current <- existing_record(
      store$connection,
      scalar_character(contract$table),
      physical$id[[index]]
    )
    if (nrow(current) == 0L) {
      disposition[[index]] <- "inserted"
      physical <- set_record_timestamps(
        physical,
        index,
        now,
        existing = NULL
      )
    } else {
      changed <- record_has_changes(physical[index, , drop = FALSE], current)
      disposition[[index]] <- if (changed) "updated" else "matched"
      physical <- set_record_timestamps(
        physical,
        index,
        now,
        existing = current,
        changed = changed
      )
    }
  }
  relations <- Filter(
    \(.x) identical(scalar_character(.x$owner_class), record_class),
    store$schema$manifest$relations
  )
  for (relation in relations) {
    slot_name <- scalar_character(relation$slot)
    for (index in seq_len(nrow(physical))) {
      if (
        !identical(disposition[[index]], "inserted") &&
          generated_relation_has_changes(
            store$connection,
            relation,
            physical$id[[index]],
            data[[slot_name]][[index]]
          )
      ) {
        disposition[[index]] <- "updated"
        physical <- set_record_timestamps(
          physical,
          index,
          now,
          existing = existing_record(
            store$connection,
            scalar_character(contract$table),
            physical$id[[index]]
          ),
          changed = TRUE
        )
      }
    }
  }

  list(
    class = record_class,
    contract = contract,
    data = physical,
    multivalues = data[names(multivalue_slots)],
    identities = identities,
    disposition = disposition,
    input_row = seq_len(nrow(data))
  )
}

generated_relation_has_changes <- function(
  connection,
  relation,
  owner_id,
  values
) {
  kind <- scalar_character(relation$kind)
  owner_column <- if (identical(kind, "object")) "subject" else "owner_id"
  value_column <- if (identical(kind, "object")) "object" else "value"
  columns <- vapply(
    relation$columns,
    \(.x) scalar_character(.x$name),
    character(1)
  )
  selected <- value_column
  if (scalar_logical(relation$ordered) && "position" %in% columns) {
    selected <- c(value_column, "position")
  }
  sql <- paste0(
    "SELECT ",
    paste(quote_identifier(connection, selected), collapse = ", "),
    " FROM ",
    quote_identifier(connection, scalar_character(relation$table)),
    " WHERE ",
    quote_identifier(connection, owner_column),
    " = ?",
    if ("position" %in% selected) " ORDER BY position" else ""
  )
  existing <- DBI::dbGetQuery(connection, sql, params = list(owner_id))
  incoming <- if (is.null(values)) character() else as.character(values)
  stored <- as.character(existing[[value_column]])
  if (!scalar_logical(relation$ordered)) {
    incoming <- sort(incoming)
    stored <- sort(stored)
  }
  !identical(incoming, stored)
}

missing_slot_vector <- function(slot, n) {
  type <- toupper(scalar_character(slot$relational_type, "VARCHAR"))
  switch(
    type,
    BOOLEAN = rep(NA, n),
    BIGINT = rep(NA_real_, n),
    DOUBLE = rep(NA_real_, n),
    DATE = as.Date(rep(NA_character_, n)),
    TIMESTAMP = as.POSIXct(rep(NA_real_, n), origin = "1970-01-01", tz = "UTC"),
    rep(NA_character_, n)
  )
}

coerce_slot_vector <- function(x, slot, record_class) {
  slot_name <- scalar_character(slot$name)
  type <- toupper(scalar_character(slot$relational_type, "VARCHAR"))
  converted <- switch(
    type,
    VARCHAR = {
      if (is.factor(x)) {
        as.character(x)
      } else if (is.character(x)) {
        x
      } else {
        NULL
      }
    },
    DOUBLE = coerce_numeric(x, integer = FALSE),
    DECIMAL = coerce_numeric(x, integer = FALSE),
    BIGINT = coerce_numeric(x, integer = TRUE),
    BOOLEAN = coerce_logical(x),
    DATE = coerce_date(x),
    TIMESTAMP = coerce_timestamp(x),
    TIME = coerce_time(x),
    NULL
  )
  if (is.null(converted) || length(converted) != length(x)) {
    abort_validation_error(
      paste0(
        "Field `",
        record_class,
        ".",
        slot_name,
        "` cannot be coerced to ",
        type,
        "."
      ),
      record_class = record_class,
      field = slot_name,
      rule = paste0("type_", tolower(type)),
      observed_value = x
    )
  }
  converted
}

coerce_numeric <- function(x, integer = FALSE) {
  if (!is.numeric(x) && !is.character(x) && !is.factor(x)) {
    return(NULL)
  }
  original_missing <- is.na(x)
  value <- suppressWarnings(as.numeric(as.character(x)))
  invalid <- (!original_missing & is.na(value)) |
    is.nan(value) |
    is.infinite(value)
  if (any(invalid)) {
    return(NULL)
  }
  if (integer && any(!is.na(value) & value != trunc(value))) {
    return(NULL)
  }
  value
}

coerce_logical <- function(x) {
  if (is.logical(x)) {
    return(x)
  }
  if (is.numeric(x) && all(is.na(x) | x %in% c(0, 1))) {
    return(as.logical(x))
  }
  if (is.character(x) || is.factor(x)) {
    value <- tolower(as.character(x))
    valid <- is.na(value) | value %in% c("true", "false", "1", "0")
    if (!all(valid)) {
      return(NULL)
    }
    return(ifelse(is.na(value), NA, value %in% c("true", "1")))
  }
  NULL
}

coerce_date <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }
  if (!is.character(x)) {
    return(NULL)
  }
  value <- suppressWarnings(as.Date(x))
  if (any(!is.na(x) & is.na(value))) {
    return(NULL)
  }
  value
}

coerce_timestamp <- function(x) {
  if (inherits(x, "POSIXt")) {
    return(as.POSIXct(x, tz = "UTC"))
  }
  if (inherits(x, "Date")) {
    return(as.POSIXct(x, tz = "UTC"))
  }
  if (!is.character(x)) {
    return(NULL)
  }
  value <- suppressWarnings(as.POSIXct(
    x,
    tz = "UTC",
    tryFormats = c(
      "%Y-%m-%dT%H:%M:%OSZ",
      "%Y-%m-%dT%H:%M:%OS%z",
      "%Y-%m-%d %H:%M:%OS",
      "%Y-%m-%d"
    )
  ))
  if (any(!is.na(x) & is.na(value))) {
    return(NULL)
  }
  value
}

coerce_time <- function(x) {
  if (!is.character(x)) {
    return(NULL)
  }
  valid <- is.na(x) | grepl("^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$", x)
  if (!all(valid)) {
    return(NULL)
  }
  x
}

existing_record <- function(connection, table, record_id) {
  sql <- paste0(
    "SELECT * FROM ",
    quote_identifier(connection, table),
    " WHERE ",
    quote_identifier(connection, "id"),
    " = ?"
  )
  DBI::dbGetQuery(connection, sql, params = list(record_id))
}

record_has_changes <- function(incoming, current) {
  fields <- setdiff(names(incoming), c("created_at", "updated_at"))
  if (length(fields) == 0L) {
    return(FALSE)
  }
  !isTRUE(all.equal(
    incoming[fields],
    current[fields],
    check.attributes = FALSE
  ))
}

set_record_timestamps <- function(
  data,
  index,
  now,
  existing = NULL,
  changed = TRUE
) {
  if ("created_at" %in% names(data)) {
    data$created_at[[index]] <- if (is.null(existing)) {
      now
    } else {
      existing$created_at[[1L]]
    }
  }
  if ("updated_at" %in% names(data)) {
    data$updated_at[[index]] <- if (!is.null(existing) && !isTRUE(changed)) {
      existing$updated_at[[1L]]
    } else {
      now
    }
  }
  data
}

validate_staged_records <- function(store, batch, staged) {
  validate_staged_uniqueness(batch, staged)
  for (record_class in names(staged)) {
    validate_class_records(store, staged[[record_class]])
  }
  validate_staged_references(store, staged)
  invisible(staged)
}

validate_staged_uniqueness <- function(batch, staged) {
  ids <- unlist(lapply(staged, \(.x) .x$data$id), use.names = FALSE)
  duplicate <- unique(ids[duplicated(ids)])
  if (length(duplicate) > 0L) {
    location <- locate_staged_record(staged, duplicate[[1L]])
    abort_validation_error(
      paste0(
        "Internal ID `",
        duplicate[[1L]],
        "` occurs more than once in the batch."
      ),
      record_class = location$class,
      input_row = location$row,
      record_id = duplicate[[1L]],
      field = "id",
      rule = "unique_batch_id",
      observed_value = duplicate[[1L]]
    )
  }
  origins <- unlist(
    lapply(staged, function(class_staged) {
      vapply(
        class_staged$identities,
        \(.x) .x$origin_key,
        character(1)
      )
    }),
    use.names = FALSE
  )
  origin_classes <- unlist(
    lapply(staged, function(class_staged) {
      rep(class_staged$class, length(class_staged$identities))
    }),
    use.names = FALSE
  )
  present <- !is.na(origins)
  keys <- paste(
    origin_classes[present],
    batch$producer,
    origins[present],
    sep = "\u001f"
  )
  duplicate_origin <- unique(keys[duplicated(keys)])
  if (length(duplicate_origin) > 0L) {
    abort_validation_error(
      "A producer origin key occurs more than once for a class in the batch.",
      record_class = strsplit(
        duplicate_origin[[1L]],
        "\u001f",
        fixed = TRUE
      )[[1L]][[1L]],
      field = ".graft_origin_key",
      rule = "unique_batch_origin",
      observed_value = duplicate_origin[[1L]]
    )
  }
  invisible(staged)
}

validate_class_records <- function(store, staged) {
  contract <- staged$contract
  scalar <- staged$data
  for (slot_name in names(contract$slots)) {
    slot <- contract$slots[[slot_name]]
    values <- if (scalar_logical(slot$multivalued)) {
      staged$multivalues[[slot_name]]
    } else {
      scalar[[scalar_character(slot$column, slot_name)]]
    }
    for (index in seq_len(nrow(scalar))) {
      value <- if (scalar_logical(slot$multivalued)) {
        values[[index]]
      } else {
        values[[index]]
      }
      validate_slot_value(staged, slot, value, index, store$schema$manifest)
    }
  }
  validate_manifest_invariants(staged)
  invisible(staged)
}

validate_slot_value <- function(staged, slot, value, index, manifest) {
  slot_name <- scalar_character(slot$name)
  missing <- is_missing_value(
    value,
    multivalued = scalar_logical(
      slot$multivalued
    )
  )
  if (scalar_logical(slot$required) && missing) {
    abort_validation_error(
      paste0(
        "Required field `",
        staged$class,
        ".",
        slot_name,
        "` is missing."
      ),
      record_class = staged$class,
      input_row = index,
      record_id = staged$data$id[[index]],
      field = slot_name,
      rule = "required",
      observed_value = value
    )
  }
  if (missing) {
    return(invisible(value))
  }
  if (anyNA(value)) {
    abort_validation_error(
      paste0(
        "Field `",
        staged$class,
        ".",
        slot_name,
        "` contains a missing collection value."
      ),
      record_class = staged$class,
      input_row = index,
      record_id = staged$data$id[[index]],
      field = slot_name,
      rule = "non_missing_collection_values",
      observed_value = value
    )
  }
  enum_name <- scalar_character(slot$enum)
  if (!is.na(enum_name)) {
    allowed <- vapply(
      manifest$enums[[enum_name]]$permissible_values,
      \(.x) scalar_character(.x$value),
      character(1)
    )
    invalid <- setdiff(as.character(value), allowed)
    if (length(invalid) > 0L) {
      abort_validation_error(
        paste0(
          "Field `",
          staged$class,
          ".",
          slot_name,
          "` contains an unrecognized ",
          enum_name,
          " value."
        ),
        record_class = staged$class,
        input_row = index,
        record_id = staged$data$id[[index]],
        field = slot_name,
        rule = "enum_membership",
        observed_value = value,
        permissible_values = allowed
      )
    }
  }
  pattern <- scalar_character(slot$pattern)
  if (!is.na(pattern) && any(!grepl(pattern, as.character(value)))) {
    abort_validation_error(
      paste0(
        "Field `",
        staged$class,
        ".",
        slot_name,
        "` does not match its required pattern."
      ),
      record_class = staged$class,
      input_row = index,
      record_id = staged$data$id[[index]],
      field = slot_name,
      rule = "pattern",
      observed_value = value,
      pattern = pattern
    )
  }
  minimum <- slot$minimum_value
  maximum <- slot$maximum_value
  if (!is.null(minimum) && any(as.numeric(value) < as.numeric(minimum))) {
    abort_validation_error(
      paste0("Field `", staged$class, ".", slot_name, "` is below its bound."),
      record_class = staged$class,
      input_row = index,
      record_id = staged$data$id[[index]],
      field = slot_name,
      rule = "minimum_value",
      observed_value = value,
      minimum_value = minimum
    )
  }
  if (!is.null(maximum) && any(as.numeric(value) > as.numeric(maximum))) {
    abort_validation_error(
      paste0("Field `", staged$class, ".", slot_name, "` is above its bound."),
      record_class = staged$class,
      input_row = index,
      record_id = staged$data$id[[index]],
      field = slot_name,
      rule = "maximum_value",
      observed_value = value,
      maximum_value = maximum
    )
  }
  invisible(value)
}

is_missing_value <- function(value, multivalued = FALSE) {
  if (is.null(value) || length(value) == 0L || all(is.na(value))) {
    return(TRUE)
  }
  if (!multivalued && is.character(value) && all(!nzchar(trimws(value)))) {
    return(TRUE)
  }
  FALSE
}

validate_manifest_invariants <- function(staged) {
  data <- staged$data
  for (index in seq_len(nrow(data))) {
    if (all(c("valid_from", "valid_to") %in% names(data))) {
      from <- data$valid_from[[index]]
      to <- data$valid_to[[index]]
      if (!is.na(from) && !is.na(to) && from > to) {
        abort_validation_error(
          "`valid_from` must be before or equal to `valid_to`.",
          record_class = staged$class,
          input_row = index,
          record_id = data$id[[index]],
          field = "valid_from,valid_to",
          rule = "valid_time_order",
          observed_value = list(valid_from = from, valid_to = to)
        )
      }
    }
    if (
      identical(scalar_character(staged$contract$statement_shape), "semantic")
    ) {
      entity <- data$object_entity[[index]]
      value <- data$object_value[[index]]
      present <- c(!is_missing_value(entity), !is_missing_value(value))
      if (sum(present) != 1L) {
        abort_validation_error(
          "A semantic statement must have exactly one object field.",
          record_class = staged$class,
          input_row = index,
          record_id = data$id[[index]],
          field = "object_entity,object_value",
          rule = "exactly_one_semantic_object",
          observed_value = list(
            object_entity = entity,
            object_value = value
          )
        )
      }
      if (
        !is_missing_value(value) &&
          is_missing_value(data$object_datatype[[index]])
      ) {
        abort_validation_error(
          "A semantic literal object requires `object_datatype`.",
          record_class = staged$class,
          input_row = index,
          record_id = data$id[[index]],
          field = "object_datatype",
          rule = "semantic_literal_datatype",
          observed_value = data$object_datatype[[index]]
        )
      }
    }
    if ("superseded_by" %in% names(data)) {
      target <- data$superseded_by[[index]]
      if (!is.na(target) && identical(target, data$id[[index]])) {
        abort_validation_error(
          "A statement may not supersede itself.",
          record_class = staged$class,
          input_row = index,
          record_id = data$id[[index]],
          field = "superseded_by",
          rule = "no_self_supersession",
          observed_value = target
        )
      }
    }
  }
  invisible(staged)
}

validate_staged_references <- function(store, staged) {
  for (record_class in names(staged)) {
    class_staged <- staged[[record_class]]
    for (slot_name in names(class_staged$contract$slots)) {
      slot <- class_staged$contract$slots[[slot_name]]
      if (!scalar_logical(slot$object_reference)) {
        next
      }
      expected <- scalar_character(slot$range)
      values <- if (scalar_logical(slot$multivalued)) {
        class_staged$multivalues[[slot_name]]
      } else {
        class_staged$data[[scalar_character(slot$column, slot_name)]]
      }
      for (index in seq_len(nrow(class_staged$data))) {
        targets <- if (scalar_logical(slot$multivalued)) {
          values[[index]]
        } else {
          values[[index]]
        }
        if (is_missing_value(targets, multivalued = TRUE)) {
          next
        }
        targets <- as.character(targets)
        if (
          !scalar_logical(slot$ordered) &&
            anyDuplicated(targets)
        ) {
          abort_validation_error(
            paste0(
              "Unordered relation `",
              record_class,
              ".",
              slot_name,
              "` contains a duplicate target."
            ),
            record_class = record_class,
            input_row = index,
            record_id = class_staged$data$id[[index]],
            field = slot_name,
            rule = "unique_relation_target",
            observed_value = targets
          )
        }
        for (target in targets) {
          validate_reference_target(
            store,
            staged,
            record_class,
            index,
            class_staged$data$id[[index]],
            slot_name,
            target,
            expected
          )
        }
      }
    }
  }
  invisible(staged)
}

validate_reference_target <- function(
  store,
  staged,
  record_class,
  input_row,
  record_id,
  field,
  target,
  expected
) {
  if (!is_graft_id(target)) {
    abort_reference_error(
      paste0("Reference `", target, "` is not an internal graft ID."),
      record_class = record_class,
      input_row = input_row,
      record_id = record_id,
      field = field,
      rule = "internal_reference_id",
      observed_value = target,
      expected_class = expected
    )
  }
  actual <- unique(c(
    staged_classes_for_id(staged, target),
    find_existing_id_classes(store, target)
  ))
  compatible <- actual[vapply(
    actual,
    function(actual_class) {
      contract <- store$schema$manifest$classes[[actual_class]]
      identical(expected, actual_class) ||
        expected %in% empty_character(contract$ancestors)
    },
    logical(1)
  )]
  if (length(actual) == 0L) {
    abort_reference_error(
      paste0("Reference target `", target, "` does not exist."),
      record_class = record_class,
      input_row = input_row,
      record_id = record_id,
      field = field,
      rule = "reference_exists",
      observed_value = target,
      expected_class = expected
    )
  }
  if (length(compatible) != 1L) {
    abort_reference_error(
      paste0(
        "Reference target `",
        target,
        "` is not compatible with `",
        expected,
        "`."
      ),
      record_class = record_class,
      input_row = input_row,
      record_id = record_id,
      field = field,
      rule = "reference_class",
      observed_value = target,
      expected_class = expected,
      actual_classes = actual
    )
  }
  invisible(target)
}

staged_classes_for_id <- function(staged, record_id) {
  names(Filter(
    function(class_staged) record_id %in% class_staged$data$id,
    staged
  ))
}

locate_staged_record <- function(staged, record_id) {
  for (record_class in names(staged)) {
    row <- match(record_id, staged[[record_class]]$data$id)
    if (!is.na(row)) {
      return(list(class = record_class, row = row))
    }
  }
  list(class = NA_character_, row = NA_integer_)
}

ingest_now <- function() {
  as.POSIXct(Sys.time(), tz = "UTC")
}
