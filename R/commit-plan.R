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
#' @param store An initialized `GraftStore`.
#' @param records A named list of concrete-class data frames.
#' @param provenance A [graft_provenance()] object.
#'
#' @return An immutable `GraftCommitPlan` S7 object.
#' @export
graft_plan <- function(store, records, provenance) {
  store <- as_graft_store_internal(store, "store")
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
  validate_initialized_store(store, write = FALSE, refresh = TRUE)
  provenance <- as_graft_provenance(provenance)
  metadata <- read_store_metadata(store$connection)
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
  batch <- commit_batch_from_provenance(provenance, temporary_batch_id)
  candidate <- plan_candidate_records(store, batch, records, metadata)
  heads <- candidate$changes[
    c(
      "class",
      "record_id",
      "expected_revision_id",
      "expected_revision_number",
      "expected_content_digest"
    )
  ]
  preconditions <- list(
    heads = heads,
    definitions = candidate$definition_preconditions,
    registries = candidate$registry_preconditions,
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
    planned_at = candidate$planned_at,
    provenance = provenance,
    records = candidate$records,
    changes = candidate$changes,
    issues = candidate$issues,
    preconditions = preconditions,
    input_digest = input_digest,
    execution = list(staged = candidate$execution)
  )
}

#' Commit a reviewed knowledge-change plan
#'
#' Before writing, Graft rechecks the plan digest, store identity and format,
#' active schema, write capability, source state, and every expected record
#' head. All accepted changes then commit in one DuckDB transaction.
#'
#' @param store An initialized, writable `GraftStore`.
#' @param plan A valid `GraftCommitPlan` returned by [graft_plan()] or
#'   [graft_review()].
#'
#' @return An ordinary list summarizing committed observations.
#' @export
graft_commit <- function(store, plan) {
  store <- as_graft_store_internal(store, "store")
  commit_graft_plan(store, plan)
}

