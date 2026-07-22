logical_record_payload <- function(class_staged, index) {
  slots <- class_staged$contract$slots
  payload <- stats::setNames(vector("list", length(slots)), names(slots))
  for (slot_name in names(slots)) {
    slot <- slots[[slot_name]]
    if (scalar_logical(slot$multivalued)) {
      value <- class_staged$multivalues[[slot_name]][[index]]
      payload[[slot_name]] <- canonical_multivalue(value, slot)
      next
    }
    column <- scalar_character(slot$column, slot_name)
    payload[slot_name] <- list(unname(class_staged$data[[column]][[index]]))
  }
  payload
}

canonical_multivalue <- function(value, slot) {
  if (is.null(value) || length(value) == 0L) {
    return(list())
  }
  values <- unname(as.list(value))
  if (!scalar_logical(slot$ordered)) {
    keys <- vapply(values, canonical_json, character(1))
    values <- values[order(keys, method = "radix")]
  }
  unname(values)
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
    "r.content_digest FROM ",
    quote_identifier(connection, "_graft_record_heads"),
    " h LEFT JOIN ",
    quote_identifier(connection, "_graft_record_revisions"),
    " r ON h.revision_id = r.revision_id WHERE h.record_id = ?"
  )
  DBI::dbGetQuery(connection, sql, params = list(record_id))
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
    if (scalar_logical(slot$multivalued)) {
      value <- current_multivalue(
        store,
        class_staged$class,
        slot_name,
        slot,
        record_id
      )
      payload[[slot_name]] <- canonical_multivalue(value, slot)
      next
    }
    column <- scalar_character(slot$column, slot_name)
    payload[slot_name] <- list(unname(current[[column]][[1L]]))
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
        current_payload <- current_record_payload(
          store,
          class_staged,
          record_id
        )
        current_digest <- logical_record_content_digest(current_payload)
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
        if (!identical(head$content_digest[[1L]], content_digest)) {
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
