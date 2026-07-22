#' List committed ingestion batches
#'
#' `kg_batches()` returns committed batches in deterministic newest-first commit
#' order. Batch metadata is parsed into a list-column; the stored JSON is never
#' exposed directly.
#'
#' @param store An initialized `kg_store`.
#' @param producer Optional exact producer name.
#' @param source_run_id Optional exact producer-side run identifier.
#' @param from,to Optional inclusive `POSIXt` boundaries on commit time.
#' @param limit Maximum number of batches to return.
#'
#' @return A bounded data frame of committed batch provenance.
#' @export
kg_batches <- function(
  store,
  producer = NULL,
  source_run_id = NULL,
  from = NULL,
  to = NULL,
  limit = 100
) {
  validate_retrieval_store(store)
  producer <- validate_optional_scalar_text(producer, "producer")
  source_run_id <- validate_optional_scalar_text(
    source_run_id,
    "source_run_id"
  )
  boundaries <- validate_history_time_range(from, to)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$batches
  )
  filters <- history_sql_filters(
    store,
    values = list(
      producer = producer,
      source_run_id = source_run_id,
      from = boundaries$from,
      to = boundaries$to
    ),
    columns = c(
      producer = "producer",
      source_run_id = "source_run_id",
      from = "committed_at",
      to = "committed_at"
    ),
    operators = c(from = ">=", to = "<=")
  )
  sql <- paste0(
    "SELECT batch_id, schema_build_digest, commit_order, producer, ",
    "producer_version, source_run_id, idempotency_key, metadata_json, ",
    "started_at, committed_at, status FROM ",
    quote_identifier(store$connection, "_graft_batches"),
    " WHERE status = 'committed'",
    filters$sql,
    " ORDER BY commit_order DESC, batch_id ASC LIMIT ",
    limit + 1L
  )
  rows <- with_duckdb_error(
    "list_batches",
    DBI::dbGetQuery(store$connection, sql, params = filters$params)
  )
  truncated <- nrow(rows) > limit
  if (truncated) {
    rows <- rows[seq_len(limit), , drop = FALSE]
  }
  payloads <- lapply(rows$metadata_json, parse_public_batch_metadata)
  rows$metadata_json <- NULL
  rows$metadata <- I(lapply(payloads, function(payload) {
    if (is.null(payload$metadata)) list() else payload$metadata
  }))
  rows$result <- I(lapply(payloads, function(payload) {
    if (is.null(payload$graft_result)) list() else payload$graft_result
  }))
  finalize_history_rows(rows, store, limit, truncated)
}

#' List accepted record changes
#'
#' `kg_changes()` returns immutable record revisions in deterministic
#' newest-first commit order. Historical records and changed-field names are
#' filtered using the exact manifest that governed each revision, so sensitive
#' slots are not exposed.
#'
#' @param store An initialized `kg_store`.
#' @param batch_id Optional exact committed batch identifier.
#' @param record_id Optional exact internal record identifier.
#' @param class Optional exact historical concrete class name.
#' @param from,to Optional inclusive `POSIXt` boundaries on batch commit time.
#' @param limit Maximum number of revisions to return.
#'
#' @return A bounded data frame with `changed_fields` and `record` list-columns.
#' @export
kg_changes <- function(
  store,
  batch_id = NULL,
  record_id = NULL,
  class = NULL,
  from = NULL,
  to = NULL,
  limit = 100
) {
  validate_retrieval_store(store)
  batch_id <- validate_optional_scalar_text(batch_id, "batch_id")
  record_id <- validate_optional_scalar_text(record_id, "record_id")
  class <- validate_optional_scalar_text(class, "class")
  boundaries <- validate_history_time_range(from, to)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$changes
  )
  filters <- history_sql_filters(
    store,
    values = list(
      batch_id = batch_id,
      record_id = record_id,
      class = class,
      from = boundaries$from,
      to = boundaries$to
    ),
    columns = c(
      batch_id = "r.batch_id",
      record_id = "r.record_id",
      class = "r.class",
      from = "b.committed_at",
      to = "b.committed_at"
    ),
    operators = c(from = ">=", to = "<=")
  )
  rows <- query_history_revisions(store, filters, limit)
  hydrate_history_rows(rows, store, limit)
}

