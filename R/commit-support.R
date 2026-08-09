new_commit_batch <- function(
  batch_id,
  producer,
  producer_version,
  source_run_id,
  idempotency_key,
  metadata
) {
  list(
    batch_id = batch_id,
    producer = producer,
    producer_version = producer_version,
    source_run_id = source_run_id,
    idempotency_key = idempotency_key,
    metadata = metadata
  )
}

new_commit_result <- function(
  batch_id,
  inserted,
  updated,
  matched,
  observed,
  warnings = character(),
  duration = 0,
  replay = FALSE
) {
  list(
    batch_id = batch_id,
    inserted = inserted,
    updated = updated,
    matched = matched,
    observed = observed,
    warnings = warnings,
    duration = duration,
    replay = replay
  )
}

validate_initialized_store <- function(
  store,
  write = FALSE,
  refresh = FALSE
) {
  validate_store_backend(store)
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
      "The Graft store is not initialized.",
      operation = if (write) "commit" else "read",
      store_path = store$path
    )
  }
  if (write) {
    validate_store_writable(store, "commit")
  }
  verify_initialized_store(store, activate = FALSE)
  mark_store_verified(store)
  invisible(store)
}

commit_batch_metadata_json <- function(metadata, result = NULL) {
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
  canonical_json(payload)
}

find_committed_replay <- function(connection, batch) {
  sql <- paste0(
    "SELECT batch_id, metadata_json FROM ",
    quote_identifier(connection, "_graft_batches"),
    " WHERE status = 'committed' AND (batch_id = ? OR (",
    quote_identifier(connection, "producer"),
    " = ? AND ",
    quote_identifier(connection, "idempotency_key"),
    " = ?))"
  )
  rows <- DBI::dbGetQuery(
    connection,
    sql,
    params = list(batch$batch_id, batch$producer, batch$idempotency_key)
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
    error = \(error) list()
  )
  stored <- payload$graft_result
  if (is.null(stored)) {
    return(derive_replay_result(connection, rows$batch_id[[1L]]))
  }
  new_commit_result(
    batch_id = rows$batch_id[[1L]],
    inserted = commit_result_counts(stored$inserted),
    updated = commit_result_counts(stored$updated),
    matched = commit_result_counts(stored$matched),
    observed = commit_result_counts(stored$observed),
    warnings = empty_character(stored$warnings),
    duration = as.numeric(stored$duration[[1L]]),
    replay = TRUE
  )
}

commit_result_counts <- function(x) {
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
      quote_identifier(connection, "_graft_origins"),
      " WHERE first_batch_id = ? GROUP BY class"
    ),
    params = list(batch_id)
  )
  inserted <- stats::setNames(
    as.integer(inserted_rows$n),
    inserted_rows$class
  )
  classes <- union(names(observed), names(inserted))
  inserted <- commit_counts_for_classes(inserted, classes)
  new_commit_result(
    batch_id = batch_id,
    inserted = inserted,
    updated = stats::setNames(integer(length(classes)), classes),
    matched = observed - inserted,
    observed = observed,
    replay = TRUE
  )
}

commit_counts_for_classes <- function(counts, classes) {
  result <- stats::setNames(integer(length(classes)), classes)
  shared <- intersect(names(counts), classes)
  result[shared] <- counts[shared]
  result
}

commit_now <- function() {
  as.POSIXct(Sys.time(), tz = "UTC")
}
