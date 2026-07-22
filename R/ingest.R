#' Atomically ingest one or more record classes
#'
#' All supplied classes, generated multivalue tables, identifiers, origins,
#' observations, and batch metadata commit in one DuckDB transaction. A failure
#' in any class rolls back the entire batch.
#'
#' @param store An initialized, writable `kg_store`.
#' @param batch A [kg_batch()] object.
#' @param records A named list of concrete-class data frames. Multivalued fields
#'   must be list-columns. `.graft_origin_key` is reserved for producer-side
#'   identity.
#' @param mode Ingestion mode. Milestone 1 supports `"upsert"`.
#' @param validate Validation level. Milestone 1 supports `"fast"`.
#'
#' @return A `kg_ingest_result`. A committed producer/idempotency replay returns
#'   the original result with `replay = TRUE` and signals
#'   `graft_batch_replay`.
#' @export
kg_ingest <- function(
  store,
  batch,
  records,
  mode = "upsert",
  validate = "fast"
) {
  started <- proc.time()[["elapsed"]]
  validate_ingest_options(mode, validate)
  validate_initialized_store_for_ingest(store, write = TRUE)
  batch <- as_kg_batch(batch)

  replay <- find_committed_replay(store$connection, batch)
  if (!is.null(replay)) {
    replay$replay <- TRUE
    signal_batch_replay(replay)
    return(replay)
  }

  started_at <- ingest_now()
  result <- with_duckdb_error(
    "ingest",
    DBI::dbWithTransaction(store$connection, {
      verify_initialized_store(store, activate = TRUE)
      metadata <- read_store_metadata(store$connection)
      build_digest <- scalar_character(
        store$schema$manifest$fingerprints$build_digest
      )
      if (!identical(metadata$active_build_digest, build_digest)) {
        abort_backend_error(
          "The active store schema does not match the ingestion schema.",
          operation = "ingest",
          active_build_digest = metadata$active_build_digest,
          build_digest = build_digest
        )
      }
      commit_order <- next_metadata_order(
        store$connection,
        "_graft_batches",
        "commit_order"
      )
      insert_started_batch(
        store$connection,
        batch,
        started_at,
        build_digest,
        commit_order
      )
      staged <- prepare_ingest_records(store, batch, records, started_at)
      staged <- write_staged_revisions(
        store,
        batch,
        staged,
        started_at,
        commit_order
      )
      write_staged_records(store, staged, started_at)
      write_staged_identifiers(store, batch, staged, started_at)
      write_staged_lineage(store, batch, staged, started_at)
      result <- result_from_staged(
        batch$batch_id,
        staged,
        proc.time()[["elapsed"]] - started
      )
      committed_at <- ingest_now()
      commit_batch(store$connection, batch, result, committed_at)
      result
    })
  )
  result
}

#' Ingest one concrete record class
#'
#' `kg_write()` is a convenience wrapper around the atomic [kg_ingest()]
#' contract.
#'
#' @param store An initialized, writable `kg_store`.
#' @param batch A [kg_batch()] object.
#' @param class One concrete class name.
#' @param records A data frame for `class`.
#' @param mode,validate Passed to [kg_ingest()].
#'
#' @return A `kg_ingest_result`.
#' @export
kg_write <- function(
  store,
  batch,
  class,
  records,
  mode = "upsert",
  validate = "fast"
) {
  if (
    !is.character(class) ||
      length(class) != 1L ||
      is.na(class) ||
      !nzchar(class)
  ) {
    abort_validation_error(
      "`class` must be one non-empty concrete class name.",
      field = "class",
      rule = "scalar_character",
      observed_value = class
    )
  }
  input <- list(records)
  names(input) <- class
  kg_ingest(
    store,
    batch = batch,
    records = input,
    mode = mode,
    validate = validate
  )
}

validate_ingest_options <- function(mode, validate) {
  if (!identical(mode, "upsert")) {
    abort_validation_error(
      "`mode` must be \"upsert\".",
      field = "mode",
      rule = "supported_mode",
      observed_value = mode
    )
  }
  if (!identical(validate, "fast")) {
    abort_validation_error(
      "`validate` must be \"fast\".",
      field = "validate",
      rule = "supported_validation_level",
      observed_value = validate
    )
  }
  invisible(TRUE)
}

