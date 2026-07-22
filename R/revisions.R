logical_record_payload <- function(class_staged, index) {
  slots <- class_staged$contract$slots
  payload <- stats::setNames(vector("list", length(slots)), names(slots))
  for (slot_name in names(slots)) {
    slot <- slots[[slot_name]]
    value <- if (scalar_logical(slot$multivalued)) {
      class_staged$multivalues[[slot_name]][[index]]
    } else {
      column <- scalar_character(slot$column, slot_name)
      class_staged$data[[column]][[index]]
    }
    payload[slot_name] <- list(canonical_slot_value(value, slot))
  }
  payload
}

canonical_slot_value <- function(value, slot) {
  canonical_slot_type(slot)
  if (!scalar_logical(slot$multivalued)) {
    return(canonical_slot_scalar(value, slot))
  }
  if (is.null(value) || length(value) == 0L) {
    return(list())
  }
  values <- lapply(
    seq_along(value),
    \(index) canonical_slot_scalar(value[[index]], slot)
  )
  if (!scalar_logical(slot$ordered)) {
    keys <- vapply(values, canonical_json, character(1))
    values <- values[order(keys, method = "radix")]
  }
  unname(values)
}

canonical_slot_scalar <- function(value, slot) {
  type <- canonical_slot_type(slot)
  if (is.null(value) || length(value) == 0L) {
    return(NULL)
  }
  if (length(value) != 1L) {
    abort_backend_error(
      "A scalar logical-record value must contain exactly one item.",
      operation = "canonicalize_record",
      field = scalar_character(slot$name),
      value_length = length(value)
    )
  }
  if (scalar_logical(slot$object_reference)) {
    if (is.na(value)) {
      return(NA_character_)
    }
    return(as.character(value))
  }
  if (is.na(value)) {
    return(switch(
      type,
      BOOLEAN = NA,
      BIGINT = NA_real_,
      DOUBLE = NA_real_,
      DECIMAL = NA_real_,
      DATE = as.Date(NA_character_),
      TIME = NA_character_,
      TIMESTAMP = as.POSIXct(
        NA_real_,
        origin = "1970-01-01",
        tz = "UTC"
      ),
      NA_character_
    ))
  }
  switch(
    type,
    BOOLEAN = as.logical(value),
    BIGINT = as.numeric(value),
    DOUBLE = as.numeric(value),
    DECIMAL = as.numeric(value),
    DATE = as.Date(value),
    TIME = canonical_time_value(value),
    TIMESTAMP = as.POSIXct(value, tz = "UTC"),
    as.character(value)
  )
}

canonical_slot_type <- function(slot, operation = "canonicalize_record") {
  type <- toupper(scalar_character(slot$relational_type, "VARCHAR"))
  if (
    scalar_logical(slot$object_reference) &&
      !identical(type, "VARCHAR")
  ) {
    slot_name <- scalar_character(slot$name, "<unknown>")
    abort_schema_error(
      paste0(
        "Object-reference slot `",
        slot_name,
        "` must use relational type `VARCHAR`, not `",
        type,
        "`."
      ),
      operation = operation,
      field = slot_name,
      relational_type = type,
      rule = "object_reference_varchar"
    )
  }
  type
}

canonical_time_value <- function(value) {
  seconds <- if (inherits(value, "difftime")) {
    as.numeric(value, units = "secs")
  } else if (is.numeric(value)) {
    as.numeric(value)
  } else {
    parts <- as.numeric(strsplit(as.character(value), ":", fixed = TRUE)[[1L]])
    if (length(parts) < 2L || length(parts) > 3L || anyNA(parts)) {
      abort_backend_error(
        "A TIME value could not be canonicalized.",
        operation = "canonicalize_record",
        observed_value = value
      )
    }
    parts[[1L]] *
      3600 +
      parts[[2L]] * 60 +
      if (length(parts) == 3L) {
        parts[[3L]]
      } else {
        0
      }
  }
  total_microseconds <- round(seconds * 1e6)
  if (
    !is.finite(total_microseconds) ||
      total_microseconds < 0 ||
      total_microseconds >= 86400 * 1e6
  ) {
    abort_backend_error(
      "A TIME value must be between 00:00:00 and 23:59:59.999999.",
      operation = "canonicalize_record",
      observed_value = value
    )
  }
  hour <- floor(total_microseconds / (3600 * 1e6))
  remainder <- total_microseconds - hour * 3600 * 1e6
  minute <- floor(remainder / (60 * 1e6))
  remainder <- remainder - minute * 60 * 1e6
  second <- floor(remainder / 1e6)
  microsecond <- as.integer(remainder - second * 1e6)
  result <- sprintf("%02d:%02d:%02d", hour, minute, second)
  if (microsecond > 0L) {
    fraction <- sub("0+$", "", sprintf("%06d", microsecond))
    result <- paste0(result, ".", fraction)
  }
  result
}