#' Retrieve the accepted history of one record
#'
#' Revisions are returned in deterministic newest-first commit order. `as_of`
#' selects the state committed by a boundary: either an exact committed batch
#' identifier or a `POSIXt` time. Time boundaries are first resolved to a
#' committed batch order, so revision timestamps are never used as transaction
#' boundaries. With `limit = 1`, the returned `record` is the accepted record at
#' that boundary.
#'
#' @param store An initialized `kg_store`.
#' @param id One internal record identifier.
#' @param as_of Optional committed batch identifier or scalar `POSIXt` time.
#' @param limit Maximum number of revisions to return.
#'
#' @return A bounded data frame with `changed_fields` and `record` list-columns.
#' @export
kg_history <- function(store, id, as_of = NULL, limit = 100) {
  validate_retrieval_store(store)
  id <- validate_scalar_text(id, "id", condition = abort_reference_error)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$history
  )
  boundary <- resolve_history_boundary(store, as_of)
  record_classes <- with_duckdb_error(
    "record_history_class",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT DISTINCT class FROM ",
        quote_identifier(store$connection, "_graft_record_revisions"),
        " WHERE record_id = ? ORDER BY class"
      ),
      params = list(id)
    )
  )
  if (nrow(record_classes) == 0L) {
    abort_reference_error(
      paste0("Record `", id, "` has no accepted history."),
      record_id = id,
      field = "id",
      rule = "record_history_exists",
      observed_value = id
    )
  }
  if (nrow(record_classes) != 1L) {
    abort_identity_error(
      paste0("Record `", id, "` has history in multiple classes."),
      record_id = id,
      field = "id",
      rule = "unique_record_history_class",
      observed_value = id,
      matched_classes = record_classes$class
    )
  }
  values <- list(record_id = id)
  columns <- c(record_id = "r.record_id")
  operators <- character()
  if (!is.null(boundary$commit_order)) {
    values$commit_order <- boundary$commit_order
    columns <- c(columns, commit_order = "r.commit_order")
    operators <- c(operators, commit_order = "<=")
  }
  filters <- history_sql_filters(
    store,
    values = values,
    columns = columns,
    operators = operators
  )
  rows <- query_history_revisions(store, filters, limit)
  if (nrow(rows) == 0L) {
    graft_abort(
      "graft_history_boundary_error",
      paste0(
        "Record `",
        id,
        "` was not accepted at the requested history boundary."
      ),
      record_id = id,
      as_of = as_of,
      boundary_commit_order = boundary$commit_order
    )
  }
  result <- hydrate_history_rows(rows, store, limit)
  attr(result, "as_of") <- as_of
  attr(result, "as_of_commit_order") <- boundary$commit_order
  attr(result, "as_of_batch_id") <- boundary$batch_id
  result
}

#' Check revision-ledger and current-state integrity
#'
#' Shallow checks validate relationships among batches, revisions, heads,
#' observations, schema versions, and typed current tables. With `deep = TRUE`,
#' Graft also parses and re-digests every revision payload and compares every
#' current typed record with its revision head. All records may be scanned, but
#' reported issues are always bounded.
#'
#' @param store An initialized `kg_store`.
#' @param deep Whether to perform payload and current-state digest checks.
#' @param limit Maximum number of issues to report.
#'
#' @return A `kg_store_check` containing `valid`, scan details, and a bounded
#'   `issues` data frame.
#' @export
kg_check_store <- function(store, deep = FALSE, limit = 100) {
  validate_retrieval_store(store, refresh = TRUE)
  deep <- validate_history_flag(deep, "deep")
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$integrity_issues
  )
  issues <- shallow_integrity_issues(store, limit)
  if (deep) {
    issues <- c(issues, deep_integrity_issues(store, limit))
  }
  issues <- bind_integrity_issues(issues)
  if (nrow(issues) > 0L) {
    issues <- issues[
      order(
        issues$issue,
        issues$class,
        issues$record_id,
        issues$revision_id,
        issues$batch_id,
        na.last = TRUE,
        method = "radix"
      ),
      ,
      drop = FALSE
    ]
  }
  truncated <- nrow(issues) > limit
  if (truncated) {
    issues <- issues[seq_len(limit), , drop = FALSE]
  }
  issues <- bounded_data_frame(issues, store, limit, truncated)
  structure(
    list(
      valid = nrow(issues) == 0L,
      deep = deep,
      checked_at = as.POSIXct(Sys.time(), tz = "UTC"),
      reported_issues = nrow(issues),
      truncated = truncated,
      issues = issues,
      store_schema_digest = store_schema_digest(store)
    ),
    class = "kg_store_check"
  )
}

validate_history_flag <- function(value, argument) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    abort_validation_error(
      paste0("`", argument, "` must be `TRUE` or `FALSE`."),
      field = argument,
      rule = "scalar_logical",
      observed_value = value
    )
  }
  value
}

validate_history_time <- function(value, argument) {
  if (is.null(value)) {
    return(NULL)
  }
  if (
    !inherits(value, "POSIXt") ||
      length(value) != 1L ||
      is.na(value) ||
      !is.finite(as.numeric(value))
  ) {
    abort_validation_error(
      paste0("`", argument, "` must be one non-missing POSIXt value."),
      field = argument,
      rule = "scalar_posixt",
      observed_value = value
    )
  }
  as.POSIXct(value, tz = "UTC")
}