validate_initialized_store_for_ingest <- function(
  store,
  write = FALSE,
  refresh = FALSE
) {
  validate_kg_store(store)
  if (
    !isTRUE(write) &&
      !isTRUE(refresh) &&
      store_schema_is_verified(store) &&
      store_metadata_is_verified(store)
  ) {
    return(invisible(store))
  }
  clear_store_verification(store)
  if (!duckdb_table_exists(store$connection, "_graft_store")) {
    abort_backend_error(
      "The kg_store must be initialized with `kg_init()` before ingestion.",
      operation = if (write) "ingest" else "validate_data",
      store_path = store$path
    )
  }
  if (write) {
    validate_store_writable(store, "ingest")
  }
  verify_initialized_store(store, activate = FALSE)
  mark_store_verified(store)
  invisible(store)
}

insert_started_batch <- function(
  connection,
  batch,
  now,
  schema_build_digest,
  commit_order
) {
  row <- data.frame(
    batch_id = batch$batch_id,
    schema_build_digest = schema_build_digest,
    commit_order = commit_order,
    producer = batch$producer,
    producer_version = batch$producer_version,
    source_run_id = batch$source_run_id,
    idempotency_key = batch$idempotency_key,
    metadata_json = batch_metadata_json(batch$metadata),
    started_at = now,
    committed_at = as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC"),
    status = "started",
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(connection, "_graft_batches", row)
  invisible(batch)
}

commit_batch <- function(connection, batch, result, committed_at) {
  sql <- paste0(
    "UPDATE ",
    quote_identifier(connection, "_graft_batches"),
    " SET ",
    quote_identifier(connection, "metadata_json"),
    " = ?, ",
    quote_identifier(connection, "committed_at"),
    " = ?, ",
    quote_identifier(connection, "status"),
    " = 'committed' WHERE ",
    quote_identifier(connection, "batch_id"),
    " = ?"
  )
  DBI::dbExecute(
    connection,
    sql,
    params = list(
      batch_metadata_json(batch$metadata, result),
      committed_at,
      batch$batch_id
    )
  )
  invisible(result)
}

batch_metadata_json <- function(metadata, result = NULL) {
  payload <- list(metadata = metadata)
  if (!is.null(result)) {
    payload$graft_result <- list(
      batch_id = result$batch_id,
      inserted = as.list(result$inserted),
      updated = as.list(result$updated),
      matched = as.list(result$matched),
      observed = as.list(result$observed),
      warnings = result$warnings,
      duration = result$duration
    )
  }
  as.character(jsonlite::toJSON(
    payload,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    POSIXt = "ISO8601",
    UTC = TRUE
  ))
}

find_committed_replay <- function(connection, batch) {
  if (is.na(batch$idempotency_key)) {
    return(NULL)
  }
  sql <- paste0(
    "SELECT batch_id, metadata_json FROM ",
    quote_identifier(connection, "_graft_batches"),
    " WHERE ",
    quote_identifier(connection, "producer"),
    " = ? AND ",
    quote_identifier(connection, "idempotency_key"),
    " = ? AND ",
    quote_identifier(connection, "status"),
    " = 'committed'"
  )
  rows <- DBI::dbGetQuery(
    connection,
    sql,
    params = list(batch$producer, batch$idempotency_key)
  )
  if (nrow(rows) == 0L) {
    return(NULL)
  }
  if (nrow(rows) > 1L) {
    abort_backend_error(
      "A producer/idempotency key has multiple committed batches.",
      operation = "batch_replay",
      producer = batch$producer,
      idempotency_key = batch$idempotency_key
    )
  }
  payload <- tryCatch(
    jsonlite::fromJSON(rows$metadata_json[[1L]], simplifyVector = FALSE),
    error = \(.x) list()
  )
  stored <- payload$graft_result
  if (is.null(stored)) {
    return(derive_replay_result(connection, rows$batch_id[[1L]]))
  }
  new_kg_ingest_result(
    batch_id = rows$batch_id[[1L]],
    inserted = result_counts(stored$inserted),
    updated = result_counts(stored$updated),
    matched = result_counts(stored$matched),
    observed = result_counts(stored$observed),
    warnings = empty_character(stored$warnings),
    duration = as.numeric(stored$duration[[1L]]),
    replay = TRUE
  )
}

result_counts <- function(x) {
  if (is.null(x)) {
    return(stats::setNames(integer(), character()))
  }
  stats::setNames(
    as.integer(unlist(x, use.names = FALSE)),
    names(x)
  )
}

derive_replay_result <- function(connection, batch_id) {
  observations <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT class, COUNT(*) AS n FROM ",
      quote_identifier(connection, "_graft_record_observations"),
      " WHERE batch_id = ? GROUP BY class"
    ),
    params = list(batch_id)
  )
  observed <- stats::setNames(
    as.integer(observations$n),
    observations$class
  )
  inserted_rows <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT class, COUNT(*) AS n FROM ",
      quote_identifier(connection, "_graft_record_origins"),
      " WHERE first_batch_id = ? GROUP BY class"
    ),
    params = list(batch_id)
  )
  inserted <- stats::setNames(
    as.integer(inserted_rows$n),
    inserted_rows$class
  )
  classes <- union(names(observed), names(inserted))
  inserted <- counts_for_classes(inserted, classes)
  new_kg_ingest_result(
    batch_id = batch_id,
    inserted = inserted,
    updated = stats::setNames(integer(length(classes)), classes),
    matched = observed - inserted,
    observed = observed,
    replay = TRUE
  )
}