relation_value_slot <- function(relation) {
  kind <- scalar_character(relation$kind)
  value_column <- if (identical(kind, "object")) "object" else "value"
  columns <- Filter(
    \(column) identical(scalar_character(column$name), value_column),
    relation$columns
  )
  if (length(columns) != 1L) {
    abort_backend_error(
      "A generated relation must declare exactly one value column.",
      operation = "canonicalize_relation",
      relation = scalar_character(relation$name),
      value_column = value_column,
      column_count = length(columns)
    )
  }
  list(
    name = scalar_character(relation$slot),
    relational_type = scalar_character(columns[[1L]]$type),
    object_reference = identical(kind, "object"),
    multivalued = TRUE,
    ordered = scalar_logical(relation$ordered)
  )
}

logical_record_content <- function(payload) {
  payload[setdiff(names(payload), c("created_at", "updated_at"))]
}

logical_record_content_digest <- function(payload) {
  paste0(
    "sha256:",
    digest::digest(
      canonical_json(logical_record_content(payload)),
      algo = "sha256",
      serialize = FALSE
    )
  )
}

logical_record_changed_fields <- function(payload, prior_payload = NULL) {
  content <- logical_record_content(payload)
  if (is.null(prior_payload)) {
    return(sort(names(content), method = "radix"))
  }
  prior_content <- logical_record_content(prior_payload)
  fields <- union(names(content), names(prior_content))
  changed <- fields[vapply(
    fields,
    function(field) {
      current <- canonical_json(list(value = content[[field]]))
      prior <- canonical_json(list(value = prior_content[[field]]))
      !identical(current, prior)
    },
    logical(1)
  )]
  sort(changed, method = "radix")
}

changed_fields_json <- function(fields) {
  canonical_json(unname(as.list(fields)))
}

read_record_head <- function(connection, record_id) {
  sql <- paste0(
    "SELECT h.record_id, h.class, h.revision_id, h.revision_number, ",
    "r.revision_id AS ledger_revision_id, r.payload_json, ",
    "r.content_digest, r.schema_build_digest FROM ",
    quote_identifier(connection, "_graft_record_heads"),
    " h LEFT JOIN ",
    quote_identifier(connection, "_graft_record_revisions"),
    " r ON h.revision_id = r.revision_id WHERE h.record_id = ?"
  )
  DBI::dbGetQuery(connection, sql, params = list(record_id))
}

revision_head_schema <- function(store, head, record_class, record_id) {
  build_digest <- scalar_character(head$schema_build_digest)
  registered <- read_schema_version(store$connection, build_digest)
  if (nrow(registered) != 1L) {
    abort_backend_error(
      "A record revision head does not have exactly one registered schema.",
      operation = "write_record_revision",
      record_id = record_id,
      record_class = record_class,
      build_digest = build_digest,
      schema_count = nrow(registered)
    )
  }
  schema <- schema_from_manifest_json(registered$manifest_json[[1L]])
  if (is.null(schema$manifest$classes[[record_class]])) {
    abort_backend_error(
      "A record revision's historical schema does not declare its class.",
      operation = "write_record_revision",
      record_id = record_id,
      record_class = record_class,
      build_digest = build_digest
    )
  }
  schema
}

project_payload_through_schema <- function(payload, schema, record_class) {
  slot_names <- names(schema$manifest$classes[[record_class]]$slots)
  payload[slot_names]
}

canonical_manifest_payload <- function(payload, contract) {
  slots <- contract$slots
  canonical <- payload
  for (slot_name in names(slots)) {
    if (!scalar_logical(slots[[slot_name]]$object_reference)) {
      next
    }
    canonical[slot_name] <- list(canonical_slot_value(
      payload[[slot_name]],
      slots[[slot_name]]
    ))
  }
  canonical
}