validate_history_time_range <- function(from, to) {
  from <- validate_history_time(from, "from")
  to <- validate_history_time(to, "to")
  if (!is.null(from) && !is.null(to) && from > to) {
    abort_validation_error(
      "`from` must not be later than `to`.",
      field = "from",
      rule = "time_range_order",
      observed_value = from
    )
  }
  list(from = from, to = to)
}

history_sql_filters <- function(
  store,
  values,
  columns,
  operators = character()
) {
  clauses <- character()
  params <- list()
  for (name in names(values)) {
    value <- values[[name]]
    if (is.null(value)) {
      next
    }
    column <- columns[[name]]
    operator <- if (name %in% names(operators)) operators[[name]] else "="
    stopifnot(operator %in% c("=", ">=", "<="))
    if (grepl("\\.", column, fixed = FALSE)) {
      parts <- strsplit(column, ".", fixed = TRUE)[[1L]]
      column <- paste(
        vapply(
          parts,
          \(.x) quote_identifier(store$connection, .x),
          character(1)
        ),
        collapse = "."
      )
    } else {
      column <- quote_identifier(store$connection, column)
    }
    clauses <- c(clauses, paste0(" AND ", column, " ", operator, " ?"))
    params <- c(params, list(value))
  }
  list(sql = paste0(clauses, collapse = ""), params = params)
}

parse_public_batch_metadata <- function(metadata_json) {
  if (is.na(metadata_json) || !nzchar(metadata_json)) {
    return(list())
  }
  payload <- tryCatch(
    jsonlite::fromJSON(metadata_json, simplifyVector = FALSE),
    error = function(error) {
      abort_backend_error(
        paste0(
          "Could not parse stored batch metadata: ",
          conditionMessage(error)
        ),
        operation = "list_batches",
        parent = error
      )
    }
  )
  if (!is.list(payload)) {
    abort_backend_error(
      "Stored batch metadata must contain a JSON object.",
      operation = "list_batches"
    )
  }
  payload
}

query_history_revisions <- function(store, filters, limit) {
  sql <- paste0(
    "SELECT r.revision_id, r.record_id, r.class, r.batch_id, ",
    "r.schema_build_digest, r.revision_number, r.operation, ",
    "r.payload_json, r.content_digest, r.changed_fields_json, ",
    "r.prior_revision_id, r.recorded_at, r.commit_order, ",
    "b.committed_at, b.producer, b.source_run_id FROM ",
    quote_identifier(store$connection, "_graft_record_revisions"),
    " r INNER JOIN ",
    quote_identifier(store$connection, "_graft_batches"),
    " b ON r.batch_id = b.batch_id WHERE b.status = 'committed'",
    filters$sql,
    " ORDER BY r.commit_order DESC, r.class ASC, r.record_id ASC, ",
    "r.revision_number DESC, r.revision_id ASC LIMIT ",
    limit + 1L
  )
  with_duckdb_error(
    "record_history",
    DBI::dbGetQuery(store$connection, sql, params = filters$params)
  )
}

hydrate_history_rows <- function(rows, store, limit) {
  truncated <- nrow(rows) > limit
  if (truncated) {
    rows <- rows[seq_len(limit), , drop = FALSE]
  }
  cache <- new.env(parent = emptyenv())
  records <- vector("list", nrow(rows))
  changed_fields <- vector("list", nrow(rows))
  for (index in seq_len(nrow(rows))) {
    schema <- historical_schema(
      store,
      rows$schema_build_digest[[index]],
      cache
    )
    contract <- schema$manifest$classes[[rows$class[[index]]]]
    if (is.null(contract)) {
      abort_backend_error(
        "A revision class is absent from its historical manifest.",
        operation = "record_history",
        record_id = rows$record_id[[index]],
        record_class = rows$class[[index]],
        build_digest = rows$schema_build_digest[[index]]
      )
    }
    records[[index]] <- public_revision_record(
      rows$payload_json[[index]],
      contract
    )
    changed_fields[[index]] <- public_changed_fields(
      rows$changed_fields_json[[index]],
      contract
    )
  }
  rows$payload_json <- NULL
  rows$content_digest <- NULL
  rows$changed_fields_json <- NULL
  rows$changed_fields <- I(changed_fields)
  rows$record <- I(records)
  finalize_history_rows(rows, store, limit, truncated)
}

