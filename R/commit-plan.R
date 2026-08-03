GraftCommitPlan <- S7::new_class(
  "GraftCommitPlan",
  package = "graft",
  properties = list(
    plan_version = S7::new_property(
      S7::class_character,
      getter = \(self) commit_plan_data(self)$plan_version
    ),
    plan_id = S7::new_property(
      S7::class_character,
      getter = \(self) commit_plan_data(self)$plan_id
    ),
    source = S7::new_property(
      S7::class_character,
      getter = \(self) commit_plan_data(self)$source
    ),
    store_id = S7::new_property(
      S7::class_character,
      getter = \(self) commit_plan_data(self)$store_id
    ),
    store_format_version = S7::new_property(
      S7::class_character,
      getter = \(self) commit_plan_data(self)$store_format_version
    ),
    schema_build_digest = S7::new_property(
      S7::class_character,
      getter = \(self) commit_plan_data(self)$schema_build_digest
    ),
    schema_structural_digest = S7::new_property(
      S7::class_character,
      getter = \(self) commit_plan_data(self)$schema_structural_digest
    ),
    planned_at = S7::new_property(
      S7::class_POSIXct,
      getter = \(self) commit_plan_data(self)$planned_at
    ),
    provenance = S7::new_property(
      S7::class_any,
      getter = \(self) commit_plan_data(self)$provenance
    ),
    records = S7::new_property(
      S7::class_list,
      getter = \(self) commit_plan_data(self)$records
    ),
    changes = S7::new_property(
      S7::class_data.frame,
      getter = \(self) commit_plan_data(self)$changes
    ),
    issues = S7::new_property(
      S7::class_data.frame,
      getter = \(self) commit_plan_data(self)$issues
    ),
    preconditions = S7::new_property(
      S7::class_list,
      getter = \(self) commit_plan_data(self)$preconditions
    ),
    input_digest = S7::new_property(
      S7::class_character,
      getter = \(self) commit_plan_data(self)$input_digest
    ),
    execution_digest = S7::new_property(
      S7::class_character,
      getter = \(self) commit_plan_data(self)$execution_digest
    ),
    plan_digest = S7::new_property(
      S7::class_character,
      getter = \(self) commit_plan_data(self)$plan_digest
    ),
    valid = S7::new_property(
      S7::class_logical,
      getter = \(self) nrow(commit_plan_data(self)$issues) == 0L
    )
  ),
  constructor = function(data, execution) {
    S7::new_object(
      S7::S7_object(),
      .data = data,
      .execution = execution
    )
  },
  validator = function(self) {
    data <- commit_plan_data(self)
    if (!identical(names(data), commit_plan_field_names())) {
      return("internal commit-plan fields are invalid")
    }
    if (!self@source %in% c("records", "okf")) {
      return("@source must be `records` or `okf`")
    }
    if (!is_graft_provenance(self@provenance)) {
      return("@provenance must be a GraftProvenance object")
    }
    if (!identical(names(self@changes), names(empty_plan_changes()))) {
      return("@changes has invalid columns")
    }
    if (!identical(names(self@issues), names(empty_plan_issues()))) {
      return("@issues has invalid columns")
    }
    digests <- c(
      self@schema_build_digest,
      self@schema_structural_digest,
      self@input_digest,
      self@execution_digest,
      self@plan_digest
    )
    if (!all(vapply(digests, is_graft_digest, logical(1)))) {
      return("commit-plan digests must be canonical SHA-256 values")
    }
    NULL
  }
)

#' Plan a candidate knowledge change without writing it
#'
#' Planning normalizes records, resolves identity, validates the candidate set,
#' and binds its expected record heads to the active store and schema. It does
#' not persist records or batch metadata. Invalid input returns a plan whose
#' `@valid` property is `FALSE` and whose `@issues` table describes the failure.
#'
#' @param store An initialized `kg_store`.
#' @param records A named list of concrete-class data frames.
#' @param provenance A [graft_provenance()] object.
#'
#' @return An immutable `GraftCommitPlan` S7 object.
#' @export
graft_plan <- function(store, records, provenance) {
  graft_plan_records(
    store = store,
    records = records,
    provenance = provenance,
    source = "records"
  )
}

