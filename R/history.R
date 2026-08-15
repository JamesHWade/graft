graft_history_engine <- function(store, id, as_of = NULL, limit = 100) {
  validate_retrieval_store(store)
  id <- validate_scalar_text(id, "id", condition = abort_reference_error)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$history
  )
  boundary <- resolve_effective_history_boundary(store, as_of)
  class_boundary_sql <- ""
  class_params <- list(id)
  if (!is.null(boundary$commit_order)) {
    class_boundary_sql <- " AND r.commit_order <= ?"
    class_params <- c(class_params, list(boundary$commit_order))
  }
  record_classes <- with_duckdb_error(
    "record_history_class",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT DISTINCT r.class FROM ",
        quote_identifier(store$connection, "_graft_record_revisions"),
        " r INNER JOIN ",
        quote_identifier(store$connection, "_graft_batches"),
        " b ON r.batch_id = b.batch_id WHERE b.status = 'committed' ",
        "AND r.record_id = ?",
        class_boundary_sql,
        " ORDER BY r.class"
      ),
      params = class_params
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
  schemas <- historical_schemas(
    store,
    unique(rows$schema_build_digest)
  )
  records <- vector("list", nrow(rows))
  changed_fields <- vector("list", nrow(rows))
  for (index in seq_len(nrow(rows))) {
    schema <- schemas[[rows$schema_build_digest[[index]]]]
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
    records[[index]] <- validated_public_revision_record(
      rows$payload_json[[index]],
      rows$content_digest[[index]],
      contract,
      record_id = rows$record_id[[index]],
      revision_id = rows$revision_id[[index]]
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

historical_schemas <- function(store, build_digests) {
  build_digests <- unique(as.character(build_digests))
  if (length(build_digests) == 0L) {
    return(list())
  }
  versions <- with_duckdb_error(
    "record_history_schemas",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT structural_digest, source_digest, build_digest, ",
        "manifest_json FROM ",
        quote_identifier(store$connection, "_graft_schema_versions"),
        " WHERE build_digest IN (",
        paste(rep("?", length(build_digests)), collapse = ", "),
        ") ORDER BY build_digest"
      ),
      params = as.list(build_digests)
    )
  )
  schemas <- list()
  for (build_digest in build_digests) {
    version <- versions[versions$build_digest == build_digest, , drop = FALSE]
    schemas[[build_digest]] <- historical_schema_version(
      version,
      build_digest
    )
  }
  schemas
}

historical_schema_version <- function(version, build_digest) {
  if (nrow(version) != 1L) {
    abort_backend_error(
      "A revision does not have exactly one registered historical manifest.",
      operation = "record_history",
      build_digest = build_digest,
      schema_version_count = nrow(version)
    )
  }
  schema <- compiled_schema_from_json(version$manifest_json[[1L]])
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
  schema
}

historical_schema <- function(store, build_digest, cache) {
  if (exists(build_digest, envir = cache, inherits = FALSE)) {
    return(get(build_digest, envir = cache, inherits = FALSE))
  }
  version <- read_schema_version(store$connection, build_digest)
  schema <- historical_schema_version(version, build_digest)
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

validated_public_revision_record <- function(
  payload_json,
  content_digest,
  contract,
  record_id = NULL,
  revision_id = NULL
) {
  payload <- tryCatch(
    parse_revision_payload(payload_json),
    error = identity
  )
  if (inherits(payload, "error")) {
    abort_backend_error(
      "A selected revision payload is not valid canonical JSON.",
      operation = "graft_retrieval",
      record_id = record_id,
      revision_id = revision_id,
      parent = payload
    )
  }
  canonical <- tryCatch(
    canonical_manifest_payload(payload, contract),
    error = identity
  )
  if (
    inherits(canonical, "error") ||
      !identical(logical_record_content_digest(canonical), content_digest)
  ) {
    abort_backend_error(
      "A selected revision payload does not match its content digest.",
      operation = "graft_retrieval",
      record_id = record_id,
      revision_id = revision_id,
      parent = if (inherits(canonical, "error")) canonical else NULL
    )
  }
  public_revision_record(payload_json, contract)
}

coerce_historical_value <- function(value, slot) {
  type <- toupper(scalar_character(
    slot$duckdb_type,
    scalar_character(slot$relational_type, "VARCHAR")
  ))
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
      if (is.character(item)) {
        number <- suppressWarnings(as.numeric(item))
        exact <- is.finite(number) &&
          abs(number) <= 2^53 &&
          identical(
            format(number, scientific = FALSE, trim = TRUE),
            item
          )
        if (!exact) {
          return(item)
        }
        return(number)
      }
      return(as.numeric(item))
    }
    if (identical(type, "DECIMAL")) {
      if (is.character(item)) {
        return(item)
      }
      return(as.numeric(item))
    }
    if (identical(type, "DOUBLE")) {
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
      if (type %in% c("BIGINT", "DECIMAL")) {
        return(character())
      }
      if (identical(type, "DOUBLE")) {
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

resolve_effective_history_boundary <- function(store, as_of) {
  if (!is_graft_snapshot_backend(store)) {
    return(resolve_history_boundary(store, as_of))
  }
  snapshot <- snapshot_backend_data(store)
  pinned <- list(
    commit_order = snapshot$commit_order,
    batch_id = snapshot$batch_id,
    committed_at = snapshot$committed_at
  )
  if (is.null(as_of)) {
    return(pinned)
  }
  if (inherits(as_of, "POSIXt") && snapshot$commit_order > 0) {
    requested_time <- validate_history_time(as_of, "as_of")
    pinned_time <- as.POSIXct(
      snapshot$committed_at,
      format = "%Y-%m-%dT%H:%M:%OSZ",
      tz = "UTC"
    )
    if (requested_time > pinned_time) {
      abort_snapshot_error(
        c("graft_snapshot_boundary_error", "graft_history_boundary_error"),
        "The requested history boundary is later than the GraftView snapshot.",
        requested_as_of = as_of,
        snapshot_commit_order = snapshot$commit_order,
        snapshot_batch_id = snapshot$batch_id
      )
    }
  }
  boundary <- resolve_history_boundary(store, as_of)
  if (boundary$commit_order > snapshot$commit_order) {
    abort_snapshot_error(
      c("graft_snapshot_boundary_error", "graft_history_boundary_error"),
      "The requested history boundary is later than the GraftView snapshot.",
      requested_as_of = as_of,
      requested_commit_order = boundary$commit_order,
      snapshot_commit_order = snapshot$commit_order,
      snapshot_batch_id = snapshot$batch_id
    )
  }
  boundary
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
  execute_integrity_checks(connection, checks, limit)
}

execute_integrity_checks <- function(connection, checks, limit) {
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