historical_schema <- function(store, build_digest, cache) {
  if (exists(build_digest, envir = cache, inherits = FALSE)) {
    return(get(build_digest, envir = cache, inherits = FALSE))
  }
  version <- read_schema_version(store$connection, build_digest)
  if (nrow(version) != 1L) {
    abort_backend_error(
      "A revision does not have exactly one registered historical manifest.",
      operation = "record_history",
      build_digest = build_digest,
      schema_version_count = nrow(version)
    )
  }
  schema <- schema_from_manifest_json(version$manifest_json[[1L]])
  validate_manifest_integrity(schema)
  fingerprints <- schema$manifest$fingerprints
  if (
    !identical(
      scalar_character(version$structural_digest),
      scalar_character(fingerprints$structural_digest)
    ) ||
      !identical(
        scalar_character(version$source_digest),
        scalar_character(fingerprints$source_digest)
      ) ||
      !identical(
        scalar_character(version$build_digest),
        scalar_character(fingerprints$build_digest)
      )
  ) {
    abort_backend_error(
      "A historical schema registry row does not match its manifest.",
      operation = "record_history",
      build_digest = build_digest
    )
  }
  assign(build_digest, schema, envir = cache)
  schema
}

public_revision_record <- function(payload_json, contract) {
  payload <- parse_revision_payload(payload_json)
  if (!is.list(payload) || is.null(names(payload))) {
    abort_backend_error(
      "A record revision payload must contain a named JSON object.",
      operation = "record_history"
    )
  }
  public <- names(Filter(
    \(.x) !scalar_logical(.x$sensitive),
    contract$slots
  ))
  record <- payload[public]
  for (field in names(record)) {
    record[field] <- list(coerce_historical_value(
      record[[field]],
      contract$slots[[field]]
    ))
  }
  record
}

coerce_historical_value <- function(value, slot) {
  type <- canonical_slot_type(slot, operation = "record_history")
  object_reference <- scalar_logical(slot$object_reference)
  if (is.null(value)) {
    return(NULL)
  }
  if (object_reference) {
    canonical <- canonical_slot_value(value, slot)
    if (scalar_logical(slot$multivalued)) {
      return(as.character(unlist(canonical, use.names = FALSE)))
    }
    return(canonical)
  }
  convert <- function(item) {
    if (is.null(item)) {
      return(NULL)
    }
    if (identical(type, "BOOLEAN")) {
      return(as.logical(item))
    }
    if (identical(type, "BIGINT")) {
      return(as.numeric(item))
    }
    if (type %in% c("DOUBLE", "DECIMAL")) {
      return(as.numeric(item))
    }
    if (identical(type, "DATE")) {
      return(as.Date(item))
    }
    if (identical(type, "TIME")) {
      parts <- as.numeric(strsplit(as.character(item), ":", fixed = TRUE)[[1L]])
      seconds <- parts[[1L]] * 3600 + parts[[2L]] * 60
      if (length(parts) == 3L) {
        seconds <- seconds + parts[[3L]]
      }
      return(as.difftime(seconds, units = "secs"))
    }
    if (identical(type, "TIMESTAMP")) {
      return(as.POSIXct(
        item,
        format = "%Y-%m-%dT%H:%M:%OSZ",
        tz = "UTC"
      ))
    }
    as.character(item)
  }
  if (scalar_logical(slot$multivalued)) {
    if (length(value) == 0L) {
      if (identical(type, "BOOLEAN")) {
        return(logical())
      }
      if (type %in% c("BIGINT", "DOUBLE", "DECIMAL")) {
        return(numeric())
      }
      if (identical(type, "DATE")) {
        return(as.Date(character()))
      }
      if (identical(type, "TIME")) {
        return(as.difftime(numeric(), units = "secs"))
      }
      if (identical(type, "TIMESTAMP")) {
        return(as.POSIXct(character(), tz = "UTC"))
      }
      return(character())
    }
    return(unname(do.call(c, lapply(value, convert))))
  }
  convert(value)
}

public_changed_fields <- function(changed_fields_json, contract) {
  fields <- tryCatch(
    jsonlite::fromJSON(changed_fields_json, simplifyVector = FALSE),
    error = function(error) {
      abort_backend_error(
        paste0(
          "Could not parse stored changed fields: ",
          conditionMessage(error)
        ),
        operation = "record_history",
        parent = error
      )
    }
  )
  fields <- as.character(unlist(fields, use.names = FALSE))
  public <- names(Filter(
    \(.x) !scalar_logical(.x$sensitive),
    contract$slots
  ))
  sort(intersect(fields, public), method = "radix")
}

finalize_history_rows <- function(rows, store, limit, truncated) {
  rownames(rows) <- NULL
  rows <- bounded_data_frame(rows, store, limit, truncated)
  attr(rows, "schema_build_digests") <- if (
    "schema_build_digest" %in% names(rows)
  ) {
    sort(unique(as.character(rows$schema_build_digest)), method = "radix")
  } else {
    character()
  }
  attr(rows, "newest_first") <- TRUE
  rows
}