graft_plan_records <- function(
  store,
  records,
  provenance,
  source,
  source_preconditions = list()
) {
  validate_initialized_store_for_ingest(store, write = FALSE, refresh = TRUE)
  provenance <- as_graft_provenance(provenance)
  metadata <- read_store_metadata(store$connection)
  planned_at <- commit_plan_snapshot_time(store$connection, metadata)
  input_digest <- graft_sha256(
    list(records = records, provenance = provenance_data(provenance)),
    serialize = TRUE
  )
  temporary_batch_id <- deterministic_graft_id(
    "GraftPlanInput",
    list(
      store_id = scalar_character(metadata$store_id),
      input_digest = input_digest
    )
  )
  batch <- provenance_batch(provenance, temporary_batch_id)
  failure <- NULL
  staged <- tryCatch(
    prepare_ingest_records(store, batch, records, planned_at),
    graft_validation_error = function(condition) {
      failure <<- condition
      NULL
    },
    graft_identity_error = function(condition) {
      failure <<- condition
      NULL
    },
    graft_reference_error = function(condition) {
      failure <<- condition
      NULL
    },
    graft_schema_error = function(condition) {
      failure <<- condition
      NULL
    }
  )

  if (is.null(failure)) {
    plan_records <- staged_plan_records(staged)
    changes <- staged_plan_changes(store, staged)
    issues <- empty_plan_issues()
    execution <- list(staged = staged)
  } else {
    plan_records <- list()
    changes <- empty_plan_changes()
    issues <- condition_plan_issue(failure)
    execution <- NULL
  }
  heads <- changes[
    c(
      "class",
      "record_id",
      "expected_revision_id",
      "expected_content_digest"
    )
  ]
  preconditions <- list(
    heads = heads,
    source = source_preconditions
  )
  new_graft_commit_plan(
    source = source,
    store_id = scalar_character(metadata$store_id),
    store_format_version = scalar_character(metadata$store_format_version),
    schema_build_digest = scalar_character(
      store$schema$manifest$fingerprints$build_digest
    ),
    schema_structural_digest = store_schema_digest(store),
    planned_at = planned_at,
    provenance = provenance,
    records = plan_records,
    changes = changes,
    issues = issues,
    preconditions = preconditions,
    input_digest = input_digest,
    execution = execution
  )
}

#' Commit a reviewed knowledge-change plan
#'
#' Before writing, Graft rechecks the plan digest, store identity and format,
#' active schema, write capability, source state, and every expected record
#' head. All accepted changes then commit in one DuckDB transaction.
#'
#' @param store An initialized, writable `kg_store`.
#' @param plan A valid `GraftCommitPlan` returned by [graft_plan()] or
#'   [graft_review()].
#'
#' @return A `kg_ingest_result` describing the committed observations.
#' @export
graft_commit <- function(store, plan) {
  started <- proc.time()[["elapsed"]]
  validate_initialized_store_for_ingest(store, write = TRUE, refresh = TRUE)
  plan <- validate_graft_commit_plan(plan)
  if (!isTRUE(plan@valid)) {
    abort_commit_plan(
      "graft_commit_plan_invalid",
      "A commit plan with validation issues cannot be committed.",
      issues = plan@issues
    )
  }
  execution <- commit_plan_execution(plan)
  if (!is.list(execution) || !is.list(execution$staged)) {
    abort_commit_plan(
      "graft_commit_plan_invalid",
      "The commit plan does not contain an executable candidate set."
    )
  }
  validate_commit_plan_static_binding(store, plan)
  batch <- provenance_batch(plan@provenance, plan@plan_id)
  replay <- find_committed_replay(store$connection, batch)
  if (!is.null(replay)) {
    validate_commit_plan_replay(plan, replay)
    replay$replay <- TRUE
    signal_batch_replay(replay)
    return(replay)
  }

  commit_prepared_plan(
    store = store,
    batch = batch,
    staged = execution$staged,
    plan = plan,
    started = started
  )
}