parse_revision_payload <- function(payload_json) {
  tryCatch(
    jsonlite::fromJSON(payload_json, simplifyVector = FALSE),
    error = function(error) {
      abort_backend_error(
        paste0(
          "Could not parse a record revision payload: ",
          conditionMessage(error)
        ),
        operation = "read_record_revision",
        parent = error
      )
    }
  )
}

current_record_payload <- function(store, class_staged, record_id) {
  table <- scalar_character(class_staged$contract$table)
  current <- existing_record(store$connection, table, record_id)
  if (nrow(current) != 1L) {
    abort_backend_error(
      "An existing record must have exactly one current-state row.",
      operation = "write_record_revision",
      record_id = record_id,
      record_class = class_staged$class,
      current_row_count = nrow(current)
    )
  }
  slots <- class_staged$contract$slots
  payload <- stats::setNames(vector("list", length(slots)), names(slots))
  for (slot_name in names(slots)) {
    slot <- slots[[slot_name]]
    value <- if (scalar_logical(slot$multivalued)) {
      current_multivalue(
        store,
        class_staged$class,
        slot_name,
        slot,
        record_id
      )
    } else {
      column <- scalar_character(slot$column, slot_name)
      current[[column]][[1L]]
    }
    payload[slot_name] <- list(canonical_slot_value(value, slot))
  }
  payload
}

current_multivalue <- function(
  store,
  record_class,
  slot_name,
  slot,
  record_id
) {
  relations <- Filter(
    function(relation) {
      identical(scalar_character(relation$owner_class), record_class) &&
        identical(scalar_character(relation$slot), slot_name)
    },
    store$schema$manifest$relations
  )
  if (length(relations) != 1L) {
    abort_backend_error(
      "A multivalued slot must have exactly one generated relation.",
      operation = "write_record_revision",
      record_id = record_id,
      record_class = record_class,
      field = slot_name,
      relation_count = length(relations)
    )
  }
  relation <- relations[[1L]]
  kind <- scalar_character(relation$kind)
  owner_column <- if (identical(kind, "object")) "subject" else "owner_id"
  value_column <- if (identical(kind, "object")) "object" else "value"
  sql <- paste0(
    "SELECT ",
    quote_identifier(store$connection, value_column),
    " FROM ",
    quote_identifier(store$connection, scalar_character(relation$table)),
    " WHERE ",
    quote_identifier(store$connection, owner_column),
    " = ?",
    if (scalar_logical(slot$ordered)) " ORDER BY position" else ""
  )
  DBI::dbGetQuery(
    store$connection,
    sql,
    params = list(record_id)
  )[[value_column]]
}

validate_staged_head <- function(head, record_class, record_id, disposition) {
  if (identical(disposition, "inserted")) {
    if (nrow(head) != 0L) {
      abort_backend_error(
        "An inserted record already has a revision head.",
        operation = "write_record_revision",
        record_id = record_id,
        record_class = record_class
      )
    }
    return(invisible(head))
  }
  if (nrow(head) != 1L) {
    abort_backend_error(
      "An existing record must have exactly one revision head.",
      operation = "write_record_revision",
      record_id = record_id,
      record_class = record_class,
      head_count = nrow(head)
    )
  }
  if (!identical(head$class[[1L]], record_class)) {
    abort_backend_error(
      "A record revision head belongs to a different class.",
      operation = "write_record_revision",
      record_id = record_id,
      record_class = record_class,
      head_class = head$class[[1L]]
    )
  }
  if (
    is.na(head$ledger_revision_id[[1L]]) ||
      !identical(head$ledger_revision_id[[1L]], head$revision_id[[1L]])
  ) {
    abort_backend_error(
      "A record revision head does not reference an existing revision.",
      operation = "write_record_revision",
      record_id = record_id,
      record_class = record_class,
      revision_id = head$revision_id[[1L]]
    )
  }
  invisible(head)
}

