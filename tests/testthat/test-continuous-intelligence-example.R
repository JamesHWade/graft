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
  day_one_commit <- environment$ci_approve_and_commit(
    day_one$review,
    "knowledge-change-set-json",
    store,
    day_one$review_id,
    "approved-observations",
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
      premature_context
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
    "approved-observations",
    "Approved source-faithful independent observations."
  )
  expect_identical(
    tempest::tempest_run_status(day_two_commit$run),
    "succeeded"
  )
  monitor_content <- tempest::tempest_run_artifact(
    day_two$monitor,
    "monitor-result-json"
  )@content
  expect_length(monitor_content$referrals, 1L)

  referral <- monitor_content$referrals[[1L]]
  decision <- environment$ci_run_referral(
    referral,
    profile,
    store,
    environment$blue_sky_result_builder,
    "blue-sky-decision-2026-07-15"
  )
  expect_identical(
    tempest::tempest_run_status(decision),
    "awaiting_approval"
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
    "approved-decision",
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
      stage = "approved-decision"
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