#' Plan and immediately commit candidate records
#'
#' This convenience function is equivalent to calling [graft_plan()] followed
#' by [graft_commit()]. Use the two-step form when a person or host policy must
#' review `plan@changes` before acceptance.
#'
#' @inheritParams graft_plan
#'
#' @return A `kg_ingest_result` describing the committed observations.
#' @export
graft_ingest <- function(store, records, provenance) {
  plan <- graft_plan(store, records, provenance)
  graft_commit(store, plan)
}

new_graft_commit_plan <- function(
  source,
  store_id,
  store_format_version,
  schema_build_digest,
  schema_structural_digest,
  planned_at,
  provenance,
  records,
  changes,
  issues,
  preconditions,
  input_digest,
  execution
) {
  provenance <- as_graft_provenance(provenance)
  execution_digest <- graft_sha256(canonical_json(execution))
  data <- list(
    plan_version = graft_plan_version,
    plan_id = "",
    source = source,
    store_id = store_id,
    store_format_version = store_format_version,
    schema_build_digest = schema_build_digest,
    schema_structural_digest = schema_structural_digest,
    planned_at = as.POSIXct(planned_at, tz = "UTC"),
    provenance = provenance,
    records = records,
    changes = changes,
    issues = issues,
    preconditions = preconditions,
    input_digest = input_digest,
    execution_digest = execution_digest,
    plan_digest = ""
  )
  data$plan_digest <- graft_sha256(
    canonical_json(commit_plan_digest_data(data))
  )
  data$plan_id <- deterministic_graft_id(
    "GraftCommitPlan",
    list(plan_digest = data$plan_digest)
  )
  GraftCommitPlan(data, execution)
}

commit_plan_field_names <- function() {
  c(
    "plan_version",
    "plan_id",
    "source",
    "store_id",
    "store_format_version",
    "schema_build_digest",
    "schema_structural_digest",
    "planned_at",
    "provenance",
    "records",
    "changes",
    "issues",
    "preconditions",
    "input_digest",
    "execution_digest",
    "plan_digest"
  )
}

commit_plan_data <- function(plan) {
  attr(plan, ".data", exact = TRUE)
}

commit_plan_execution <- function(plan) {
  attr(plan, ".execution", exact = TRUE)
}

commit_plan_digest_data <- function(data) {
  list(
    plan_version = data$plan_version,
    source = data$source,
    store_id = data$store_id,
    store_format_version = data$store_format_version,
    schema_build_digest = data$schema_build_digest,
    schema_structural_digest = data$schema_structural_digest,
    planned_at = data$planned_at,
    provenance = provenance_data(data$provenance),
    records = data$records,
    changes = data$changes,
    issues = data$issues,
    preconditions = data$preconditions,
    input_digest = data$input_digest,
    execution_digest = data$execution_digest
  )
}

validate_graft_commit_plan <- function(plan) {
  if (!S7::S7_inherits(plan, GraftCommitPlan)) {
    abort_commit_plan(
      "graft_commit_plan_invalid",
      "`plan` must be a GraftCommitPlan object.",
      argument = "plan"
    )
  }
  data <- commit_plan_data(plan)
  if (!is.list(data) || !identical(names(data), commit_plan_field_names())) {
    abort_commit_plan(
      "graft_commit_plan_tampered",
      "The commit plan structure is invalid; create and review a new plan."
    )
  }
  as_graft_provenance(data$provenance, "plan@provenance")
  execution_digest <- tryCatch(
    graft_sha256(canonical_json(commit_plan_execution(plan))),
    error = function(error) NA_character_
  )
  expected_digest <- tryCatch(
    graft_sha256(canonical_json(commit_plan_digest_data(data))),
    error = function(error) NA_character_
  )
  expected_id <- if (is_graft_digest(expected_digest)) {
    deterministic_graft_id(
      "GraftCommitPlan",
      list(plan_digest = expected_digest)
    )
  } else {
    NA_character_
  }
  if (
    !identical(execution_digest, data$execution_digest) ||
      !identical(expected_digest, data$plan_digest) ||
      !identical(expected_id, data$plan_id)
  ) {
    abort_commit_plan(
      "graft_commit_plan_tampered",
      "The commit plan digest is invalid; create and review a new plan.",
      expected_digest = expected_digest,
      observed_digest = data$plan_digest
    )
  }
  plan
}