commit_graft_plan <- function(store, plan, finalize = NULL) {
  started <- proc.time()[["elapsed"]]
  validate_initialized_store(store, write = TRUE, refresh = TRUE)
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
  batch <- commit_batch_from_provenance(plan@provenance, plan@plan_id)
  replay <- find_committed_replay(store$connection, batch)
  if (!is.null(replay) && is.null(finalize)) {
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
    started = started,
    finalize = finalize
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
#' @return An ordinary list summarizing committed observations.
#' @export
graft_ingest <- function(store, records, provenance) {
  store <- as_graft_store_internal(store, "store")
  plan <- graft_plan_records(
    store = store,
    records = records,
    provenance = provenance,
    source = "records"
  )
  commit_graft_plan(store, plan)
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
  # A plan serialized under an earlier format lacks columns reviewers now
  # rely on, so it must be re-planned rather than committed as reviewed.
  if (
    !identical(data$plan_version, graft_plan_version) ||
      !identical(names(data$changes), names(empty_plan_changes()))
  ) {
    abort_commit_plan(
      "graft_commit_plan_invalid",
      paste0(
        "The commit plan uses plan format `",
        scalar_character(data$plan_version, "unknown"),
        "`, but this Graft commits format `",
        graft_plan_version,
        "`; create and review a new plan."
      ),
      plan_version = data$plan_version
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
  validate_commit_plan_definitions(store, plan)
  validate_commit_plan_registries(store, plan)
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

commit_plan_snapshot_time <- function(connection, metadata, latest = NULL) {
  if (is.null(latest)) {
    latest <- DBI::dbGetQuery(
      connection,
      paste0(
        "SELECT MAX(committed_at) AS committed_at FROM ",
        quote_identifier(connection, "_graft_batches"),
        " WHERE status = 'committed'"
      )
    )
  }
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
  placeholders <- paste(rep("?", nrow(heads)), collapse = ", ")
  current_heads <- DBI::dbGetQuery(
    store$connection,
    paste0(
      "SELECT h.record_id, h.class, h.revision_id, h.revision_number, ",
      "r.record_id AS ledger_record_id, r.class AS ledger_class, ",
      "r.revision_id AS ledger_revision_id, ",
      "r.revision_number AS ledger_revision_number, r.content_digest FROM ",
      quote_identifier(store$connection, "_graft_record_heads"),
      " AS h LEFT JOIN ",
      quote_identifier(store$connection, "_graft_record_revisions"),
      " AS r ON r.record_id = h.record_id AND r.class = h.class ",
      "AND r.revision_id = h.revision_id ",
      "AND r.revision_number = h.revision_number ",
      "WHERE h.record_id IN (",
      placeholders,
      ")"
    ),
    params = as.list(heads$record_id)
  )
  current_index <- match(heads$record_id, current_heads$record_id)
  for (index in seq_len(nrow(heads))) {
    current_row <- current_index[[index]]
    current_revision <- if (is.na(current_row)) {
      NA_character_
    } else {
      current_heads$revision_id[[current_row]]
    }
    current_digest <- if (is.na(current_row)) {
      NA_character_
    } else {
      current_heads$content_digest[[current_row]]
    }
    current_class <- if (is.na(current_row)) {
      NA_character_
    } else {
      current_heads$class[[current_row]]
    }
    current_number <- if (is.na(current_row)) {
      NA_real_
    } else {
      as.numeric(current_heads$revision_number[[current_row]])
    }
    dangling <- !is.na(current_row) &&
      (is.na(current_heads$ledger_revision_id[[current_row]]) ||
        !identical(
          current_heads$ledger_record_id[[current_row]],
          current_heads$record_id[[current_row]]
        ) ||
        !identical(
          current_heads$ledger_class[[current_row]],
          current_heads$class[[current_row]]
        ) ||
        !identical(
          current_heads$ledger_revision_id[[current_row]],
          current_heads$revision_id[[current_row]]
        ) ||
        !identical(
          as.numeric(current_heads$ledger_revision_number[[current_row]]),
          current_number
        ))
    expected_revision <- heads$expected_revision_id[[index]]
    expected_number <- as.numeric(heads$expected_revision_number[[index]])
    expected_exists <- !is.na(expected_revision)
    observed_exists <- !is.na(current_row)
    changed <- expected_exists != observed_exists ||
      expected_exists &&
        observed_exists &&
        (!identical(current_class, heads$class[[index]]) ||
          !identical(current_revision, expected_revision) ||
          !identical(current_number, expected_number) ||
          !identical(
            current_digest,
            heads$expected_content_digest[[index]]
          ) ||
          dangling)
    if (changed) {
      abort_commit_plan(
        "graft_commit_plan_stale",
        paste0(
          "Record `",
          heads$record_id[[index]],
          "` changed after planning."
        ),
        record_id = heads$record_id[[index]],
        record_class = heads$class[[index]],
        expected_revision_id = expected_revision,
        observed_revision_id = current_revision,
        expected_revision_number = expected_number,
        observed_revision_number = current_number,
        dangling_head = dangling
      )
    }
  }
  invisible(heads)
}

validate_commit_plan_registries <- function(store, plan) {
  expected <- plan@preconditions$registries
  if (
    !is.list(expected) ||
      !identical(names(expected), c("identifier_digest", "origin_digest")) ||
      !all(vapply(expected, is_graft_digest, logical(1)))
  ) {
    abort_commit_plan(
      "graft_commit_plan_tampered",
      "The identity-registry preconditions are invalid."
    )
  }
  identifiers <- DBI::dbGetQuery(
    store$connection,
    planning_identifiers_sql(store$connection)
  )
  origins <- DBI::dbGetQuery(
    store$connection,
    planning_origins_sql(store$connection),
    params = list(plan@provenance@producer)
  )
  observed <- list(
    identifier_digest = planning_snapshot_digest(identifiers),
    origin_digest = planning_snapshot_digest(origins)
  )
  if (!identical(observed, expected)) {
    abort_commit_plan(
      "graft_commit_plan_stale",
      "An identity registry changed after planning.",
      expected = expected,
      observed = observed
    )
  }
  invisible(plan)
}

validate_commit_plan_definitions <- function(store, plan) {
  expected <- plan@preconditions$definitions
  if (
    !is.list(expected) ||
      !identical(names(expected), c("required", "catalog_digest")) ||
      !is_scalar_flag(expected$required) ||
      !is_graft_digest(expected$catalog_digest)
  ) {
    abort_commit_plan(
      "graft_commit_plan_tampered",
      "The definition-catalog preconditions are invalid."
    )
  }
  if (!expected$required) {
    return(invisible(plan))
  }
  current <- DBI::dbGetQuery(
    store$connection,
    paste0(
      "SELECT h.record_id, h.class, h.revision_id, h.revision_number, ",
      "r.record_id AS ledger_record_id, r.class AS ledger_class, ",
      "r.revision_id AS ledger_revision_id, ",
      "r.revision_number AS ledger_revision_number, r.operation, ",
      "r.payload_json, r.content_digest FROM ",
      quote_identifier(store$connection, "_graft_record_heads"),
      " AS h LEFT JOIN ",
      quote_identifier(store$connection, "_graft_record_revisions"),
      " AS r ON r.record_id = h.record_id AND r.class = h.class ",
      "AND r.revision_id = h.revision_id ",
      "AND r.revision_number = h.revision_number ",
      "WHERE h.class = ? ORDER BY h.record_id"
    ),
    params = list(graft_definition_class_name)
  )
  validate_planning_head_snapshot(current)
  observed <- planning_definition_catalog_digest(current)
  if (!identical(observed, expected$catalog_digest)) {
    abort_commit_plan(
      "graft_commit_plan_stale",
      "The accepted definition catalog changed after planning.",
      expected_digest = expected$catalog_digest,
      observed_digest = observed
    )
  }
  invisible(plan)
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

commit_prepared_plan <- function(
  store,
  batch,
  staged,
  plan,
  started,
  finalize = NULL
) {
  if (!identical(staged$format, candidate_stage_version)) {
    abort_commit_plan(
      "graft_commit_plan_invalid",
      "The commit plan does not use the canonical staged contract."
    )
  }
  commit_candidate_plan(store, batch, staged, plan, started, finalize)
}

empty_plan_changes <- function() {
  data.frame(
    class = character(),
    input_row = integer(),
    record_id = character(),
    action = character(),
    disposition = character(),
    changed_fields = character(),
    expected_revision_id = character(),
    expected_revision_number = numeric(),
    expected_content_digest = character(),
    proposed_content_digest = character(),
    identity_reason = character(),
    identity_evidence = character(),
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