resolve_history_boundary <- function(store, as_of) {
  if (is.null(as_of)) {
    return(list(
      commit_order = NULL,
      batch_id = NULL,
      committed_at = NULL
    ))
  }
  if (inherits(as_of, "POSIXt")) {
    time <- validate_history_time(as_of, "as_of")
    row <- with_duckdb_error(
      "resolve_history_boundary",
      DBI::dbGetQuery(
        store$connection,
        paste0(
          "SELECT batch_id, commit_order, committed_at FROM ",
          quote_identifier(store$connection, "_graft_batches"),
          " WHERE status = 'committed' AND committed_at <= ? ",
          "ORDER BY commit_order DESC, batch_id ASC LIMIT 1"
        ),
        params = list(time)
      )
    )
    if (nrow(row) == 0L) {
      return(list(
        commit_order = 0,
        batch_id = NA_character_,
        committed_at = time
      ))
    }
    return(list(
      commit_order = as.numeric(row$commit_order[[1L]]),
      batch_id = row$batch_id[[1L]],
      committed_at = row$committed_at[[1L]]
    ))
  }
  batch_id <- validate_scalar_text(as_of, "as_of")
  row <- with_duckdb_error(
    "resolve_history_boundary",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT batch_id, commit_order, committed_at, status FROM ",
        quote_identifier(store$connection, "_graft_batches"),
        " WHERE batch_id = ?"
      ),
      params = list(batch_id)
    )
  )
  if (nrow(row) != 1L || !identical(row$status[[1L]], "committed")) {
    graft_abort(
      "graft_history_boundary_error",
      paste0(
        "History boundary batch `",
        batch_id,
        "` does not identify exactly one committed batch."
      ),
      batch_id = batch_id,
      observed_status = if (nrow(row) == 1L) row$status[[1L]] else NA_character_
    )
  }
  list(
    commit_order = as.numeric(row$commit_order[[1L]]),
    batch_id = row$batch_id[[1L]],
    committed_at = row$committed_at[[1L]]
  )
}

