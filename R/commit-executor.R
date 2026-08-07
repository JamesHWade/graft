commit_executor_head_stage <- "_graft_commit_head_stage"
commit_executor_identifier_stage <- "_graft_commit_identifier_stage"
commit_executor_origin_stage <- "_graft_commit_origin_stage"

commit_candidate_plan <- function(store, batch, staged, plan, started) {
  outcome <- with_duckdb_error(
    "commit_plan",
    DBI::dbWithTransaction(
      store$connection,
      commit_candidate_transaction(store, batch, staged, plan, started)
    )
  )
  if (identical(outcome$type, "replay")) {
    outcome$result$replay <- TRUE
    signal_batch_replay(outcome$result)
  }
  outcome$result
}

commit_candidate_transaction <- function(store, batch, staged, plan, started) {
  replay <- find_committed_replay(store$connection, batch)
  if (!is.null(replay)) {
    validate_commit_plan_replay(plan, replay)
    return(list(type = "replay", result = replay))
  }
  verify_initialized_store(store, activate = FALSE)
  validate_commit_plan_preconditions(store, plan)
  commit_order <- next_metadata_order(
    store$connection,
    "_graft_batches",
    "commit_order"
  )
  recorded_at <- commit_now()
  authority <- assemble_candidate_authority(
    staged,
    batch,
    plan,
    recorded_at,
    commit_order
  )

  commit_executor_append(
    store$connection,
    "_graft_record_revisions",
    authority$revisions
  )
  commit_executor_failure_hook("revisions")

  commit_executor_write_heads(store$connection, authority$heads)
  commit_executor_failure_hook("heads")

  commit_executor_append(
    store$connection,
    "_graft_record_observations",
    authority$observations
  )
  commit_executor_failure_hook("observations")

  commit_executor_write_identifiers(
    store$connection,
    authority$identifiers
  )
  commit_executor_failure_hook("identifiers")

  commit_executor_write_origins(store$connection, authority$origins)
  commit_executor_failure_hook("origins")

  commit_executor_statement_hook("rebuild_projections")
  rebuild_projection_views(store$connection, store$schema)
  commit_executor_failure_hook("projections")

  result <- result_from_candidate_rows(
    batch$batch_id,
    staged$rows,
    proc.time()[["elapsed"]] - started
  )
  committed_at <- commit_now()
  commit_executor_append(
    store$connection,
    "_graft_batches",
    committed_batch_row(
      batch,
      plan,
      result,
      recorded_at,
      committed_at,
      commit_order
    )
  )
  commit_executor_failure_hook("batch")
  list(type = "committed", result = result)
}

assemble_candidate_authority <- function(
  staged,
  batch,
  plan,
  recorded_at,
  commit_order
) {
  rows <- staged$rows
  validate_candidate_execution_rows(rows, plan)
  changed <- rows$action %in% c("insert", "update")
  revisions <- assemble_candidate_revisions(
    rows[changed, , drop = FALSE],
    batch,
    plan,
    recorded_at,
    commit_order
  )
  revision_ids <- rows$expected_revision_id
  revision_ids[changed] <- revisions$revision_id
  if (anyNA(revision_ids) || !all(nzchar(revision_ids))) {
    abort_commit_plan(
      "graft_commit_plan_invalid",
      "Every staged observation must resolve to a revision ID."
    )
  }
  origin_index <- match(
    candidate_authority_key(rows),
    candidate_authority_key(staged$origins)
  )
  if (anyNA(origin_index)) {
    abort_commit_plan(
      "graft_commit_plan_invalid",
      "Every staged observation must have one accepted origin decision."
    )
  }
  dispositions <- unname(c(
    insert = "inserted",
    update = "updated",
    match = "matched"
  )[rows$action])
  observations <- data.frame(
    record_id = rows$record_id,
    class = rows$class,
    batch_id = rep(batch$batch_id, nrow(rows)),
    disposition = dispositions,
    revision_id = revision_ids,
    origin_key = staged$origins$origin_key[origin_index],
    matched_by = rows$identity_reason,
    identity_evidence_json = rows$identity_evidence,
    observed_at = rep(recorded_at, nrow(rows)),
    stringsAsFactors = FALSE
  )
  list(
    revisions = revisions,
    heads = assemble_candidate_heads(revisions, recorded_at),
    observations = observations,
    identifiers = assemble_candidate_identifiers(
      staged$identifiers,
      recorded_at
    ),
    origins = assemble_candidate_origins(
      staged$origins,
      batch,
      recorded_at
    )
  )
}

