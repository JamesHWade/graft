test_that("continuous-intelligence host stays domain neutral", {
  environment <- local_continuous_intelligence_environment()
  blue_sky <- environment$ci_read_json(
    continuous_intelligence_example_path(
      "profiles",
      "blue-sky.json"
    )
  )
  maintainer <- environment$ci_read_json(
    continuous_intelligence_example_path(
      "profiles",
      "package-maintainer.json"
    )
  )
  host <- readLines(
    continuous_intelligence_example_path("R", "host.R"),
    warn = FALSE
  )

  expect_identical(names(blue_sky), names(maintainer))
  expect_identical(
    vapply(
      blue_sky$briefing_sections,
      `[[`,
      character(1),
      "field"
    ),
    vapply(
      maintainer$briefing_sections,
      `[[`,
      character(1),
      "field"
    )
  )
  expect_length(
    grep(
      "Project Ember|actuator|package maintainer",
      host,
      ignore.case = TRUE
    ),
    0L
  )
  expect_length(
    blue_sky$routing_policy$allowed_workflow_ids,
    1L
  )
  expect_length(
    maintainer$routing_policy$allowed_workflow_ids,
    2L
  )
})

test_that("staged walkthrough console gates require explicit decisions", {
  environment <- new.env(parent = globalenv())
  sys.source(
    continuous_intelligence_example_path("walkthrough.R"),
    envir = environment
  )

  approved <- environment$ci_walkthrough_console_gate(
    "knowledge",
    "approve",
    "Knowledge boundary",
    "Candidate records remain outside Graft.",
    read_input = \(prompt) " approve "
  )
  stopped <- environment$ci_walkthrough_console_gate(
    "promotion",
    "promote",
    "Promotion boundary",
    "The referral remains inactive.",
    read_input = \(prompt) "stop"
  )

  expect_identical(approved, TRUE)
  expect_identical(stopped, FALSE)
})

test_that("staged walkthrough exercises each operator boundary", {
  if (!continuous_intelligence_tempest_available()) {
    testthat::skip(
      "A compatible current Tempest workflow runtime is unavailable."
    )
  }
  environment <- new.env(parent = globalenv())
  sys.source(
    continuous_intelligence_example_path("walkthrough.R"),
    envir = environment
  )
  events <- new.env(parent = emptyenv())
  events$stages <- character()
  events$actions <- character()
  approve_all <- function(stage, action, ...) {
    events$stages <- c(events$stages, stage)
    events$actions <- c(events$actions, action)
    TRUE
  }
  stop_at_supplier_knowledge <- function(stage, ...) {
    !identical(stage, "supplier-knowledge")
  }

  result <- environment$run_continuous_intelligence_walkthrough(
    example_dir = continuous_intelligence_example_path(),
    gate = approve_all
  )
  stopped_result <- environment$run_continuous_intelligence_walkthrough(
    example_dir = continuous_intelligence_example_path(),
    gate = stop_at_supplier_knowledge
  )

  expect_identical(
    events$stages,
    c(
      "welcome",
      "supplier-briefing",
      "supplier-knowledge",
      "independent-briefing",
      "independent-knowledge",
      "workflow-promotion",
      "decision-approval",
      "no-change-briefing"
    )
  )
  expect_identical(
    events$actions,
    c(
      "continue",
      "continue",
      "approve",
      "continue",
      "approve",
      "promote",
      "approve",
      "continue"
    )
  )
  expect_identical(result$status, "completed")
  expect_null(result$stopped_at)
  expect_length(result$monitor_runs, 3L)
  expect_length(result$review_runs, 2L)
  expect_length(result$ingests, 3L)
  expect_identical(
    result$promotion_record$decision,
    "approved"
  )
  expect_equal(result$assessment_count, 2L)
  expect_equal(result$decision_count, 2L)
  expect_identical(stopped_result$status, "stopped")
  expect_identical(
    stopped_result$stopped_at,
    "supplier-knowledge"
  )
  expect_length(stopped_result$ingests, 0L)
  expect_identical(stopped_result$assessment_count, 1L)
  expect_identical(stopped_result$decision_count, 1L)
  expect_identical(
    tempest::tempest_run_status(stopped_result$review_runs[[1L]]),
    "awaiting_approval"
  )
})