write_staged_records <- function(store, staged, now) {
  for (record_class in names(staged)) {
    class_staged <- staged[[record_class]]
    table <- scalar_character(class_staged$contract$table)
    changed <- class_staged$disposition %in% c("inserted", "updated")
    if (!any(changed)) {
      next
    }
    updated_ids <- class_staged$data$id[
      class_staged$disposition == "updated"
    ]
    delete_records_by_id(store$connection, table, updated_ids)
    DBI::dbAppendTable(
      store$connection,
      table,
      class_staged$data[changed, , drop = FALSE]
    )
    write_generated_relations(store, class_staged, changed, now)
  }
  invisible(staged)
}

delete_records_by_id <- function(connection, table, ids) {
  for (record_id in ids) {
    sql <- paste0(
      "DELETE FROM ",
      quote_identifier(connection, table),
      " WHERE ",
      quote_identifier(connection, "id"),
      " = ?"
    )
    DBI::dbExecute(connection, sql, params = list(record_id))
  }
  invisible(connection)
}

write_generated_relations <- function(store, staged, changed, now) {
  relations <- Filter(
    \(.x) identical(scalar_character(.x$owner_class), staged$class),
    store$schema$manifest$relations
  )
  for (relation in relations) {
    slot <- scalar_character(relation$slot)
    for (index in which(changed)) {
      owner_id <- staged$data$id[[index]]
      values <- staged$multivalues[[slot]][[index]]
      synchronize_generated_relation(
        store$connection,
        relation,
        owner_id,
        values,
        now
      )
    }
  }
  invisible(staged)
}