validate_commit_plan_preconditions <- function(store, plan) {
  validate_commit_plan_static_binding(store, plan)
  validate_commit_plan_heads(store, plan@preconditions$heads)
  validate_commit_plan_source(store, plan)
  invisible(plan)
}

validate_commit_plan_static_binding <- function(store, plan) {
  metadata <- read_store_metadata(store$connection)
  observed <- list(
    store_id = scalar_character(metadata$store_id),
    store_format_version = scalar_character(metadata$store_format_version),
    schema_build_digest = scalar_character(metadata$active_build_digest),
    schema_structural_digest = scalar_character(
      metadata$active_structural_digest
    )
  )
  expected <- list(
    store_id = plan@store_id,
    store_format_version = plan@store_format_version,
    schema_build_digest = plan@schema_build_digest,
    schema_structural_digest = plan@schema_structural_digest
  )
  if (!identical(observed, expected)) {
    abort_commit_plan(
      "graft_commit_plan_stale",
      "The store or active schema changed after planning.",
      expected = expected,
      observed = observed
    )
  }
  invisible(plan)
}

validate_commit_plan_replay <- function(plan, replay) {
  if (identical(replay$batch_id, plan@plan_id)) {
    return(invisible(replay))
  }
  abort_commit_plan(
    "graft_commit_plan_replay_conflict",
    paste0(
      "The producer/idempotency key is already committed for a different ",
      "plan."
    ),
    producer = plan@provenance@producer,
    idempotency_key = plan@provenance@idempotency_key,
    expected_batch_id = plan@plan_id,
    observed_batch_id = replay$batch_id
  )
}

commit_plan_snapshot_time <- function(connection, metadata) {
  latest <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT MAX(committed_at) AS committed_at FROM ",
      quote_identifier(connection, "_graft_batches"),
      " WHERE status = 'committed'"
    )
  )
  candidates <- as.numeric(c(
    metadata$updated_at,
    latest$committed_at[[1L]]
  ))
  candidates <- candidates[is.finite(candidates)]
  if (length(candidates) == 0L) {
    abort_backend_error(
      "The store has no durable timestamp for a commit-plan snapshot.",
      operation = "plan_snapshot"
    )
  }
  as.POSIXct(
    max(candidates),
    origin = "1970-01-01",
    tz = "UTC"
  )
}

validate_commit_plan_heads <- function(store, heads) {
  if (nrow(heads) == 0L) {
    return(invisible(heads))
  }
  for (index in seq_len(nrow(heads))) {
    current <- read_record_head(store$connection, heads$record_id[[index]])
    current_revision <- if (nrow(current) == 0L) {
      NA_character_
    } else {
      current$revision_id[[1L]]
    }
    current_digest <- if (nrow(current) == 0L) {
      NA_character_
    } else {
      current$content_digest[[1L]]
    }
    if (
      !identical(current_revision, heads$expected_revision_id[[index]]) ||
        !identical(current_digest, heads$expected_content_digest[[index]])
    ) {
      abort_commit_plan(
        "graft_commit_plan_stale",
        paste0(
          "Record `",
          heads$record_id[[index]],
          "` changed after planning."
        ),
        record_id = heads$record_id[[index]],
        record_class = heads$class[[index]],
        expected_revision_id = heads$expected_revision_id[[index]],
        observed_revision_id = current_revision
      )
    }
  }
  invisible(heads)
}

validate_commit_plan_source <- function(store, plan) {
  if (!identical(plan@source, "okf")) {
    return(invisible(plan))
  }
  source <- plan@preconditions$source
  if (
    !is.list(source) ||
      !identical(names(source), c("path", "base_batch_id", "bundle_digest"))
  ) {
    abort_commit_plan(
      "graft_commit_plan_tampered",
      "The OKF source preconditions are invalid."
    )
  }
  current_batch <- scalar_character(okf_current_boundary(store)$batch_id, "")
  observed_digest <- if (dir.exists(source$path)) {
    okf_bundle_digest(source$path)
  } else {
    NA_character_
  }
  if (
    !identical(current_batch, source$base_batch_id) ||
      !identical(observed_digest, source$bundle_digest)
  ) {
    abort_commit_plan(
      "graft_commit_plan_stale",
      "The accepted store or edited OKF bundle changed after review.",
      expected_batch_id = source$base_batch_id,
      observed_batch_id = current_batch,
      expected_bundle_digest = source$bundle_digest,
      observed_bundle_digest = observed_digest
    )
  }
  invisible(plan)
}

