example_dir <- if (
  dir.exists(
    "inst/examples/continuous-intelligence"
  )
) {
  "inst/examples/continuous-intelligence"
} else {
  system.file(
    "examples",
    "continuous-intelligence",
    package = "graft",
    mustWork = TRUE
  )
}

source(file.path(example_dir, "R", "host.R"))
source(file.path(example_dir, "R", "blue-sky.R"))

run_continuous_intelligence_demo <- function(example_dir) {
  profile <- ci_read_json(
    file.path(example_dir, "profiles", "blue-sky.json")
  )
  schema <- graft::kg_schema(
    file.path(example_dir, "schema", "blue-sky.graft.json")
  )
  store_path <- tempfile("blue-sky-", fileext = ".duckdb")
  store <- graft::kg_connect_duckdb(schema, store_path)
  on.exit(
    {
      graft::kg_disconnect(store)
      unlink(store_path)
    },
    add = TRUE
  )
  graft::kg_init(store)

  baseline <- jsonlite::fromJSON(
    file.path(example_dir, "corpus", "baseline.json")
  )
  invisible(graft::kg_ingest(
    store,
    graft::kg_batch(
      "blue-sky-demo",
      idempotency_key = "blue-sky-baseline"
    ),
    baseline
  ))

  run_signal_day <- function(date, corpus_file) {
    monitor_id <- paste0("blue-sky-monitor-", date)
    review_id <- paste0("blue-sky-review-", date)
    daily_bundle <- ci_read_json(
      file.path(example_dir, "corpus", corpus_file)
    )
    monitor <- ci_run_monitor(
      profile,
      daily_bundle,
      store,
      monitor_id
    )
    cat(
      tempest::tempest_run_artifact(
        monitor,
        "daily-briefing-md"
      )@content,
      "\n\n"
    )
    review <- ci_run_knowledge_review(
      monitor,
      monitor_id,
      review_id
    )
    committed <- ci_approve_and_commit(
      review,
      "knowledge-change-set-json",
      store,
      review_id,
      "Approved source-faithful observations from the frozen corpus."
    )
    list(
      monitor = monitor,
      review = committed$run,
      ingest = committed$ingest
    )
  }

  day_one <- run_signal_day(
    "2026-07-14",
    "2026-07-14-supplier.json"
  )
  day_two <- run_signal_day(
    "2026-07-15",
    "2026-07-15-independent.json"
  )

  monitor_content <- tempest::tempest_run_artifact(
    day_two$monitor,
    "monitor-result-json"
  )@content
  referral <- monitor_content$referrals[[1L]]
  promotion_store <- ci_promotion_store()
  promotion_id <- ci_record_promotion(
    promotion_store,
    "blue-sky:promotion:prototype-gate:2026-07-15",
    referral,
    reviewer = "technology portfolio owner",
    decided_at = "2026-07-15T13:30:00Z",
    note = "Open the prototype-gate decision workflow."
  )
  decision <- ci_run_referral(
    referral,
    profile,
    store,
    blue_sky_result_builder,
    "blue-sky-decision-2026-07-15",
    promotion_store = promotion_store,
    promotion_id = promotion_id
  )
  decision_content <- tempest::tempest_run_artifact(
    decision,
    "workflow-referral-result-json"
  )@content
  cat(
    "# Promoted workflow\n\n",
    decision_content$recommendation,
    "\n\n",
    sep = ""
  )
  committed_decision <- ci_approve_and_commit(
    decision,
    "workflow-referral-result-json",
    store,
    "blue-sky-decision-2026-07-15",
    "Approved a bounded bench test; deployment remains unauthorized.",
    record_mapper = blue_sky_decision_record_mapper
  )

  day_three <- ci_run_monitor(
    profile,
    ci_read_json(file.path(
      example_dir,
      "corpus",
      "2026-07-16-no-change.json"
    )),
    store,
    "blue-sky-monitor-2026-07-16"
  )
  cat(
    tempest::tempest_run_artifact(
      day_three,
      "daily-briefing-md"
    )@content,
    "\n"
  )

  list(
    monitor_runs = list(
      day_one$monitor,
      day_two$monitor,
      day_three
    ),
    review_runs = list(day_one$review, day_two$review),
    decision_run = committed_decision$run,
    promotion_record = promotion_store$records[[promotion_id]],
    assessment_count = nrow(dplyr::collect(
      graft::kg_records(store, "Assessment")
    )),
    decision_count = nrow(dplyr::collect(
      graft::kg_records(store, "ReviewDecision")
    ))
  )
}

continuous_intelligence_demo <- run_continuous_intelligence_demo(
  example_dir
)
