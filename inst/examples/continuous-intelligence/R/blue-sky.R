blue_sky_result_builder <- function(
  referral,
  accepted_context,
  accepted_evidence
) {
  accepted_ids <- vapply(
    accepted_context$claims,
    `[[`,
    character(1),
    "id"
  )
  required <- c(
    "graft:00000000000000000000000106",
    "graft:00000000000000000000000115",
    "graft:00000000000000000000000118",
    "graft:00000000000000000000000119"
  )
  if (!all(required %in% accepted_ids)) {
    stop(
      paste(
        "The promoted referral requires the accepted baseline, supplier,",
        "and independent observations."
      )
    )
  }
  accepted_claims <- stats::setNames(
    accepted_context$claims,
    accepted_ids
  )
  accepted_record_ids <- vapply(
    accepted_context$records,
    `[[`,
    character(1),
    "id"
  )
  accepted_records <- stats::setNames(
    accepted_context$records,
    accepted_record_ids
  )
  torque_requirement <- accepted_records[[
    "graft:00000000000000000000000102"
  ]]
  duty_requirement <- accepted_records[[
    "graft:00000000000000000000000103"
  ]]
  if (
    !identical(torque_requirement$class, "ProjectRequirement") ||
      !identical(duty_requirement$class, "ProjectRequirement")
  ) {
    stop("The Project Ember requirements are not accepted records.")
  }
  torque_threshold <- as.numeric(torque_requirement$record$threshold)
  torque_unit <- as.character(torque_requirement$record$unit)
  duty_threshold <- as.numeric(duty_requirement$record$threshold)
  duty_unit <- as.character(duty_requirement$record$unit)
  prior_assessment <- accepted_claims[[
    "graft:00000000000000000000000106"
  ]]
  prior_decision <- accepted_claims[[
    "graft:00000000000000000000000107"
  ]]
  if (
    !identical(prior_assessment$class, "Assessment") ||
      !identical(prior_assessment$record$status, "active") ||
      !identical(prior_decision$class, "ReviewDecision") ||
      !identical(prior_decision$record$status, "active")
  ) {
    stop("The prior Blue-Sky decision is no longer active.")
  }
  supersession_preconditions <- list(
    list(
      class = prior_assessment$class,
      id = prior_assessment$id,
      record_digest = prior_assessment$record_digest,
      superseded_by = "graft:00000000000000000000000122",
      valid_to = "2026-07-15T14:00:00Z"
    ),
    list(
      class = prior_decision$class,
      id = prior_decision$id,
      record_digest = prior_decision$record_digest,
      superseded_by = "graft:00000000000000000000000123",
      valid_to = "2026-07-15T14:30:00Z"
    )
  )
  required_evidence_claim_ids <- c(
    "graft:00000000000000000000000118",
    "graft:00000000000000000000000119"
  )
  supporting_evidence <- Filter(
    function(evidence) {
      identical(evidence$record$support_type, "supports") &&
        evidence$record$statement_id %in% required_evidence_claim_ids
    },
    accepted_evidence
  )
  supported_claim_ids <- vapply(
    supporting_evidence,
    \(evidence) evidence$record$statement_id,
    character(1)
  )
  if (!all(required_evidence_claim_ids %in% supported_claim_ids)) {
    stop(
      paste(
        "The promoted referral requires cited supporting evidence for",
        "both independent observations."
      )
    )
  }
  source_matches <- vapply(
    supporting_evidence,
    function(evidence) {
      is.list(evidence$source) &&
        identical(
          evidence$source$id,
          evidence$record$source_id
        ) &&
        identical(
          evidence$source$record$content_hash,
          evidence$record$source_content_hash
        )
    },
    logical(1)
  )
  if (!all(source_matches)) {
    stop(
      paste(
        "The promoted referral evidence does not match its accepted",
        "source provenance."
      )
    )
  }
  source_ids <- vapply(
    supporting_evidence,
    \(evidence) evidence$source$id,
    character(1)
  )
  source_hashes <- vapply(
    supporting_evidence,
    \(evidence) evidence$source$record$content_hash,
    character(1)
  )
  if (
    length(unique(source_ids)) != 1L ||
      length(unique(source_hashes)) != 1L
  ) {
    stop(
      paste(
        "The bounded-test synthesis requires one accepted source",
        "provenance."
      )
    )
  }
  decision_source_id <- unname(source_ids[[1L]])
  decision_source_hash <- unname(source_hashes[[1L]])
  supporting_evidence_ids <- unname(
    vapply(
      supporting_evidence,
      \(evidence) evidence$id,
      character(1)
    )
  )
  relied_claims <- unname(accepted_claims[c(
    "graft:00000000000000000000000115",
    "graft:00000000000000000000000118",
    "graft:00000000000000000000000119"
  )])
  supporting_sources <- lapply(
    unname(supporting_evidence),
    `[[`,
    "source"
  )
  supporting_sources <- supporting_sources[
    !duplicated(vapply(
      supporting_sources,
      `[[`,
      character(1),
      "id"
    ))
  ]
  knowledge_preconditions <- c(
    lapply(
      list(torque_requirement, duty_requirement),
      ci_record_precondition
    ),
    lapply(
      relied_claims,
      ci_record_precondition,
      expected_status = "active"
    ),
    lapply(
      unname(supporting_evidence),
      ci_record_precondition
    ),
    lapply(
      supporting_sources,
      ci_record_precondition
    )
  )
  list(
    workflow_id = referral$workflow_id,
    decision = paste(
      "Should Project Ember authorize a bounded",
      duty_threshold,
      duty_unit,
      "bench test of the Nova compact actuator?"
    ),
    prior_position = paste(
      "Hold the prototype gate until comparable independent evidence",
      "is available."
    ),
    why_now = paste(
      "Independent testing supports the torque requirement and exposes",
      "a testable duty-cycle limitation."
    ),
    options = list(
      list(
        option = "Continue to hold",
        consequence = "Avoid test cost but leave the duty-cycle question open."
      ),
      list(
        option = "Run a bounded bench test",
        consequence = paste(
          "Test the representative twelve-minute cycle without",
          "authorizing deployment."
        )
      ),
      list(
        option = "Proceed toward deployment",
        consequence = "Exceeds the current evidence and is not recommended."
      )
    ),
    recommendation = paste(
      "Authorize a bounded",
      duty_threshold,
      duty_unit,
      "bench test that must sustain at least",
      torque_threshold,
      torque_unit,
      "under Project Ember's representative thermal conditions."
    ),
    uncertainty = paste(
      "Independent evidence stops at ten minutes; thermal behavior during",
      "the final two minutes remains unresolved."
    ),
    owner = "Project Ember test lead",
    next_step = paste(
      "Publish the bench protocol and acceptance criteria before",
      "procuring test hardware."
    ),
    evidence_record_ids = supporting_evidence_ids,
    accepted_claim_ids = accepted_ids,
    knowledge_preconditions = knowledge_preconditions,
    supersession_preconditions = supersession_preconditions,
    new_record_ids = c(
      "graft:00000000000000000000000122",
      "graft:00000000000000000000000123",
      "graft:00000000000000000000000124",
      "graft:00000000000000000000000125"
    ),
    knowledge_changes = list(
      Assessment = list(
        list(
          id = "graft:00000000000000000000000122",
          statement_text = paste(
            "Accepted evidence supports a bounded Project Ember bench test",
            "but does not support deployment."
          ),
          primary_subject = "graft:00000000000000000000000101",
          about = c(
            "graft:00000000000000000000000101",
            "graft:00000000000000000000000104",
            "graft:00000000000000000000000102",
            "graft:00000000000000000000000103"
          ),
          disposition = "prototype",
          decision_confidence = 0.86,
          polarity = "positive",
          confidence = 0.86,
          status = "active",
          asserted_at = "2026-07-15T14:00:00Z"
        )
      ),
      ReviewDecision = list(
        list(
          id = "graft:00000000000000000000000123",
          statement_text = paste(
            "Authorize a bounded twelve-minute Project Ember actuator bench",
            "test; do not authorize deployment."
          ),
          primary_subject = "graft:00000000000000000000000101",
          about = c(
            "graft:00000000000000000000000101",
            "graft:00000000000000000000000104",
            "graft:00000000000000000000000102",
            "graft:00000000000000000000000103"
          ),
          disposition = "prototype",
          reviewer_role = "technology portfolio owner",
          polarity = "positive",
          confidence = 1,
          status = "active",
          asserted_at = "2026-07-15T14:30:00Z"
        )
      ),
      Evidence = list(
        list(
          id = "graft:00000000000000000000000124",
          statement_id = "graft:00000000000000000000000122",
          source_id = decision_source_id,
          support_type = "derived_from",
          locator_type = "other",
          locator_value = "table 2",
          excerpt = paste(
            "At 24 V, sustained torque was 105 Nm through minute ten."
          ),
          source_content_hash = decision_source_hash,
          extraction_method = "workflow-selected-source-evidence",
          extraction_version = "1"
        ),
        list(
          id = "graft:00000000000000000000000125",
          statement_id = "graft:00000000000000000000000123",
          source_id = decision_source_id,
          support_type = "derived_from",
          locator_type = "other",
          locator_value = "Thermal behavior",
          excerpt = paste(
            "Thermal protection reduced output after ten minutes of",
            "continuous operation."
          ),
          source_content_hash = decision_source_hash,
          extraction_method = "workflow-selected-source-evidence",
          extraction_version = "1"
        )
      )
    )
  )
}