synchronize_generated_relation <- function(
  connection,
  relation,
  owner_id,
  values,
  now
) {
  table <- scalar_character(relation$table)
  kind <- scalar_character(relation$kind)
  owner_column <- if (identical(kind, "object")) "subject" else "owner_id"
  value_column <- if (identical(kind, "object")) "object" else "value"
  ordered <- scalar_logical(relation$ordered)
  columns <- vapply(
    relation$columns,
    \(.x) scalar_character(.x$name),
    character(1)
  )
  sql <- paste0(
    "SELECT * FROM ",
    quote_identifier(connection, table),
    " WHERE ",
    quote_identifier(connection, owner_column),
    " = ?",
    if (ordered && "position" %in% columns) " ORDER BY position" else ""
  )
  existing <- DBI::dbGetQuery(connection, sql, params = list(owner_id))
  if (is.null(values)) {
    values <- character()
  }
  retained <- logical(nrow(existing))
  final <- vector("list", length(values))
  slot <- relation_value_slot(relation)
  for (index in seq_along(values)) {
    candidates <- which(
      !retained &
        vapply(
          existing[[value_column]],
          relation_value_equal,
          logical(1),
          values[[index]],
          slot
        )
    )
    if (length(candidates) > 0L) {
      candidate <- candidates[[1L]]
      retained[[candidate]] <- TRUE
      row <- existing[candidate, , drop = FALSE]
      if (ordered && "position" %in% columns) {
        row$position <- as.numeric(index)
      }
      final[[index]] <- row
    } else {
      final[[index]] <- generated_relation_rows(
        relation,
        owner_id,
        values[[index]],
        now,
        position = index
      )
    }
  }
  delete_relation_owner(connection, relation, owner_id)
  if (length(final) > 0L) {
    final <- lapply(final, function(row) {
      row[[value_column]] <- canonical_slot_scalar(
        row[[value_column]][[1L]],
        slot
      )
      row
    })
    rows <- do.call(rbind, final)
    rownames(rows) <- NULL
    DBI::dbAppendTable(connection, table, rows)
  }
  invisible(connection)
}

relation_value_equal <- function(existing, incoming, slot) {
  identical(
    canonical_json(canonical_slot_scalar(existing, slot)),
    canonical_json(canonical_slot_scalar(incoming, slot))
  )
}

delete_relation_owner <- function(connection, relation, owner_id) {
  owner_column <- if (identical(scalar_character(relation$kind), "object")) {
    "subject"
  } else {
    "owner_id"
  }
  sql <- paste0(
    "DELETE FROM ",
    quote_identifier(connection, scalar_character(relation$table)),
    " WHERE ",
    quote_identifier(connection, owner_column),
    " = ?"
  )
  DBI::dbExecute(connection, sql, params = list(owner_id))
  invisible(connection)
}

generated_relation_rows <- function(
  relation,
  owner_id,
  values,
  now,
  position = seq_along(values)
) {
  columns <- vapply(
    relation$columns,
    \(.x) scalar_character(.x$name),
    character(1)
  )
  rows <- vector("list", length(columns))
  names(rows) <- columns
  ordered <- scalar_logical(relation$ordered)
  for (column in columns) {
    rows[[column]] <- switch(
      column,
      id = vapply(values, \(.x) new_graft_id(), character(1)),
      subject = rep(owner_id, length(values)),
      owner_id = rep(owner_id, length(values)),
      object = as.character(values),
      value = unname(values),
      position = if (ordered) {
        as.numeric(position)
      } else {
        rep(NA_real_, length(values))
      },
      created_at = rep(now, length(values)),
      rep(NA, length(values))
    )
  }
  as.data.frame(rows, stringsAsFactors = FALSE, check.names = FALSE)
}

write_staged_identifiers <- function(store, batch, staged, now) {
  connection <- store$connection
  for (class_staged in staged) {
    for (index in seq_along(class_staged$identities)) {
      identity <- class_staged$identities[[index]]
      existing_count <- active_identifier_count(
        connection,
        class_staged$class,
        identity$record_id
      )
      for (identifier in identity$identifiers) {
        existing <- identifier_registry_entry(
          connection,
          class_staged$class,
          identifier$namespace,
          identifier$normalized_value
        )
        if (
          nrow(existing) > 0L &&
            existing$status[[1L]] %in% c("primary", "equivalent")
        ) {
          if (!identical(existing$record_id[[1L]], identity$record_id)) {
            abort_identity_error(
              "An active identifier conflicts with the resolved record.",
              record_class = class_staged$class,
              input_row = index,
              record_id = identity$record_id,
              field = identifier$slot,
              rule = "active_identifier_agreement",
              observed_value = identifier$value,
              matched_record_ids = existing$record_id[[1L]]
            )
          }
          next
        }
        status <- if (existing_count == 0L) "primary" else "equivalent"
        if (nrow(existing) > 0L) {
          promote_identifier_registry_entry(
            connection,
            class_staged$class,
            identifier,
            identity$record_id,
            status,
            batch$producer,
            now
          )
          existing_count <- existing_count + 1L
          next
        }
        row <- data.frame(
          record_id = identity$record_id,
          class = class_staged$class,
          namespace = identifier$namespace,
          value = identifier$value,
          normalized_value = identifier$normalized_value,
          status = status,
          assigned_by = batch$producer,
          confidence = 1,
          created_at = now,
          stringsAsFactors = FALSE
        )
        DBI::dbAppendTable(connection, "_graft_identifiers", row)
        existing_count <- existing_count + 1L
      }
    }
  }
  invisible(staged)
}