validate_candidate_execution_rows <- function(rows, plan) {
  required <- c(
    "class",
    "input_row",
    "record_id",
    "action",
    "payload_json",
    "content_digest",
    "changed_fields_json",
    "expected_revision_id",
    "expected_revision_number",
    "expected_content_digest",
    "identity_reason",
    "identity_evidence"
  )
  if (
    !is.data.frame(rows) ||
      !all(required %in% names(rows)) ||
      !all(rows$action %in% c("insert", "update", "match")) ||
      anyNA(rows$record_id) ||
      !all(nzchar(rows$record_id))
  ) {
    abort_commit_plan(
      "graft_commit_plan_invalid",
      "The canonical staged record rows are invalid."
    )
  }
  changes <- plan@changes
  heads <- plan@preconditions$heads
  change_required <- c(
    "class",
    "input_row",
    "record_id",
    "action",
    "changed_fields",
    "expected_revision_id",
    "expected_revision_number",
    "expected_content_digest",
    "proposed_content_digest",
    "identity_reason",
    "identity_evidence"
  )
  head_required <- c(
    "class",
    "record_id",
    "expected_revision_id",
    "expected_revision_number",
    "expected_content_digest"
  )
  if (
    !is.data.frame(changes) ||
      !all(change_required %in% names(changes)) ||
      !is.data.frame(heads) ||
      !all(head_required %in% names(heads)) ||
      nrow(rows) != nrow(changes) ||
      nrow(rows) != nrow(heads)
  ) {
    abort_candidate_execution_rows()
  }
  row_key <- candidate_authority_key(rows)
  change_key <- candidate_authority_key(changes)
  row_head_key <- candidate_head_key(rows)
  head_key <- candidate_head_key(heads)
  if (
    anyDuplicated(row_key) ||
      anyDuplicated(change_key) ||
      anyDuplicated(row_head_key) ||
      anyDuplicated(head_key) ||
      !setequal(row_key, change_key) ||
      !setequal(row_head_key, head_key)
  ) {
    abort_candidate_execution_rows()
  }
  changes <- changes[match(row_key, change_key), , drop = FALSE]
  heads <- heads[match(row_head_key, head_key), , drop = FALSE]
  row_fields <- candidate_changed_fields(rows$changed_fields_json)
  payload_digests <- candidate_payload_digests(rows$payload_json)
  correlated <- identical(rows$action, changes$action) &&
    identical(rows$content_digest, changes$proposed_content_digest) &&
    identical(rows$expected_revision_id, changes$expected_revision_id) &&
    identical(
      rows$expected_revision_number,
      changes$expected_revision_number
    ) &&
    identical(
      rows$expected_content_digest,
      changes$expected_content_digest
    ) &&
    identical(rows$identity_reason, changes$identity_reason) &&
    identical(rows$identity_evidence, changes$identity_evidence) &&
    identical(row_fields, changes$changed_fields) &&
    identical(rows$class, heads$class) &&
    identical(rows$record_id, heads$record_id) &&
    identical(rows$expected_revision_id, heads$expected_revision_id) &&
    identical(
      rows$expected_revision_number,
      heads$expected_revision_number
    ) &&
    identical(
      rows$expected_content_digest,
      heads$expected_content_digest
    ) &&
    identical(payload_digests, rows$content_digest)
  if (
    !correlated ||
      !all(vapply(rows$content_digest, is_graft_digest, logical(1)))
  ) {
    abort_candidate_execution_rows()
  }
  insert <- rows$action == "insert"
  update <- rows$action == "update"
  match <- rows$action == "match"
  has_revision_id <- !is.na(rows$expected_revision_id) &
    nzchar(rows$expected_revision_id)
  revision_number <- as.numeric(rows$expected_revision_number)
  has_revision_number <- !is.na(revision_number) &
    is.finite(revision_number) &
    revision_number >= 1 &
    revision_number == floor(revision_number)
  has_content_digest <- vapply(
    rows$expected_content_digest,
    is_graft_digest,
    logical(1)
  )
  valid_insert <- !insert |
    (!has_revision_id &
      !has_revision_number &
      is.na(rows$expected_content_digest))
  valid_existing <- !(update | match) |
    (has_revision_id & has_revision_number & has_content_digest)
  valid_update <- !update |
    rows$content_digest != rows$expected_content_digest
  valid_match <- !match |
    rows$content_digest == rows$expected_content_digest
  if (
    anyNA(c(valid_insert, valid_existing, valid_update, valid_match)) ||
      !all(valid_insert) ||
      !all(valid_existing) ||
      !all(valid_update) ||
      !all(valid_match)
  ) {
    abort_candidate_execution_rows()
  }
  invisible(rows)
}