test_that("scheduled signals promote through approval into accepted history", {
  if (!continuous_intelligence_tempest_available()) {
    testthat::skip(
      "A compatible current Tempest workflow runtime is unavailable."
    )
  }
  environment <- local_continuous_intelligence_environment()
  profile <- environment$ci_read_json(
    continuous_intelligence_example_path(
      "profiles",
      "blue-sky.json"
    )
  )
  store <- local_continuous_intelligence_store(environment)
  missing_context <- tryCatch(
    environment$ci_accepted_context(
      store,
      "graft:00000000000000000000000999"
    ),
    graft_error = identity
  )
  expect_s3_class(missing_context, "graft_error")
  expect_match(
    conditionMessage(missing_context),
    "was not found"
  )
  single_about <- environment$ci_rows_to_records(
    list(
      Observation = list(list(
        id = "graft:00000000000000000000000199",
        statement_text = "One technology remains in the monitored scope.",
        primary_subject = "graft:00000000000000000000000104",
        about = c("graft:00000000000000000000000104"),
        finding_kind = "capability",
        source_quality = "vendor",
        extraction_confidence = 0.9,
        polarity = "positive",
        confidence = 0.9,
        status = "active",
        asserted_at = "2026-07-14T08:00:00Z"
      ))
    ),
    store$schema
  )
  expect_type(single_about$Observation$about, "list")
  expect_identical(
    single_about$Observation$about[[1L]],
    "graft:00000000000000000000000104"
  )
  expect_identical(kg_validate_data(store, single_about)$valid, TRUE)

  day_one <- continuous_intelligence_run_signal_day(
    environment,
    profile,
    store,
    "2026-07-14",
    "2026-07-14-supplier.json"
  )
  expect_identical(
    tempest::tempest_run_status(day_one$monitor),
    "succeeded"
  )
  expect_identical(
    tempest::tempest_run_status(day_one$review),
    "awaiting_approval"
  )
  day_one_monitor_content <- tempest::tempest_run_artifact(
    day_one$monitor,
    "monitor-result-json"
  )@content
  expect_setequal(
    vapply(
      day_one_monitor_content$proposal_target_preconditions,
      `[[`,
      character(1),
      "id"
    ),
    c(
      "graft:00000000000000000000000113",
      "graft:00000000000000000000000114",
      "graft:00000000000000000000000115",
      "graft:00000000000000000000000116"
    )
  )
  expect_equal(
    nrow(dplyr::collect(kg_records(store, "Observation"))),
    0L
  )
  mismatched_review <- tryCatch(
    environment$ci_run_knowledge_review(
      day_one$monitor,
      "not-the-monitor-run",
      "blue-sky-review-mismatch",
      store
    ),
    error = identity
  )
  expect_s3_class(mismatched_review, "error")
  expect_match(
    conditionMessage(mismatched_review),
    "does not match the monitor artifact provenance"
  )
  review_content <- tempest::tempest_run_artifact(
    day_one$review,
    "knowledge-change-set-json"
  )@content
  expect_identical(
    review_content$source_monitor_run_id,
    tempest::tempest_run_artifact(
      day_one$monitor,
      "monitor-result-json"
    )@run_id
  )
  review_target_ids <- vapply(
    review_content$target_preconditions,
    `[[`,
    character(1),
    "id"
  )
  expect_setequal(
    review_target_ids,
    c(
      "graft:00000000000000000000000113",
      "graft:00000000000000000000000114",
      "graft:00000000000000000000000115",
      "graft:00000000000000000000000116"
    )
  )
  expect_setequal(
    vapply(
      review_content$target_preconditions,
      `[[`,
      character(1),
      "expected_state"
    ),
    "absent"
  )
  context_precondition_ids <- vapply(
    review_content$context_preconditions,
    `[[`,
    character(1),
    "id"
  )
  expect_in(
    "graft:00000000000000000000000102",
    context_precondition_ids
  )
  expect_in(
    "graft:00000000000000000000000103",
    context_precondition_ids
  )
  expect_in(
    "graft:00000000000000000000000106",
    context_precondition_ids
  )
  mismatched_commit <- tryCatch(
    environment$ci_approve_and_commit(
      day_one$review,
      "knowledge-change-set-json",
      store,
      "not-the-review-run",
      "Should not approve or commit."
    ),
    error = identity
  )
  expect_s3_class(mismatched_commit, "error")
  expect_match(
    conditionMessage(mismatched_commit),
    "does not match the approved artifact provenance"
  )
  expect_identical(
    tempest::tempest_run_artifact(
      day_one$review,
      "knowledge-change-set-json"
    )@status,
    "awaiting_approval"
  )
  interstitial_store <- local_continuous_intelligence_store(environment)
  interstitial_bundle <- environment$ci_read_json(
    continuous_intelligence_example_path(
      "corpus",
      "2026-07-14-supplier.json"
    )
  )
  interstitial_monitor <- environment$ci_run_monitor(
    profile,
    interstitial_bundle,
    interstitial_store,
    "blue-sky-monitor-interstitial-conflict"
  )
  interstitial_source <- interstitial_bundle$proposals$Source[[1L]]
  interstitial_source$title <- paste(
    interstitial_source$title,
    "accepted after monitoring"
  )
  kg_ingest(
    interstitial_store,
    kg_batch(
      "continuous-intelligence-test",
      idempotency_key = "monitor-review-target-conflict"
    ),
    environment$ci_rows_to_records(
      list(Source = list(interstitial_source)),
      interstitial_store$schema
    )
  )
  interstitial_review <- tryCatch(
    environment$ci_run_knowledge_review(
      interstitial_monitor,
      "blue-sky-monitor-interstitial-conflict",
      "blue-sky-review-interstitial-conflict",
      interstitial_store
    ),
    error = identity
  )
  expect_s3_class(interstitial_review, "error")
  expect_match(
    conditionMessage(interstitial_review),
    "proposal target changed before commit"
  )
  conflict_store <- local_continuous_intelligence_store(environment)
  conflict_day <- continuous_intelligence_run_signal_day(
    environment,
    profile,
    conflict_store,
    "2026-07-14-conflict",
    "2026-07-14-supplier.json"
  )
  conflicting_source <- tempest::tempest_run_artifact(
    conflict_day$review,
    "knowledge-change-set-json"
  )@content$knowledge_changes$Source[[1L]]
  conflicting_source$title <- paste(
    conflicting_source$title,
    "with a newer accepted revision"
  )
  kg_ingest(
    conflict_store,
    kg_batch(
      "continuous-intelligence-test",
      idempotency_key = "proposal-target-conflict"
    ),
    environment$ci_rows_to_records(
      list(Source = list(conflicting_source)),
      conflict_store$schema
    )
  )
  conflict_commit <- tryCatch(
    environment$ci_approve_and_commit(
      conflict_day$review,
      "knowledge-change-set-json",
      conflict_store,
      conflict_day$review_id,
      "This approval must not overwrite newer accepted knowledge."
    ),
    error = identity
  )
  expect_s3_class(conflict_commit, "error")
  expect_match(
    conditionMessage(conflict_commit),
    "proposal target changed before commit"
  )
  expect_match(
    kg_get(
      conflict_store,
      "graft:00000000000000000000000114",
      include = character()
    )$record$title,
    "newer accepted revision"
  )
  context_store <- local_continuous_intelligence_store(environment)
  context_content <- review_content
  context_content$context_preconditions <-
    environment$ci_accepted_context_preconditions(
      environment$ci_accepted_context(
        context_store,
        environment$ci_character(
          profile$monitor_scope$record_ids
        )
      )
    )
  changed_requirement <- kg_get(
    context_store,
    "graft:00000000000000000000000102",
    include = character()
  )$record
  changed_requirement$threshold <- 101
  kg_ingest(
    context_store,
    kg_batch(
      "continuous-intelligence-test",
      idempotency_key = "review-context-conflict"
    ),
    environment$ci_rows_to_records(
      list(ProjectRequirement = list(changed_requirement)),
      context_store$schema
    )
  )
  context_mapping <- tryCatch(
    environment$ci_default_record_mapper(
      context_content,
      list(decision = "approved"),
      context_store
    ),
    error = identity
  )
  expect_s3_class(context_mapping, "error")
  expect_match(
    conditionMessage(context_mapping),
    "relied-upon knowledge changed before commit"
  )
  mapping_failure <- tryCatch(
    environment$ci_approve_and_commit(
      day_one$review,
      "knowledge-change-set-json",
      store,
      day_one$review_id,
      "Approved source-faithful vendor observation.",
      record_mapper = \(
        ...
      ) {
        stop("Synthetic mapping failure.")
      }
    ),
    error = identity
  )
  expect_s3_class(mapping_failure, "error")
  expect_match(
    conditionMessage(mapping_failure),
    "Synthetic mapping failure"
  )
  expect_identical(
    tempest::tempest_run_artifact(
      day_one$review,
      "knowledge-change-set-json"
    )@status,
    "approved"
  )
  expect_equal(
    nrow(dplyr::collect(kg_records(store, "Observation"))),
    0L
  )
  day_one_commit <- environment$ci_approve_and_commit(
    day_one$review,
    "knowledge-change-set-json",
    store,
    day_one$review_id,
    "Approved source-faithful vendor observation."
  )
  expect_identical(
    tempest::tempest_run_status(day_one_commit$run),
    "succeeded"
  )
  expect_equal(
    nrow(dplyr::collect(kg_records(store, "Observation"))),
    1L
  )
  expect_identical(day_one_commit$ingest$replay, FALSE)
  independent_bundle <- environment$ci_read_json(
    continuous_intelligence_example_path(
      "corpus",
      "2026-07-15-independent.json"
    )
  )
  premature_context <- environment$ci_accepted_context(
    store,
    environment$ci_character(
      profile$monitor_scope$record_ids
    )
  )
  premature_referral <- tryCatch(
    environment$blue_sky_result_builder(
      independent_bundle$referrals[[1L]],
      premature_context,
      list()
    ),
    error = identity
  )
  expect_s3_class(premature_referral, "error")
  expect_match(
    conditionMessage(premature_referral),
    "requires the accepted baseline"
  )

  day_two <- continuous_intelligence_run_signal_day(
    environment,
    profile,
    store,
    "2026-07-15",
    "2026-07-15-independent.json"
  )
  day_two_commit <- environment$ci_approve_and_commit(
    day_two$review,
    "knowledge-change-set-json",
    store,
    day_two$review_id,
    "Approved source-faithful independent observations."
  )
  expect_identical(
    tempest::tempest_run_status(day_two_commit$run),
    "succeeded"
  )
  expect_identical(day_two_commit$ingest$replay, FALSE)
  knowledge_batches <- DBI::dbReadTable(
    store$connection,
    "_graft_batches"
  )
  knowledge_batches <- knowledge_batches[
    knowledge_batches$source_run_id %in%
      c(
        day_one$review_id,
        day_two$review_id
      ),
    ,
    drop = FALSE
  ]
  expect_setequal(
    knowledge_batches$idempotency_key,
    c(
      paste0(
        day_one$review_id,
        ":",
        environment$ci_artifact_ingest_stage(
          "knowledge-change-set-json",
          day_one_commit$artifact,
          day_one_commit$approval
        )
      ),
      paste0(
        day_two$review_id,
        ":",
        environment$ci_artifact_ingest_stage(
          "knowledge-change-set-json",
          day_two_commit$artifact,
          day_two_commit$approval
        )
      )
    )
  )
  monitor_content <- tempest::tempest_run_artifact(
    day_two$monitor,
    "monitor-result-json"
  )@content
  expect_length(monitor_content$referrals, 1L)

  referral <- monitor_content$referrals[[1L]]
  accepted_context <- environment$ci_accepted_context(
    store,
    environment$ci_character(referral$context_record_ids)
  )
  accepted_evidence <- environment$ci_accepted_evidence(
    store,
    referral$evidence_record_ids,
    accepted_context
  )
  independent_ids <- vapply(
    accepted_context$claims,
    `[[`,
    character(1),
    "id"
  )
  torque_index <- which(
    independent_ids == "graft:00000000000000000000000118"
  )
  thermal_index <- which(
    independent_ids == "graft:00000000000000000000000119"
  )
  prior_decision_index <- which(
    independent_ids == "graft:00000000000000000000000107"
  )
  accepted_record_ids <- vapply(
    accepted_context$records,
    `[[`,
    character(1),
    "id"
  )
  torque_requirement_index <- which(
    accepted_record_ids == "graft:00000000000000000000000102"
  )
  insufficient_context <- accepted_context
  insufficient_context$claims[[
    torque_index
  ]]$record$observed_torque <- 95
  insufficient_result <- tryCatch(
    environment$blue_sky_result_builder(
      referral,
      insufficient_context,
      accepted_evidence
    ),
    error = identity
  )
  expect_s3_class(insufficient_result, "error")
  expect_match(
    conditionMessage(insufficient_result),
    "does not meet the Project Ember torque requirement"
  )
  vendor_context <- accepted_context
  vendor_context$claims[[
    torque_index
  ]]$record$source_quality <- "vendor"
  vendor_result <- tryCatch(
    environment$blue_sky_result_builder(
      referral,
      vendor_context,
      accepted_evidence
    ),
    error = identity
  )
  expect_s3_class(vendor_result, "error")
  expect_match(
    conditionMessage(vendor_result),
    "requires an independent positive"
  )
  contradictory_context <- accepted_context
  contradictory_context$claims[[
    thermal_index
  ]]$record$finding_kind <- "capability"
  contradictory_context$claims[[
    thermal_index
  ]]$record$polarity <- "positive"
  contradictory_result <- tryCatch(
    environment$blue_sky_result_builder(
      referral,
      contradictory_context,
      accepted_evidence
    ),
    error = identity
  )
  expect_s3_class(contradictory_result, "error")
  expect_match(
    conditionMessage(contradictory_result),
    "independent negative limitation"
  )
  zero_duration_context <- accepted_context
  zero_duration_context$claims[[
    torque_index
  ]]$record$observed_duration <- 0
  zero_duration_result <- tryCatch(
    environment$blue_sky_result_builder(
      referral,
      zero_duration_context,
      accepted_evidence
    ),
    error = identity
  )
  expect_s3_class(zero_duration_result, "error")
  expect_match(
    conditionMessage(zero_duration_result),
    "test duration must be strictly positive"
  )
  negative_duration_context <- accepted_context
  negative_duration_context$claims[[
    thermal_index
  ]]$record$observed_duration <- -1
  negative_duration_result <- tryCatch(
    environment$blue_sky_result_builder(
      referral,
      negative_duration_context,
      accepted_evidence
    ),
    error = identity
  )
  expect_s3_class(negative_duration_result, "error")
  expect_match(
    conditionMessage(negative_duration_result),
    "test duration must be strictly positive"
  )
  vendor_evidence <- accepted_evidence
  vendor_evidence[[1L]]$source$record$source_quality <- "vendor"
  vendor_source_result <- tryCatch(
    environment$blue_sky_result_builder(
      referral,
      accepted_context,
      vendor_evidence
    ),
    error = identity
  )
  expect_s3_class(vendor_source_result, "error")
  expect_match(
    conditionMessage(vendor_source_result),
    "does not match its accepted source provenance"
  )
  mismatched_observation_context <- accepted_context
  mismatched_observation_context$claims[[
    torque_index
  ]]$record$primary_subject <- "graft:00000000000000000000000101"
  mismatched_observation_result <- tryCatch(
    environment$blue_sky_result_builder(
      referral,
      mismatched_observation_context,
      accepted_evidence
    ),
    error = identity
  )
  expect_s3_class(mismatched_observation_result, "error")
  expect_match(
    conditionMessage(mismatched_observation_result),
    "do not match the Project Ember and Nova relationship graph"
  )
  mismatched_requirement_context <- accepted_context
  mismatched_requirement_context$records[[
    torque_requirement_index
  ]]$record$project <- "graft:00000000000000000000000104"
  mismatched_requirement_result <- tryCatch(
    environment$blue_sky_result_builder(
      referral,
      mismatched_requirement_context,
      accepted_evidence
    ),
    error = identity
  )
  expect_s3_class(mismatched_requirement_result, "error")
  expect_match(
    conditionMessage(mismatched_requirement_result),
    "do not match the Project Ember and Nova relationship graph"
  )
  changed_prior_context <- accepted_context
  changed_prior_context$claims[[
    prior_decision_index
  ]]$record$disposition <- "proceed"
  changed_prior_result <- tryCatch(
    environment$blue_sky_result_builder(
      referral,
      changed_prior_context,
      accepted_evidence
    ),
    error = identity
  )
  expect_s3_class(changed_prior_result, "error")
  expect_match(
    conditionMessage(changed_prior_result),
    "prior Blue-Sky hold is no longer active"
  )
  promotion_store <- environment$ci_promotion_store()
  promotion_id <- environment$ci_record_promotion(
    promotion_store,
    "blue-sky:promotion:prototype-gate:2026-07-15",
    referral,
    reviewer = "technology portfolio owner",
    decided_at = "2026-07-15T13:30:00Z",
    note = "Open the prototype-gate decision workflow."
  )
  promotion <- promotion_store$records[[promotion_id]]
  missing_evidence_referral <- referral
  missing_evidence_referral$evidence_record_ids <- c(
    "graft:00000000000000000000000999"
  )
  missing_promotion_id <- environment$ci_record_promotion(
    promotion_store,
    "blue-sky:promotion:missing-evidence",
    missing_evidence_referral,
    reviewer = "technology portfolio owner",
    decided_at = "2026-07-15T13:31:00Z"
  )
  missing_evidence <- tryCatch(
    environment$ci_run_referral(
      missing_evidence_referral,
      profile,
      store,
      environment$blue_sky_result_builder,
      "blue-sky-decision-missing-evidence",
      promotion_store = promotion_store,
      promotion_id = missing_promotion_id
    ),
    graft_error = identity
  )
  expect_s3_class(missing_evidence, "graft_error")
  expect_match(conditionMessage(missing_evidence), "was not found")
  unrelated_evidence_referral <- referral
  unrelated_evidence_referral$context_record_ids <- c(
    "graft:00000000000000000000000102"
  )
  unrelated_evidence_referral$evidence_record_ids <- c(
    "graft:00000000000000000000000121"
  )
  unrelated_evidence_promotion_id <- environment$ci_record_promotion(
    promotion_store,
    "blue-sky:promotion:unrelated-evidence",
    unrelated_evidence_referral,
    reviewer = "technology portfolio owner",
    decided_at = "2026-07-15T13:32:00Z"
  )
  unrelated_evidence <- tryCatch(
    environment$ci_run_referral(
      unrelated_evidence_referral,
      profile,
      store,
      environment$blue_sky_result_builder,
      "blue-sky-decision-unrelated-evidence",
      promotion_store = promotion_store,
      promotion_id = unrelated_evidence_promotion_id
    ),
    error = identity
  )
  expect_s3_class(unrelated_evidence, "error")
  expect_match(
    conditionMessage(unrelated_evidence),
    "is not attached to an accepted claim"
  )
  irrelevant_evidence_referral <- referral
  irrelevant_evidence_referral$evidence_record_ids <- c(
    "graft:00000000000000000000000108",
    "graft:00000000000000000000000109"
  )
  irrelevant_evidence_promotion_id <- environment$ci_record_promotion(
    promotion_store,
    "blue-sky:promotion:irrelevant-evidence",
    irrelevant_evidence_referral,
    reviewer = "technology portfolio owner",
    decided_at = "2026-07-15T13:33:00Z"
  )
  irrelevant_evidence <- tryCatch(
    environment$ci_run_referral(
      irrelevant_evidence_referral,
      profile,
      store,
      environment$blue_sky_result_builder,
      "blue-sky-decision-irrelevant-evidence",
      promotion_store = promotion_store,
      promotion_id = irrelevant_evidence_promotion_id
    ),
    error = identity
  )
  expect_s3_class(irrelevant_evidence, "tempest_step_execution_error")
  expect_match(
    conditionMessage(irrelevant_evidence),
    "requires cited supporting evidence"
  )
  unpromoted <- tryCatch(
    environment$ci_run_referral(
      referral,
      profile,
      store,
      environment$blue_sky_result_builder,
      "blue-sky-decision-2026-07-15"
    ),
    error = identity
  )
  expect_s3_class(unpromoted, "error")
  expect_match(
    conditionMessage(unpromoted),
    "requires an approved human-promotion"
  )
  fabricated_promotion <- tryCatch(
    environment$ci_run_referral(
      referral,
      profile,
      store,
      environment$blue_sky_result_builder,
      "blue-sky-decision-fabricated-promotion",
      promotion_store = promotion_store,
      promotion_id = "blue-sky:promotion:not-recorded"
    ),
    error = identity
  )
  expect_s3_class(fabricated_promotion, "error")
  expect_match(
    conditionMessage(fabricated_promotion),
    "was not found"
  )
  cross_referral <- referral
  cross_referral$referral_id <- "blue-sky:referral:other"
  unrelated_promotion <- tryCatch(
    environment$ci_run_referral(
      cross_referral,
      profile,
      store,
      environment$blue_sky_result_builder,
      "blue-sky-decision-unrelated-promotion",
      promotion_store = promotion_store,
      promotion_id = promotion_id
    ),
    error = identity
  )
  expect_s3_class(unrelated_promotion, "error")
  expect_match(
    conditionMessage(unrelated_promotion),
    "does not match the approved"
  )
  changed_referral <- referral
  changed_referral$objective <- paste(
    changed_referral$objective,
    "Authorize deployment as well."
  )
  changed_promotion <- tryCatch(
    environment$ci_run_referral(
      changed_referral,
      profile,
      store,
      environment$blue_sky_result_builder,
      "blue-sky-decision-changed-referral",
      promotion_store = promotion_store,
      promotion_id = promotion_id
    ),
    error = identity
  )
  expect_s3_class(changed_promotion, "error")
  expect_match(
    conditionMessage(changed_promotion),
    "does not match the approved"
  )
  decision <- environment$ci_run_referral(
    referral,
    profile,
    store,
    environment$blue_sky_result_builder,
    "blue-sky-decision-2026-07-15",
    promotion_store = promotion_store,
    promotion_id = promotion_id
  )
  expect_identical(
    tempest::tempest_run_status(decision),
    "awaiting_approval"
  )
  expect_identical(
    tempest::tempest_run_artifact(
      decision,
      "workflow-referral-result-json"
    )@content$promotion,
    promotion
  )
  expect_identical(
    tempest::tempest_run_artifact(
      decision,
      "workflow-referral-result-json"
    )@content$workflow_lineage$run_id,
    "blue-sky-decision-2026-07-15"
  )
  expect_setequal(
    tempest::tempest_run_artifact(
      decision,
      "workflow-referral-result-json"
    )@content$evidence_record_ids,
    c(
      "graft:00000000000000000000000120",
      "graft:00000000000000000000000121"
    )
  )
  decision_content <- tempest::tempest_run_artifact(
    decision,
    "workflow-referral-result-json"
  )@content
  knowledge_precondition_ids <- vapply(
    decision_content$knowledge_preconditions,
    `[[`,
    character(1),
    "id"
  )
  expect_in(
    "graft:00000000000000000000000102",
    knowledge_precondition_ids
  )
  expect_in(
    "graft:00000000000000000000000101",
    knowledge_precondition_ids
  )
  expect_in(
    "graft:00000000000000000000000104",
    knowledge_precondition_ids
  )
  expect_in(
    "graft:00000000000000000000000103",
    knowledge_precondition_ids
  )
  expect_in(
    "graft:00000000000000000000000117",
    knowledge_precondition_ids
  )
  expect_match(decision_content$recommendation, "12 min")
  expect_match(decision_content$recommendation, "100 Nm")
  expect_match(decision_content$uncertainty, "10 min")
  expect_match(decision_content$uncertainty, "final 2 min")
  for (target in list(
    list(
      id = "graft:00000000000000000000000101",
      table = "project"
    ),
    list(
      id = "graft:00000000000000000000000104",
      table = "technology"
    )
  )) {
    DBI::dbBegin(store$connection)
    DBI::dbExecute(
      store$connection,
      paste0(
        "UPDATE ",
        target$table,
        " SET description = description || ' changed after synthesis'",
        " WHERE id = ?"
      ),
      params = list(target$id)
    )
    changed_context_mapping <- tryCatch(
      environment$blue_sky_decision_record_mapper(
        decision_content,
        list(decision = "approved"),
        store
      ),
      error = identity
    )
    DBI::dbRollback(store$connection)
    expect_s3_class(changed_context_mapping, "error")
    expect_match(
      conditionMessage(changed_context_mapping),
      "relied-upon knowledge changed before commit"
    )
  }
  stale_store <- local_continuous_intelligence_store(environment)
  stale_evidence <- kg_get(
    stale_store,
    "graft:00000000000000000000000108",
    include = character()
  )
  evidence_precondition <- environment$ci_record_precondition(
    stale_evidence
  )
  stale_assessment <- kg_get(
    stale_store,
    "graft:00000000000000000000000106",
    include = character()
  )$record
  stale_assessment$decision_confidence <- 0.8
  kg_ingest(
    stale_store,
    kg_batch(
      "continuous-intelligence-test",
      idempotency_key = "stale-prior-decision"
    ),
    environment$ci_rows_to_records(
      list(Assessment = list(stale_assessment)),
      stale_store$schema
    )
  )
  changed_evidence <- stale_evidence$record
  changed_evidence$excerpt <- paste(
    changed_evidence$excerpt,
    "This record changed after workflow execution."
  )
  kg_ingest(
    stale_store,
    kg_batch(
      "continuous-intelligence-test",
      idempotency_key = "stale-evidence"
    ),
    environment$ci_rows_to_records(
      list(Evidence = list(changed_evidence)),
      stale_store$schema
    )
  )
  stale_evidence_condition <- tryCatch(
    environment$ci_validate_record_preconditions(
      stale_store,
      list(evidence_precondition)
    ),
    error = identity
  )
  expect_s3_class(stale_evidence_condition, "error")
  expect_match(
    conditionMessage(stale_evidence_condition),
    "relied-upon knowledge changed before commit"
  )
  stale_content <- tempest::tempest_run_artifact(
    decision,
    "workflow-referral-result-json"
  )@content
  stale_content$knowledge_preconditions <- list()
  stale_mapping <- tryCatch(
    environment$blue_sky_decision_record_mapper(
      stale_content,
      list(decision = "approved"),
      stale_store
    ),
    error = identity
  )
  expect_s3_class(stale_mapping, "error")
  expect_match(
    conditionMessage(stale_mapping),
    "accepted decision changed before commit"
  )
  occupied_content <- stale_content
  occupied_content$knowledge_preconditions <- list()
  occupied_record <- occupied_content$knowledge_changes$Assessment[[1L]]
  occupied_record$statement_text <- "An unrelated assessment owns this ID."
  kg_ingest(
    stale_store,
    kg_batch(
      "continuous-intelligence-test",
      idempotency_key = "occupied-new-record-id"
    ),
    environment$ci_rows_to_records(
      list(Assessment = list(occupied_record)),
      stale_store$schema
    )
  )
  occupied_mapping <- tryCatch(
    environment$blue_sky_decision_record_mapper(
      occupied_content,
      list(decision = "approved"),
      stale_store
    ),
    error = identity
  )
  expect_s3_class(occupied_mapping, "error")
  expect_match(conditionMessage(occupied_mapping), "already exists")
  expect_equal(
    nrow(dplyr::collect(kg_records(store, "ReviewDecision"))),
    1L
  )
  decision_commit <- environment$ci_approve_and_commit(
    decision,
    "workflow-referral-result-json",
    store,
    "blue-sky-decision-2026-07-15",
    "Approved bounded bench test only.",
    record_mapper = environment$blue_sky_decision_record_mapper
  )
  expect_identical(
    tempest::tempest_run_status(decision_commit$run),
    "succeeded"
  )
  expect_equal(
    nrow(dplyr::collect(kg_records(store, "Assessment"))),
    2L
  )
  expect_equal(
    nrow(dplyr::collect(kg_records(store, "ReviewDecision"))),
    2L
  )
  prior_assessment <- kg_get(
    store,
    "graft:00000000000000000000000106",
    include = character()
  )$record
  prior_decision <- kg_get(
    store,
    "graft:00000000000000000000000107",
    include = character()
  )$record
  expect_identical(prior_assessment$status, "superseded")
  expect_identical(
    prior_assessment$superseded_by,
    "graft:00000000000000000000000122"
  )
  expect_identical(prior_decision$status, "superseded")
  expect_identical(
    prior_decision$superseded_by,
    "graft:00000000000000000000000123"
  )
  committed_decision_record <- kg_get(
    store,
    "graft:00000000000000000000000123",
    include = "evidence"
  )
  expect_in(
    "graft:00000000000000000000000125",
    committed_decision_record$evidence$id
  )
  expect_in(
    "graft:00000000000000000000000127",
    committed_decision_record$evidence$id
  )
  committed_decision_evidence <- committed_decision_record$evidence[
    committed_decision_record$evidence$id == "graft:00000000000000000000000125",
    ,
    drop = FALSE
  ]
  expect_identical(
    committed_decision_evidence$source_id,
    "graft:00000000000000000000000117"
  )
  expect_identical(
    committed_decision_evidence$source_content_hash,
    "sha256:independent-test-v1"
  )
  expect_identical(
    committed_decision_evidence$excerpt,
    paste(
      "Thermal protection reduced output after ten minutes of",
      "continuous operation."
    )
  )
  expect_identical(
    committed_decision_evidence$locator_type,
    "section"
  )
  expect_identical(
    committed_decision_record$record$workflow_run_id,
    "blue-sky-decision-2026-07-15"
  )
  expect_identical(
    committed_decision_record$record$approval_id,
    decision_commit$approval$approval_id
  )
  expect_identical(
    committed_decision_record$record$synthesis_method,
    "approved-workflow-synthesis"
  )

  day_three <- environment$ci_run_monitor(
    profile,
    environment$ci_read_json(
      continuous_intelligence_example_path(
        "corpus",
        "2026-07-16-no-change.json"
      )
    ),
    store,
    "blue-sky-monitor-2026-07-16"
  )
  day_three_content <- tempest::tempest_run_artifact(
    day_three,
    "monitor-result-json"
  )@content
  day_three_brief <- tempest::tempest_run_artifact(
    day_three,
    "daily-briefing-md"
  )@content
  expect_identical(
    tempest::tempest_run_status(day_three),
    "succeeded"
  )
  expect_identical(day_three_content$proposal_count, 0L)
  expect_length(
    tempest::tempest_run_approvals(day_three, status = "pending"),
    0L
  )
  expect_match(day_three_brief, "No material change")
  accepted_claim_ids <- vapply(
    day_three_content$accepted_context$claims,
    `[[`,
    character(1),
    "id"
  )
  expect_in(
    "graft:00000000000000000000000122",
    accepted_claim_ids
  )
  expect_in(
    "graft:00000000000000000000000123",
    accepted_claim_ids
  )
  expect_length(
    intersect(
      c(
        "graft:00000000000000000000000106",
        "graft:00000000000000000000000107"
      ),
      accepted_claim_ids
    ),
    0L
  )

  changed_observation <- kg_get(
    store,
    "graft:00000000000000000000000118",
    include = character()
  )$record
  changed_observation$confidence <- 0.89
  kg_ingest(
    store,
    kg_batch(
      "continuous-intelligence-test",
      idempotency_key = "post-decision-observation-update"
    ),
    environment$ci_rows_to_records(
      list(Observation = list(changed_observation)),
      store$schema
    )
  )
  replay_condition <- NULL
  before_replay <- vapply(
    DBI::dbListTables(store$connection),
    \(table) nrow(DBI::dbReadTable(store$connection, table)),
    integer(1)
  )
  replay <- withCallingHandlers(
    environment$ci_approve_and_commit(
      decision,
      "workflow-referral-result-json",
      store,
      "blue-sky-decision-2026-07-15",
      "Approved bounded bench test only.",
      record_mapper = environment$blue_sky_decision_record_mapper
    ),
    graft_batch_replay = function(condition) {
      replay_condition <<- condition
    }
  )
  after_replay <- vapply(
    DBI::dbListTables(store$connection),
    \(table) nrow(DBI::dbReadTable(store$connection, table)),
    integer(1)
  )
  expect_s3_class(replay_condition, "graft_batch_replay")
  expect_identical(replay$ingest$replay, TRUE)
  expect_identical(after_replay, before_replay)
})