active_identifier_count <- function(connection, record_class, record_id) {
  DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT COUNT(*) AS n FROM ",
      quote_identifier(connection, "_graft_identifiers"),
      " WHERE class = ? AND record_id = ?",
      " AND status IN ('primary', 'equivalent')"
    ),
    params = list(record_class, record_id)
  )$n[[1L]]
}

identifier_registry_entry <- function(
  connection,
  record_class,
  namespace,
  normalized_value
) {
  DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT * FROM ",
      quote_identifier(connection, "_graft_identifiers"),
      " WHERE class = ? AND namespace = ? AND normalized_value = ?"
    ),
    params = list(record_class, namespace, normalized_value)
  )
}

promote_identifier_registry_entry <- function(
  connection,
  record_class,
  identifier,
  record_id,
  status,
  producer,
  now
) {
  sql <- paste0(
    "UPDATE ",
    quote_identifier(connection, "_graft_identifiers"),
    " SET record_id = ?, value = ?, status = ?, assigned_by = ?, ",
    "confidence = ?, created_at = ?",
    " WHERE class = ? AND namespace = ? AND normalized_value = ?"
  )
  DBI::dbExecute(
    connection,
    sql,
    params = list(
      record_id,
      identifier$value,
      status,
      producer,
      1,
      now,
      record_class,
      identifier$namespace,
      identifier$normalized_value
    )
  )
  invisible(connection)
}

write_staged_lineage <- function(store, batch, staged, now) {
  connection <- store$connection
  for (class_staged in staged) {
    for (index in seq_along(class_staged$identities)) {
      identity <- class_staged$identities[[index]]
      if (
        !origin_exists(
          connection,
          class_staged$class,
          batch$producer,
          identity$origin_key
        )
      ) {
        origin <- data.frame(
          record_id = identity$record_id,
          class = class_staged$class,
          producer = batch$producer,
          origin_key = identity$origin_key,
          first_batch_id = batch$batch_id,
          created_at = now,
          stringsAsFactors = FALSE
        )
        DBI::dbAppendTable(connection, "_graft_record_origins", origin)
      }
      observation <- data.frame(
        record_id = identity$record_id,
        class = class_staged$class,
        batch_id = batch$batch_id,
        disposition = class_staged$disposition[[index]],
        revision_id = class_staged$revision_ids[[index]],
        observed_at = now,
        stringsAsFactors = FALSE
      )
      DBI::dbAppendTable(
        connection,
        "_graft_record_observations",
        observation
      )
    }
  }
  invisible(staged)
}

origin_exists <- function(connection, record_class, producer, origin_key) {
  DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT COUNT(*) AS n FROM ",
      quote_identifier(connection, "_graft_record_origins"),
      " WHERE class = ? AND producer = ? AND origin_key = ?"
    ),
    params = list(record_class, producer, origin_key)
  )$n[[1L]] >
    0L
}

result_from_staged <- function(batch_id, staged, duration) {
  classes <- names(staged)
  count <- function(disposition) {
    stats::setNames(
      vapply(
        staged,
        \(.x) sum(.x$disposition == disposition),
        integer(1)
      ),
      classes
    )
  }
  observed <- stats::setNames(
    vapply(staged, \(.x) nrow(.x$data), integer(1)),
    classes
  )
  new_kg_ingest_result(
    batch_id = batch_id,
    inserted = count("inserted"),
    updated = count("updated"),
    matched = count("matched"),
    observed = observed,
    duration = duration
  )
}

counts_for_classes <- function(counts, classes) {
  result <- stats::setNames(integer(length(classes)), classes)
  result[intersect(names(counts), classes)] <- counts[
    intersect(names(counts), classes)
  ]
  result
}