abort_candidate_execution_rows <- function() {
  abort_commit_plan(
    "graft_commit_plan_invalid",
    "The canonical staged record rows do not match the reviewed plan."
  )
}

candidate_head_key <- function(rows) {
  paste(rows$class, rows$record_id, sep = "\u001f")
}

candidate_changed_fields <- function(changed_fields_json) {
  unname(vapply(
    changed_fields_json,
    function(value) {
      fields <- tryCatch(
        jsonlite::fromJSON(value, simplifyVector = TRUE),
        error = \(error) NULL
      )
      if (is.list(fields) && length(fields) == 0L) {
        fields <- character()
      }
      if (is.null(fields) || !is.character(fields)) {
        return(NA_character_)
      }
      paste(fields, collapse = ", ")
    },
    character(1)
  ))
}

candidate_payload_digests <- function(payload_json) {
  unname(vapply(
    payload_json,
    function(value) {
      payload <- tryCatch(
        jsonlite::fromJSON(value, simplifyVector = FALSE),
        error = \(error) NULL
      )
      if (is.null(payload) || !is.list(payload)) {
        return(NA_character_)
      }
      logical_record_content_digest(payload)
    },
    character(1)
  ))
}

assemble_candidate_revisions <- function(
  rows,
  batch,
  plan,
  recorded_at,
  commit_order
) {
  if (nrow(rows) == 0L) {
    return(empty_candidate_revisions())
  }
  revision_number <- ifelse(
    is.na(rows$expected_revision_number),
    1,
    as.numeric(rows$expected_revision_number) + 1
  )
  prior_revision_id <- rows$expected_revision_id
  revision_id <- vapply(
    seq_len(nrow(rows)),
    function(index) {
      deterministic_graft_id(
        "GraftRecordRevision",
        list(
          batch_id = batch$batch_id,
          schema_build_digest = plan@schema_build_digest,
          record_id = rows$record_id[[index]],
          class = rows$class[[index]],
          revision_number = as.character(revision_number[[index]]),
          content_digest = rows$content_digest[[index]],
          prior_revision_id = prior_revision_id[[index]]
        )
      )
    },
    character(1)
  )
  data.frame(
    revision_id = revision_id,
    record_id = rows$record_id,
    class = rows$class,
    batch_id = rep(batch$batch_id, nrow(rows)),
    schema_build_digest = rep(plan@schema_build_digest, nrow(rows)),
    revision_number = revision_number,
    operation = rows$action,
    payload_json = rows$payload_json,
    content_digest = rows$content_digest,
    changed_fields_json = rows$changed_fields_json,
    prior_revision_id = prior_revision_id,
    recorded_at = rep(recorded_at, nrow(rows)),
    commit_order = rep(commit_order, nrow(rows)),
    stringsAsFactors = FALSE
  )
}

empty_candidate_revisions <- function() {
  data.frame(
    revision_id = character(),
    record_id = character(),
    class = character(),
    batch_id = character(),
    schema_build_digest = character(),
    revision_number = numeric(),
    operation = character(),
    payload_json = character(),
    content_digest = character(),
    changed_fields_json = character(),
    prior_revision_id = character(),
    recorded_at = as.POSIXct(numeric(), origin = "1970-01-01", tz = "UTC"),
    commit_order = numeric(),
    stringsAsFactors = FALSE
  )
}

assemble_candidate_heads <- function(revisions, recorded_at) {
  data.frame(
    record_id = revisions$record_id,
    class = revisions$class,
    revision_id = revisions$revision_id,
    revision_number = revisions$revision_number,
    updated_at = rep(recorded_at, nrow(revisions)),
    stringsAsFactors = FALSE
  )
}

assemble_candidate_identifiers <- function(identifiers, recorded_at) {
  if (nrow(identifiers) == 0L) {
    return(data.frame(
      record_id = character(),
      class = character(),
      namespace = character(),
      value = character(),
      normalized_value = character(),
      status = character(),
      assigned_by = character(),
      confidence = numeric(),
      created_at = as.POSIXct(
        numeric(),
        origin = "1970-01-01",
        tz = "UTC"
      ),
      stringsAsFactors = FALSE
    ))
  }
  result <- data.frame(
    record_id = identifiers$record_id,
    class = identifiers$class,
    namespace = identifiers$namespace,
    value = identifiers$value,
    normalized_value = identifiers$normalized_value,
    status = identifiers$status,
    assigned_by = identifiers$assigned_by,
    confidence = rep(1, nrow(identifiers)),
    created_at = rep(recorded_at, nrow(identifiers)),
    stringsAsFactors = FALSE
  )
  key <- paste(
    result$class,
    result$namespace,
    result$normalized_value,
    sep = "\u001f"
  )
  result[!duplicated(key), , drop = FALSE]
}