commit_prepared_plan <- function(store, batch, staged, plan, started) {
  started_at <- ingest_now()
  with_duckdb_error(
    "commit_plan",
    DBI::dbWithTransaction(store$connection, {
      verify_initialized_store(store, activate = TRUE)
      validate_commit_plan_preconditions(store, plan)
      commit_order <- next_metadata_order(
        store$connection,
        "_graft_batches",
        "commit_order"
      )
      insert_started_batch(
        store$connection,
        batch,
        started_at,
        plan@schema_build_digest,
        commit_order
      )
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
      commit_batch(store$connection, batch, result, ingest_now())
      result
    })
  )
}

staged_plan_records <- function(staged) {
  result <- lapply(staged, function(class_staged) {
    slots <- class_staged$contract$slots
    columns <- lapply(names(slots), function(slot_name) {
      slot <- slots[[slot_name]]
      if (scalar_logical(slot$multivalued)) {
        return(I(class_staged$multivalues[[slot_name]]))
      }
      column <- scalar_character(slot$column, slot_name)
      class_staged$data[[column]]
    })
    names(columns) <- names(slots)
    as.data.frame(
      columns,
      stringsAsFactors = FALSE,
      check.names = FALSE,
      optional = TRUE
    )
  })
  names(result) <- names(staged)
  result
}

staged_plan_changes <- function(store, staged) {
  rows <- list()
  for (record_class in names(staged)) {
    class_staged <- staged[[record_class]]
    for (index in seq_len(nrow(class_staged$data))) {
      record_id <- class_staged$data$id[[index]]
      disposition <- class_staged$disposition[[index]]
      head <- read_record_head(store$connection, record_id)
      validate_staged_head(head, record_class, record_id, disposition)
      payload <- logical_record_payload(class_staged, index)
      prior_payload <- if (nrow(head) == 0L) {
        NULL
      } else {
        parse_revision_payload(head$payload_json[[1L]])
      }
      changed_fields <- if (identical(disposition, "matched")) {
        character()
      } else {
        logical_record_changed_fields(payload, prior_payload)
      }
      rows[[length(rows) + 1L]] <- data.frame(
        class = record_class,
        input_row = as.integer(class_staged$input_row[[index]]),
        record_id = record_id,
        action = switch(
          disposition,
          inserted = "insert",
          updated = "update",
          matched = "match"
        ),
        changed_fields = paste(changed_fields, collapse = ", "),
        expected_revision_id = if (nrow(head) == 0L) {
          NA_character_
        } else {
          head$revision_id[[1L]]
        },
        expected_content_digest = if (nrow(head) == 0L) {
          NA_character_
        } else {
          head$content_digest[[1L]]
        },
        proposed_content_digest = logical_record_content_digest(payload),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0L) {
    return(empty_plan_changes())
  }
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}

empty_plan_changes <- function() {
  data.frame(
    class = character(),
    input_row = integer(),
    record_id = character(),
    action = character(),
    changed_fields = character(),
    expected_revision_id = character(),
    expected_content_digest = character(),
    proposed_content_digest = character(),
    stringsAsFactors = FALSE
  )
}

empty_plan_issues <- function() {
  data.frame(
    class = character(),
    input_row = integer(),
    record_id = character(),
    field = character(),
    rule = character(),
    message = character(),
    condition_class = character(),
    stringsAsFactors = FALSE
  )
}

condition_plan_issue <- function(condition) {
  data.frame(
    class = scalar_character(condition$record_class, ""),
    input_row = if (is.null(condition$input_row)) {
      NA_integer_
    } else {
      as.integer(condition$input_row)
    },
    record_id = scalar_character(condition$record_id, ""),
    field = scalar_character(condition$field, ""),
    rule = scalar_character(condition$rule, ""),
    message = conditionMessage(condition),
    condition_class = class(condition)[[1L]],
    stringsAsFactors = FALSE
  )
}