shallow_integrity_issues <- function(store, limit) {
  connection <- store$connection
  head <- quote_identifier(connection, "_graft_record_heads")
  revision <- quote_identifier(connection, "_graft_record_revisions")
  batch <- quote_identifier(connection, "_graft_batches")
  observation <- quote_identifier(connection, "_graft_record_observations")
  schema <- quote_identifier(connection, "_graft_schema_versions")
  checks <- list(
    paste0(
      "SELECT 'orphan_head_revision' AS issue, h.record_id, h.class, ",
      "h.revision_id, NULL AS batch_id, ",
      "'Head revision does not exist.' AS detail FROM ",
      head,
      " h LEFT JOIN ",
      revision,
      " r ON h.revision_id = r.revision_id WHERE r.revision_id IS NULL"
    ),
    paste0(
      "SELECT 'head_identity_mismatch' AS issue, h.record_id, h.class, ",
      "h.revision_id, r.batch_id, ",
      "'Head and revision identity or class differ.' AS detail FROM ",
      head,
      " h INNER JOIN ",
      revision,
      " r ON h.revision_id = r.revision_id WHERE h.record_id <> r.record_id ",
      "OR h.class <> r.class"
    ),
    paste0(
      "SELECT 'head_revision_number_mismatch' AS issue, h.record_id, h.class, ",
      "h.revision_id, r.batch_id, ",
      "'Head and revision numbers differ.' AS detail FROM ",
      head,
      " h INNER JOIN ",
      revision,
      " r ON h.revision_id = r.revision_id ",
      "WHERE h.revision_number <> r.revision_number"
    ),
    paste0(
      "SELECT 'head_not_latest' AS issue, h.record_id, h.class, ",
      "h.revision_id, r.batch_id, ",
      "'Head is not the latest record revision.' AS detail FROM ",
      head,
      " h INNER JOIN ",
      revision,
      " r ON h.revision_id = r.revision_id INNER JOIN ",
      "(SELECT record_id, class, MAX(revision_number) AS max_revision ",
      "FROM ",
      revision,
      " GROUP BY record_id, class) m ",
      "ON h.record_id = m.record_id AND h.class = m.class ",
      "WHERE h.revision_number <> m.max_revision"
    ),
    paste0(
      "SELECT 'latest_revision_head_mismatch' AS issue, r.record_id, ",
      "r.class, r.revision_id, r.batch_id, ",
      "'Latest accepted revision has no matching revision head.' AS detail ",
      "FROM ",
      revision,
      " r INNER JOIN (SELECT record_id, class, MAX(revision_number) ",
      "AS max_revision FROM ",
      revision,
      " GROUP BY record_id, class) m ON r.record_id = m.record_id AND ",
      "r.class = m.class AND r.revision_number = m.max_revision LEFT JOIN ",
      head,
      " h ON r.record_id = h.record_id WHERE h.record_id IS NULL OR ",
      "h.class <> r.class OR h.revision_id <> r.revision_id OR ",
      "h.revision_number <> r.revision_number"
    ),
    paste0(
      "SELECT 'orphan_revision_batch' AS issue, r.record_id, r.class, ",
      "r.revision_id, r.batch_id, ",
      "'Revision batch is absent or not committed.' AS detail FROM ",
      revision,
      " r LEFT JOIN ",
      batch,
      " b ON r.batch_id = b.batch_id WHERE b.batch_id IS NULL ",
      "OR b.status <> 'committed'"
    ),
    paste0(
      "SELECT 'revision_commit_order_mismatch' AS issue, r.record_id, ",
      "r.class, r.revision_id, r.batch_id, ",
      "'Revision and batch commit orders differ.' AS detail FROM ",
      revision,
      " r INNER JOIN ",
      batch,
      " b ON r.batch_id = b.batch_id WHERE r.commit_order <> b.commit_order"
    ),
    paste0(
      "SELECT 'revision_batch_schema_mismatch' AS issue, r.record_id, ",
      "r.class, r.revision_id, r.batch_id, ",
      "'Revision and batch schema digests differ.' AS detail FROM ",
      revision,
      " r INNER JOIN ",
      batch,
      " b ON r.batch_id = b.batch_id WHERE r.schema_build_digest <> ",
      "b.schema_build_digest"
    ),
    paste0(
      "SELECT 'revision_operation_mismatch' AS issue, r.record_id, r.class, ",
      "r.revision_id, r.batch_id, ",
      "'Revision operation is inconsistent with its number.' AS detail FROM ",
      revision,
      " r WHERE (r.revision_number = 1 AND r.operation <> 'insert') OR ",
      "(r.revision_number > 1 AND r.operation <> 'update')"
    ),
    paste0(
      "SELECT 'orphan_revision_schema' AS issue, r.record_id, r.class, ",
      "r.revision_id, r.batch_id, ",
      "'Revision schema version does not exist.' AS detail FROM ",
      revision,
      " r LEFT JOIN ",
      schema,
      " s ON r.schema_build_digest = s.build_digest ",
      "WHERE s.build_digest IS NULL"
    ),
    paste0(
      "SELECT 'orphan_prior_revision' AS issue, r.record_id, r.class, ",
      "r.revision_id, r.batch_id, ",
      "'Prior revision does not exist.' AS detail FROM ",
      revision,
      " r LEFT JOIN ",
      revision,
      " p ON r.prior_revision_id = p.revision_id ",
      "WHERE r.prior_revision_id IS NOT NULL AND p.revision_id IS NULL"
    ),
    paste0(
      "SELECT 'revision_chain_mismatch' AS issue, r.record_id, r.class, ",
      "r.revision_id, r.batch_id, ",
      "'Prior revision identity or number is inconsistent.' AS detail FROM ",
      revision,
      " r LEFT JOIN ",
      revision,
      " p ON r.prior_revision_id = p.revision_id WHERE ",
      "(r.revision_number = 1 AND r.prior_revision_id IS NOT NULL) OR ",
      "(r.revision_number > 1 AND (p.revision_id IS NULL OR ",
      "p.record_id <> r.record_id OR p.class <> r.class OR ",
      "p.revision_number <> r.revision_number - 1))"
    ),
    paste0(
      "SELECT 'orphan_observation_batch' AS issue, o.record_id, o.class, ",
      "o.revision_id, o.batch_id, ",
      "'Observation batch is absent or not committed.' AS detail FROM ",
      observation,
      " o LEFT JOIN ",
      batch,
      " b ON o.batch_id = b.batch_id WHERE b.batch_id IS NULL ",
      "OR b.status <> 'committed'"
    ),
    paste0(
      "SELECT 'orphan_observation_revision' AS issue, o.record_id, o.class, ",
      "o.revision_id, o.batch_id, ",
      "'Observation revision does not exist.' AS detail FROM ",
      observation,
      " o LEFT JOIN ",
      revision,
      " r ON o.revision_id = r.revision_id WHERE r.revision_id IS NULL"
    ),
    paste0(
      "SELECT 'observation_identity_mismatch' AS issue, o.record_id, o.class, ",
      "o.revision_id, o.batch_id, ",
      "'Observation and revision identity or class differ.' AS detail FROM ",
      observation,
      " o INNER JOIN ",
      revision,
      " r ON o.revision_id = r.revision_id WHERE o.record_id <> r.record_id ",
      "OR o.class <> r.class"
    ),
    paste0(
      "SELECT 'observation_disposition_mismatch' AS issue, o.record_id, ",
      "o.class, o.revision_id, o.batch_id, ",
      "'Observation disposition is inconsistent with its revision.' ",
      "AS detail FROM ",
      observation,
      " o INNER JOIN ",
      revision,
      " r ON o.revision_id = r.revision_id INNER JOIN ",
      batch,
      " b ON o.batch_id = b.batch_id WHERE ",
      "o.disposition NOT IN ('inserted', 'updated', 'matched') OR ",
      "(o.disposition = 'inserted' AND (r.operation <> 'insert' OR ",
      "r.batch_id <> o.batch_id)) OR ",
      "(o.disposition = 'updated' AND (r.operation <> 'update' OR ",
      "r.batch_id <> o.batch_id)) OR ",
      "(o.disposition = 'matched' AND r.commit_order >= b.commit_order)"
    ),
    paste0(
      "SELECT 'revision_without_observation' AS issue, r.record_id, r.class, ",
      "r.revision_id, r.batch_id, ",
      "'Revision has no matching observation in its batch.' AS detail FROM ",
      revision,
      " r LEFT JOIN ",
      observation,
      " o ON r.revision_id = o.revision_id AND r.record_id = o.record_id ",
      "AND r.class = o.class AND r.batch_id = o.batch_id ",
      "WHERE o.revision_id IS NULL"
    )
  )
  head_classes <- DBI::dbGetQuery(
    connection,
    paste0("SELECT DISTINCT class FROM ", head, " ORDER BY class")
  )$class
  unknown_classes <- setdiff(
    as.character(head_classes),
    names(store$schema$manifest$classes)
  )
  if (length(unknown_classes) > 0L) {
    unknown <- DBI::dbGetQuery(
      connection,
      paste0(
        "SELECT 'head_class_missing' AS issue, record_id, class, ",
        "revision_id, NULL AS batch_id, ",
        "'Head class is absent from the active manifest.' AS detail FROM ",
        head,
        " WHERE class IN (",
        paste(rep("?", length(unknown_classes)), collapse = ", "),
        ") LIMIT ",
        limit + 1L
      ),
      params = as.list(unknown_classes)
    )
    checks <- c(checks, list(unknown))
  }
  available_tables <- duckdb_table_names(connection)
  for (record_class in names(store$schema$manifest$classes)) {
    contract <- store$schema$manifest$classes[[record_class]]
    table_name <- scalar_character(contract$table)
    if (!table_name %in% available_tables) {
      checks <- c(
        checks,
        list(integrity_issue_row(
          "current_table_missing",
          class = record_class,
          detail = "The active manifest's current-state table does not exist."
        ))
      )
      next
    }
    table <- quote_identifier(connection, table_name)
    id_column <- quote_identifier(connection, slot_column(contract, "id"))
    class_string <- as.character(DBI::dbQuoteString(connection, record_class))
    checks <- c(
      checks,
      list(
        paste0(
          "SELECT 'current_without_head' AS issue, t.",
          id_column,
          " AS record_id, ",
          class_string,
          " AS class, NULL AS revision_id, NULL AS batch_id, ",
          "'Current record has no revision head.' AS detail FROM ",
          table,
          " t LEFT JOIN ",
          head,
          " h ON t.",
          id_column,
          " = h.record_id AND h.class = ",
          class_string,
          " WHERE h.record_id IS NULL"
        ),
        paste0(
          "SELECT 'head_without_current' AS issue, h.record_id, h.class, ",
          "h.revision_id, NULL AS batch_id, ",
          "'Revision head has no current record.' AS detail FROM ",
          head,
          " h LEFT JOIN ",
          table,
          " t ON h.record_id = t.",
          id_column,
          " WHERE h.class = ",
          class_string,
          " AND t.",
          id_column,
          " IS NULL"
        )
      )
    )
  }
  lapply(checks, function(check) {
    if (is.data.frame(check)) {
      return(check)
    }
    with_duckdb_error(
      "check_store",
      DBI::dbGetQuery(
        connection,
        paste0(check, " LIMIT ", limit + 1L)
      )
    )
  })
}