assemble_candidate_origins <- function(origins, batch, recorded_at) {
  if (
    anyNA(origins$origin_key) ||
      !all(nzchar(origins$origin_key)) ||
      any(origins$producer != batch$producer)
  ) {
    abort_commit_plan(
      "graft_commit_plan_invalid",
      "The staged origin decisions are invalid."
    )
  }
  result <- data.frame(
    record_id = origins$record_id,
    class = origins$class,
    producer = origins$producer,
    origin_key = origins$origin_key,
    first_batch_id = rep(batch$batch_id, nrow(origins)),
    created_at = rep(recorded_at, nrow(origins)),
    stringsAsFactors = FALSE
  )
  key <- paste(
    result$class,
    result$producer,
    result$origin_key,
    sep = "\u001f"
  )
  result[!duplicated(key), , drop = FALSE]
}

candidate_authority_key <- function(rows) {
  paste(rows$class, rows$input_row, rows$record_id, sep = "\u001f")
}

commit_executor_write_heads <- function(connection, heads) {
  if (nrow(heads) == 0L) {
    return(invisible(heads))
  }
  commit_executor_stage_table(connection, commit_executor_head_stage, heads)
  target <- quote_identifier(connection, "_graft_record_heads")
  source <- quote_identifier(connection, commit_executor_head_stage)
  commit_executor_execute(
    connection,
    paste0(
      "MERGE INTO ",
      target,
      " AS target USING ",
      source,
      " AS source ON target.record_id = source.record_id ",
      "WHEN MATCHED THEN UPDATE SET class = source.class, ",
      "revision_id = source.revision_id, ",
      "revision_number = source.revision_number, ",
      "updated_at = source.updated_at ",
      "WHEN NOT MATCHED THEN INSERT ",
      "(record_id, class, revision_id, revision_number, updated_at) ",
      "VALUES (source.record_id, source.class, source.revision_id, ",
      "source.revision_number, source.updated_at)"
    )
  )
  commit_executor_drop_stage(connection, commit_executor_head_stage)
  invisible(heads)
}

commit_executor_write_identifiers <- function(connection, identifiers) {
  if (nrow(identifiers) == 0L) {
    return(invisible(identifiers))
  }
  commit_executor_stage_table(
    connection,
    commit_executor_identifier_stage,
    identifiers
  )
  target <- quote_identifier(connection, "_graft_identifiers")
  source <- quote_identifier(connection, commit_executor_identifier_stage)
  conflict <- commit_executor_query(
    connection,
    paste0(
      "SELECT source.class, source.namespace, source.normalized_value, ",
      "source.record_id AS planned_record_id, ",
      "target.record_id AS observed_record_id FROM ",
      source,
      " AS source INNER JOIN ",
      target,
      " AS target ON target.class = source.class ",
      "AND target.namespace = source.namespace ",
      "AND target.normalized_value = source.normalized_value ",
      "WHERE target.record_id <> source.record_id LIMIT 1"
    )
  )
  if (nrow(conflict) > 0L) {
    abort_identity_error(
      "An identifier registry key belongs to a different record.",
      record_class = conflict$class[[1L]],
      record_id = conflict$planned_record_id[[1L]],
      field = conflict$namespace[[1L]],
      rule = "active_identifier_agreement",
      matched_record_ids = conflict$observed_record_id[[1L]]
    )
  }
  commit_executor_execute(
    connection,
    paste0(
      "MERGE INTO ",
      target,
      " AS target USING ",
      source,
      " AS source ON target.class = source.class ",
      "AND target.namespace = source.namespace ",
      "AND target.normalized_value = source.normalized_value ",
      "WHEN MATCHED AND target.record_id = source.record_id THEN UPDATE SET ",
      "value = source.value, status = source.status, ",
      "assigned_by = source.assigned_by, confidence = source.confidence, ",
      "created_at = source.created_at ",
      "WHEN NOT MATCHED THEN INSERT ",
      "(record_id, class, namespace, value, normalized_value, status, ",
      "assigned_by, confidence, created_at) VALUES ",
      "(source.record_id, source.class, source.namespace, source.value, ",
      "source.normalized_value, source.status, source.assigned_by, ",
      "source.confidence, source.created_at)"
    )
  )
  commit_executor_drop_stage(connection, commit_executor_identifier_stage)
  invisible(identifiers)
}

