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

test_that("scheduled signals promote through approval into accepted history", {
  if (!continuous_intelligence_tempest_available()) {
    testthat::skip("The current Tempest workflow API is not installed.")
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
  expect_equal(
    nrow(dplyr::collect(kg_records(store, "Observation"))),
    0L
  )
  mismatched_review <- tryCatch(
    environment$ci_run_knowledge_review(
      day_one$monitor,
      "not-the-monitor-run",
      "blue-sky-review-mismatch"
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
    paste0(
      c(day_one$review_id, day_two$review_id),
      ":",
      environment$ci_artifact_ingest_stage(
        "knowledge-change-set-json"
      )
    )
  )
  monitor_content <- tempest::tempest_run_artifact(
    day_two$monitor,
    "monitor-result-json"
  )@content
  expect_length(monitor_content$referrals, 1L)

  referral <- monitor_content$referrals[[1L]]
  evidence_promotion <- list(
    decision = "approved",
    reviewer = "technology portfolio owner",
    decided_at = "2026-07-15T13:30:00Z"
  )
  missing_evidence_referral <- referral
  missing_evidence_referral$evidence_record_ids <- c(
    "graft:00000000000000000000000999"
  )
  missing_evidence <- tryCatch(
    environment$ci_run_referral(
      missing_evidence_referral,
      profile,
      store,
      environment$blue_sky_result_builder,
      "blue-sky-decision-missing-evidence",
      promotion = evidence_promotion
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
  unrelated_evidence <- tryCatch(
    environment$ci_run_referral(
      unrelated_evidence_referral,
      profile,
      store,
      environment$blue_sky_result_builder,
      "blue-sky-decision-unrelated-evidence",
      promotion = evidence_promotion
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
  irrelevant_evidence <- tryCatch(
    environment$ci_run_referral(
      irrelevant_evidence_referral,
      profile,
      store,
      environment$blue_sky_result_builder,
      "blue-sky-decision-irrelevant-evidence",
      promotion = evidence_promotion
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
  promotion <- list(
    decision = "approved",
    reviewer = "technology portfolio owner",
    decided_at = "2026-07-15T13:30:00Z",
    note = "Open the prototype-gate decision workflow."
  )
  decision <- environment$ci_run_referral(
    referral,
    profile,
    store,
    environment$blue_sky_result_builder,
    "blue-sky-decision-2026-07-15",
    promotion = promotion
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

  replay_condition <- NULL
  decision_records <- environment$blue_sky_decision_record_mapper(
    tempest::tempest_run_artifact(
      decision,
      "workflow-referral-result-json"
    )@content,
    decision_commit$approval
  )
  before_replay <- vapply(
    DBI::dbListTables(store$connection),
    \(table) nrow(DBI::dbReadTable(store$connection, table)),
    integer(1)
  )
  replay <- withCallingHandlers(
    kg_ingest_tempest_records(
      store,
      "blue-sky-decision-2026-07-15",
      decision_records,
      stage = environment$ci_artifact_ingest_stage(
        "workflow-referral-result-json"
      )
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
  expect_identical(replay$replay, TRUE)
  expect_identical(after_replay, before_replay)
})