write_staged_revisions <- function(
  store,
  batch,
  staged,
  now,
  commit_order
) {
  build_digest <- scalar_character(
    store$schema$manifest$fingerprints$build_digest
  )
  for (record_class in names(staged)) {
    class_staged <- staged[[record_class]]
    revision_ids <- character(nrow(class_staged$data))
    for (index in seq_len(nrow(class_staged$data))) {
      record_id <- class_staged$data$id[[index]]
      disposition <- class_staged$disposition[[index]]
      payload <- logical_record_payload(class_staged, index)
      payload_json <- canonical_json(payload)
      content_digest <- logical_record_content_digest(payload)
      head <- read_record_head(store$connection, record_id)
      validate_staged_head(head, record_class, record_id, disposition)

      if (!identical(disposition, "inserted")) {
        head_schema <- revision_head_schema(
          store,
          head,
          record_class,
          record_id
        )
        current_payload <- current_record_payload(
          store,
          class_staged,
          record_id
        )
        current_digest <- logical_record_content_digest(
          project_payload_through_schema(
            current_payload,
            head_schema,
            record_class
          )
        )
        if (!identical(head$content_digest[[1L]], current_digest)) {
          abort_backend_error(
            "A current-state record differs from its revision head.",
            operation = "write_record_revision",
            record_id = record_id,
            record_class = record_class
          )
        }
      }

      if (identical(disposition, "matched")) {
        comparable_digest <- logical_record_content_digest(
          project_payload_through_schema(
            payload,
            head_schema,
            record_class
          )
        )
        if (!identical(head$content_digest[[1L]], comparable_digest)) {
          abort_backend_error(
            "A matched record differs from its current revision head.",
            operation = "write_record_revision",
            record_id = record_id,
            record_class = record_class
          )
        }
        revision_ids[[index]] <- head$revision_id[[1L]]
        next
      }

      prior_payload <- if (nrow(head) == 0L) {
        NULL
      } else {
        parse_revision_payload(head$payload_json[[1L]])
      }
      if (
        identical(disposition, "updated") &&
          identical(head$content_digest[[1L]], content_digest)
      ) {
        abort_backend_error(
          "An updated record has the same content digest as its current head.",
          operation = "write_record_revision",
          record_id = record_id,
          record_class = record_class
        )
      }
      revision_id <- new_graft_id(now)
      revision_number <- if (nrow(head) == 0L) {
        1
      } else {
        as.numeric(head$revision_number[[1L]]) + 1
      }
      revision <- data.frame(
        revision_id = revision_id,
        record_id = record_id,
        class = record_class,
        batch_id = batch$batch_id,
        schema_build_digest = build_digest,
        revision_number = revision_number,
        operation = if (identical(disposition, "inserted")) {
          "insert"
        } else {
          "update"
        },
        payload_json = payload_json,
        content_digest = content_digest,
        changed_fields_json = changed_fields_json(
          logical_record_changed_fields(payload, prior_payload)
        ),
        prior_revision_id = if (nrow(head) == 0L) {
          NA_character_
        } else {
          head$revision_id[[1L]]
        },
        recorded_at = now,
        commit_order = commit_order,
        stringsAsFactors = FALSE
      )
      DBI::dbAppendTable(
        store$connection,
        "_graft_record_revisions",
        revision
      )
      write_record_head(
        store$connection,
        record_id,
        record_class,
        revision_id,
        revision_number,
        now,
        insert = nrow(head) == 0L
      )
      revision_ids[[index]] <- revision_id
    }
    class_staged$revision_ids <- revision_ids
    staged[[record_class]] <- class_staged
  }
  staged
}

write_record_head <- function(
  connection,
  record_id,
  record_class,
  revision_id,
  revision_number,
  now,
  insert
) {
  if (isTRUE(insert)) {
    row <- data.frame(
      record_id = record_id,
      class = record_class,
      revision_id = revision_id,
      revision_number = revision_number,
      updated_at = now,
      stringsAsFactors = FALSE
    )
    DBI::dbAppendTable(connection, "_graft_record_heads", row)
    return(invisible(connection))
  }
  sql <- paste0(
    "UPDATE ",
    quote_identifier(connection, "_graft_record_heads"),
    " SET revision_id = ?, revision_number = ?, updated_at = ? ",
    "WHERE record_id = ? AND class = ?"
  )
  affected <- DBI::dbExecute(
    connection,
    sql,
    params = list(
      revision_id,
      revision_number,
      now,
      record_id,
      record_class
    )
  )
  if (!identical(as.integer(affected), 1L)) {
    abort_backend_error(
      "Updating a record revision head did not affect exactly one row.",
      operation = "write_record_revision",
      record_id = record_id,
      record_class = record_class,
      affected_rows = affected
    )
  }
  invisible(connection)
}