commit_executor_write_origins <- function(connection, origins) {
  if (nrow(origins) == 0L) {
    return(invisible(origins))
  }
  commit_executor_stage_table(connection, commit_executor_origin_stage, origins)
  target <- quote_identifier(connection, "_graft_origins")
  source <- quote_identifier(connection, commit_executor_origin_stage)
  conflict <- commit_executor_query(
    connection,
    paste0(
      "SELECT source.class, source.producer, source.origin_key, ",
      "source.record_id AS planned_record_id, ",
      "target.record_id AS observed_record_id FROM ",
      source,
      " AS source INNER JOIN ",
      target,
      " AS target ON target.class = source.class ",
      "AND target.producer = source.producer ",
      "AND target.origin_key = source.origin_key ",
      "WHERE target.record_id <> source.record_id LIMIT 1"
    )
  )
  if (nrow(conflict) > 0L) {
    abort_identity_error(
      "A producer origin key belongs to a different record.",
      record_class = conflict$class[[1L]],
      record_id = conflict$planned_record_id[[1L]],
      field = ".graft_origin_key",
      rule = "origin_identity_agreement",
      observed_value = conflict$origin_key[[1L]],
      matched_record_ids = conflict$observed_record_id[[1L]]
    )
  }
  commit_executor_execute(
    connection,
    paste0(
      "INSERT INTO ",
      target,
      " (record_id, class, producer, origin_key, first_batch_id, created_at) ",
      "SELECT source.record_id, source.class, source.producer, ",
      "source.origin_key, source.first_batch_id, source.created_at FROM ",
      source,
      " AS source LEFT JOIN ",
      target,
      " AS target ON target.class = source.class ",
      "AND target.producer = source.producer ",
      "AND target.origin_key = source.origin_key ",
      "WHERE target.record_id IS NULL"
    )
  )
  commit_executor_drop_stage(connection, commit_executor_origin_stage)
  invisible(origins)
}

result_from_candidate_rows <- function(batch_id, rows, duration) {
  classes <- unique(rows$class)
  count <- function(action) {
    stats::setNames(
      vapply(
        classes,
        \(record_class) {
          sum(rows$class == record_class & rows$action == action)
        },
        integer(1)
      ),
      classes
    )
  }
  observed <- stats::setNames(
    vapply(
      classes,
      \(record_class) sum(rows$class == record_class),
      integer(1)
    ),
    classes
  )
  new_commit_result(
    batch_id = batch_id,
    inserted = count("insert"),
    updated = count("update"),
    matched = count("match"),
    observed = observed,
    duration = duration
  )
}

committed_batch_row <- function(
  batch,
  plan,
  result,
  started_at,
  committed_at,
  commit_order
) {
  data.frame(
    batch_id = batch$batch_id,
    schema_build_digest = plan@schema_build_digest,
    commit_order = commit_order,
    producer = batch$producer,
    producer_version = batch$producer_version,
    source_run_id = batch$source_run_id,
    idempotency_key = batch$idempotency_key,
    metadata_json = commit_batch_metadata_json(batch$metadata, result),
    started_at = started_at,
    committed_at = committed_at,
    status = "committed",
    stringsAsFactors = FALSE
  )
}

commit_executor_append <- function(connection, table, rows) {
  if (nrow(rows) == 0L) {
    return(invisible(rows))
  }
  commit_executor_statement_hook(paste0("append:", table))
  DBI::dbAppendTable(connection, table, rows)
  invisible(rows)
}

commit_executor_stage_table <- function(connection, table, rows) {
  commit_executor_statement_hook(paste0("stage:", table))
  DBI::dbWriteTable(
    connection,
    table,
    rows,
    temporary = TRUE,
    overwrite = TRUE
  )
  invisible(rows)
}

commit_executor_query <- function(connection, sql) {
  commit_executor_statement_hook("query")
  DBI::dbGetQuery(connection, sql)
}

commit_executor_execute <- function(connection, sql) {
  commit_executor_statement_hook("execute")
  DBI::dbExecute(connection, sql)
}

commit_executor_drop_stage <- function(connection, table) {
  commit_executor_statement_hook(paste0("drop:", table))
  DBI::dbRemoveTable(connection, table)
  invisible(connection)
}

commit_executor_statement_hook <- function(operation) {
  invisible(operation)
}

commit_executor_failure_hook <- function(stage) {
  if (identical(getOption("graft.commit_executor_failure_stage"), stage)) {
    abort_backend_error(
      paste0("Forced bulk commit failure after `", stage, "`."),
      operation = "commit_plan",
      stage = stage
    )
  }
  invisible(stage)
}