blue_sky_decision_record_mapper <- function(content, approval, store) {
  ci_validate_absent_records(
    store,
    content$new_record_ids
  )
  ci_validate_record_preconditions(
    store,
    content$knowledge_preconditions
  )
  records <- ci_rows_to_records(
    content$knowledge_changes,
    store$schema
  )
  records$ReviewDecision$review_outcome <- approval$decision
  records$ReviewDecision$workflow_run_id <-
    content$workflow_lineage$run_id
  records$ReviewDecision$approval_id <- approval$approval_id
  records$ReviewDecision$synthesis_method <-
    content$workflow_lineage$synthesis_method
  for (precondition in content$supersession_preconditions) {
    current <- graft::kg_get(
      store,
      precondition$id,
      include = character()
    )
    first_commit <- identical(current$class, precondition$class) &&
      identical(current$record$status, "active") &&
      identical(
        ci_record_digest(current$record),
        precondition$record_digest
      )
    if (!first_commit) {
      stop(
        paste0(
          "Supersession precondition failed for `",
          precondition$id,
          "`; the accepted decision changed before commit."
        )
      )
    }
    superseded <- ci_plain_record(current$record)
    superseded$status <- "superseded"
    superseded$superseded_by <- precondition$superseded_by
    superseded$valid_to <- precondition$valid_to
    update <- ci_rows_to_records(
      stats::setNames(
        list(list(superseded)),
        precondition$class
      ),
      store$schema
    )
    records[[precondition$class]] <- dplyr::bind_rows(
      update[[precondition$class]],
      records[[precondition$class]]
    )
  }
  records
}