deep_integrity_issues <- function(store, limit) {
  issues <- list()
  cache <- new.env(parent = emptyenv())
  add_issue <- function(issue) {
    if (length(issues) <= limit) {
      issues[[length(issues) + 1L]] <<- issue
    }
  }
  revisions <- DBI::dbSendQuery(
    store$connection,
    paste0(
      "SELECT revision_id, record_id, class, batch_id, payload_json, ",
      "content_digest, schema_build_digest FROM ",
      quote_identifier(store$connection, "_graft_record_revisions"),
      " ORDER BY revision_id"
    )
  )
  on.exit(
    {
      if (!is.null(revisions)) {
        DBI::dbClearResult(revisions)
      }
    },
    add = TRUE
  )
  repeat {
    rows <- DBI::dbFetch(revisions, n = 500L)
    if (nrow(rows) == 0L) {
      break
    }
    for (index in seq_len(nrow(rows))) {
      payload <- tryCatch(
        parse_revision_payload(rows$payload_json[[index]]),
        error = identity
      )
      if (inherits(payload, "error")) {
        add_issue(integrity_issue_row(
          "invalid_revision_payload",
          rows$record_id[[index]],
          rows$class[[index]],
          rows$revision_id[[index]],
          rows$batch_id[[index]],
          "Revision payload is not valid canonical JSON."
        ))
        next
      }
      schema <- tryCatch(
        historical_schema(
          store,
          rows$schema_build_digest[[index]],
          cache
        ),
        error = identity
      )
      contract <- if (inherits(schema, "error")) {
        NULL
      } else {
        schema$manifest$classes[[rows$class[[index]]]]
      }
      if (is.null(contract)) {
        next
      }
      payload <- tryCatch(
        canonical_manifest_payload(payload, contract),
        error = identity
      )
      if (inherits(payload, "error")) {
        add_issue(integrity_issue_row(
          "noncanonical_revision_payload",
          rows$record_id[[index]],
          rows$class[[index]],
          rows$revision_id[[index]],
          rows$batch_id[[index]],
          "Revision payload does not conform to its historical schema."
        ))
        next
      }
      digest <- logical_record_content_digest(payload)
      if (!identical(digest, rows$content_digest[[index]])) {
        add_issue(integrity_issue_row(
          "revision_digest_mismatch",
          rows$record_id[[index]],
          rows$class[[index]],
          rows$revision_id[[index]],
          rows$batch_id[[index]],
          "Revision payload does not match its content digest."
        ))
      }
    }
  }
  DBI::dbClearResult(revisions)
  revisions <- NULL
  heads_result <- DBI::dbSendQuery(
    store$connection,
    paste0(
      "SELECT h.record_id, h.class, h.revision_id, r.batch_id, ",
      "r.schema_build_digest, r.content_digest FROM ",
      quote_identifier(store$connection, "_graft_record_heads"),
      " h INNER JOIN ",
      quote_identifier(store$connection, "_graft_record_revisions"),
      " r ON h.revision_id = r.revision_id ORDER BY h.record_id"
    )
  )
  on.exit(
    {
      if (!is.null(heads_result)) {
        DBI::dbClearResult(heads_result)
      }
    },
    add = TRUE
  )
  repeat {
    heads <- DBI::dbFetch(heads_result, n = 500L)
    if (nrow(heads) == 0L) {
      break
    }
    for (index in seq_len(nrow(heads))) {
      schema <- tryCatch(
        historical_schema(
          store,
          heads$schema_build_digest[[index]],
          cache
        ),
        error = identity
      )
      contract <- if (inherits(schema, "error")) {
        NULL
      } else {
        schema$manifest$classes[[heads$class[[index]]]]
      }
      if (is.null(contract)) {
        add_issue(integrity_issue_row(
          "head_schema_class_missing",
          heads$record_id[[index]],
          heads$class[[index]],
          heads$revision_id[[index]],
          heads$batch_id[[index]],
          "Head class is absent from its revision schema."
        ))
        next
      }
      payload <- tryCatch(
        current_record_payload(
          store,
          list(class = heads$class[[index]], contract = contract),
          heads$record_id[[index]]
        ),
        error = identity
      )
      if (inherits(payload, "error")) {
        add_issue(integrity_issue_row(
          "current_payload_unreadable",
          heads$record_id[[index]],
          heads$class[[index]],
          heads$revision_id[[index]],
          heads$batch_id[[index]],
          "Current typed record could not be reconstructed."
        ))
        next
      }
      if (
        !identical(
          logical_record_content_digest(payload),
          heads$content_digest[[index]]
        )
      ) {
        add_issue(integrity_issue_row(
          "current_payload_drift",
          heads$record_id[[index]],
          heads$class[[index]],
          heads$revision_id[[index]],
          heads$batch_id[[index]],
          "Current typed record differs from its revision head."
        ))
      }
    }
  }
  DBI::dbClearResult(heads_result)
  heads_result <- NULL
  issues
}

integrity_issue_row <- function(
  issue,
  record_id = NA_character_,
  class = NA_character_,
  revision_id = NA_character_,
  batch_id = NA_character_,
  detail
) {
  data.frame(
    issue = issue,
    record_id = record_id,
    class = class,
    revision_id = revision_id,
    batch_id = batch_id,
    detail = detail,
    stringsAsFactors = FALSE
  )
}

bind_integrity_issues <- function(issues) {
  issues <- Filter(\(.x) nrow(.x) > 0L, issues)
  if (length(issues) == 0L) {
    return(data.frame(
      issue = character(),
      record_id = character(),
      class = character(),
      revision_id = character(),
      batch_id = character(),
      detail = character(),
      stringsAsFactors = FALSE
    ))
  }
  dplyr::bind_rows(issues)
}
