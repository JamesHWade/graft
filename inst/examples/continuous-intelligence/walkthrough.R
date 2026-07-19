continuous_intelligence_example_dir <- if (
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

walkthrough_environment <- environment()
sys.source(
  file.path(
    continuous_intelligence_example_dir,
    "R",
    "host.R"
  ),
  envir = walkthrough_environment
)
sys.source(
  file.path(
    continuous_intelligence_example_dir,
    "R",
    "blue-sky.R"
  ),
  envir = walkthrough_environment
)
rm(walkthrough_environment)

ci_walkthrough_console_gate <- function(
  stage,
  action,
  title,
  detail,
  read_input = base::readline
) {
  cat(
    "\n",
    strrep("=", 72L),
    "\n",
    title,
    "\n",
    "Stage: ",
    stage,
    "\n",
    strrep("-", 72L),
    "\n",
    detail,
    "\n\n",
    sep = ""
  )
  if (!interactive() && identical(read_input, base::readline)) {
    stop(
      paste(
        "The staged walkthrough needs an interactive R session or a",
        "custom `gate` callback."
      )
    )
  }
  if (identical(action, "continue")) {
    read_input("Press Enter to continue: ")
    return(TRUE)
  }
  response <- read_input(paste0(
    "Type `",
    action,
    "` to continue; anything else stops here: "
  ))
  identical(tolower(trimws(response)), action)
}

ci_walkthrough_apply_gate <- function(
  gate,
  stage,
  action,
  title,
  detail
) {
  decision <- gate(
    stage = stage,
    action = action,
    title = title,
    detail = detail
  )
  if (
    !is.logical(decision) ||
      length(decision) != 1L ||
      is.na(decision)
  ) {
    stop("The walkthrough `gate` must return one non-missing logical value.")
  }
  decision
}

ci_walkthrough_result <- function(
  state,
  status,
  stopped_at = NULL,
  store = NULL
) {
  counts <- if (is.null(store)) {
    list(
      assessment_count = NA_integer_,
      decision_count = NA_integer_
    )
  } else {
    list(
      assessment_count = nrow(dplyr::collect(
        graft::kg_records(store, "Assessment")
      )),
      decision_count = nrow(dplyr::collect(
        graft::kg_records(store, "ReviewDecision")
      ))
    )
  }
  c(
    list(
      status = status,
      stopped_at = stopped_at
    ),
    state,
    counts
  )
}

run_continuous_intelligence_walkthrough <- function(
  example_dir = continuous_intelligence_example_dir,
  gate = ci_walkthrough_console_gate
) {
  state <- list(
    monitor_runs = list(),
    review_runs = list(),
    decision_run = NULL,
    promotion_record = NULL,
    ingests = list()
  )
  proceed <- ci_walkthrough_apply_gate(
    gate,
    "welcome",
    "continue",
    "Continuous intelligence: operator walkthrough",
    paste(
      "You are the technology executive for a themed-experience",
      "organization. Over three simulated mornings, you will review",
      "briefings, decide whether candidate knowledge can enter Graft,",
      "promote a material referral, and approve or stop a bounded decision."
    )
  )
  if (!proceed) {
    return(ci_walkthrough_result(
      state,
      "stopped",
      stopped_at = "welcome"
    ))
  }

  profile <- ci_read_json(
    file.path(example_dir, "profiles", "blue-sky.json")
  )
  schema <- graft::kg_schema(
    file.path(example_dir, "schema", "blue-sky.graft.json")
  )
  store_path <- tempfile("blue-sky-walkthrough-", fileext = ".duckdb")
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
      "blue-sky-walkthrough",
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
    review <- ci_run_knowledge_review(
      monitor,
      monitor_id,
      review_id,
      store
    )
    list(
      monitor_id = monitor_id,
      review_id = review_id,
      monitor = monitor,
      review = review
    )
  }

  day_one <- run_signal_day(
    "2026-07-14",
    "2026-07-14-supplier.json"
  )
  state$monitor_runs[[1L]] <- day_one$monitor
  state$review_runs[[1L]] <- day_one$review
  briefing <- tempest::tempest_run_artifact(
    day_one$monitor,
    "daily-briefing-md"
  )@content
  proceed <- ci_walkthrough_apply_gate(
    gate,
    "supplier-briefing",
    "continue",
    "Morning one: supplier signal",
    briefing
  )
  if (!proceed) {
    return(ci_walkthrough_result(
      state,
      "stopped",
      stopped_at = "supplier-briefing",
      store = store
    ))
  }

  review_content <- tempest::tempest_run_artifact(
    day_one$review,
    "knowledge-change-set-json"
  )@content
  proceed <- ci_walkthrough_apply_gate(
    gate,
    "supplier-knowledge",
    "approve",
    "Knowledge boundary: supplier records",
    paste(
      ci_proposal_count(review_content$knowledge_changes),
      paste(
        "candidate records are awaiting approval.",
        "They remain outside Graft until you approve this artifact."
      )
    )
  )
  if (!proceed) {
    return(ci_walkthrough_result(
      state,
      "stopped",
      stopped_at = "supplier-knowledge",
      store = store
    ))
  }
  committed <- ci_approve_and_commit(
    day_one$review,
    "knowledge-change-set-json",
    store,
    day_one$review_id,
    "Approved source-faithful supplier observations."
  )
  state$review_runs[[1L]] <- committed$run
  state$ingests[[1L]] <- committed$ingest

  day_two <- run_signal_day(
    "2026-07-15",
    "2026-07-15-independent.json"
  )
  state$monitor_runs[[2L]] <- day_two$monitor
  state$review_runs[[2L]] <- day_two$review
  briefing <- tempest::tempest_run_artifact(
    day_two$monitor,
    "daily-briefing-md"
  )@content
  proceed <- ci_walkthrough_apply_gate(
    gate,
    "independent-briefing",
    "continue",
    "Morning two: independent evidence",
    briefing
  )
  if (!proceed) {
    return(ci_walkthrough_result(
      state,
      "stopped",
      stopped_at = "independent-briefing",
      store = store
    ))
  }

  review_content <- tempest::tempest_run_artifact(
    day_two$review,
    "knowledge-change-set-json"
  )@content
  proceed <- ci_walkthrough_apply_gate(
    gate,
    "independent-knowledge",
    "approve",
    "Knowledge boundary: independent test records",
    paste(
      ci_proposal_count(review_content$knowledge_changes),
      paste(
        "candidate records are awaiting approval.",
        "Approval accepts the observations and their evidence lineage,",
        "but does not authorize a prototype or deployment."
      )
    )
  )
  if (!proceed) {
    return(ci_walkthrough_result(
      state,
      "stopped",
      stopped_at = "independent-knowledge",
      store = store
    ))
  }
  committed <- ci_approve_and_commit(
    day_two$review,
    "knowledge-change-set-json",
    store,
    day_two$review_id,
    "Approved source-faithful independent observations."
  )
  state$review_runs[[2L]] <- committed$run
  state$ingests[[2L]] <- committed$ingest

  monitor_content <- tempest::tempest_run_artifact(
    day_two$monitor,
    "monitor-result-json"
  )@content
  referral <- monitor_content$referrals[[1L]]
  proceed <- ci_walkthrough_apply_gate(
    gate,
    "workflow-promotion",
    "promote",
    "Promotion boundary: prototype-gate referral",
    paste(
      referral$reason,
      paste0("Objective: ", referral$objective),
      "Promotion opens a decision workflow; it does not approve its result.",
      sep = "\n\n"
    )
  )
  if (!proceed) {
    return(ci_walkthrough_result(
      state,
      "stopped",
      stopped_at = "workflow-promotion",
      store = store
    ))
  }
  promotion_store <- ci_promotion_store()
  promotion_id <- ci_record_promotion(
    promotion_store,
    "blue-sky:promotion:prototype-gate:2026-07-15",
    referral,
    reviewer = "technology portfolio owner",
    decided_at = "2026-07-15T13:30:00Z",
    note = "Open the prototype-gate decision workflow."
  )
  state$promotion_record <- promotion_store$records[[promotion_id]]

  decision <- ci_run_referral(
    referral,
    profile,
    store,
    blue_sky_result_builder,
    "blue-sky-decision-2026-07-15",
    promotion_store = promotion_store,
    promotion_id = promotion_id
  )
  state$decision_run <- decision
  decision_content <- tempest::tempest_run_artifact(
    decision,
    "workflow-referral-result-json"
  )@content
  proceed <- ci_walkthrough_apply_gate(
    gate,
    "decision-approval",
    "approve",
    "Decision boundary: bounded prototype test",
    paste(
      decision_content$recommendation,
      paste(
        "Approval commits the bounded decision and supersedes the prior",
        "hold. It does not authorize deployment."
      ),
      sep = "\n\n"
    )
  )
  if (!proceed) {
    return(ci_walkthrough_result(
      state,
      "stopped",
      stopped_at = "decision-approval",
      store = store
    ))
  }
  committed_decision <- ci_approve_and_commit(
    decision,
    "workflow-referral-result-json",
    store,
    "blue-sky-decision-2026-07-15",
    "Approved a bounded bench test; deployment remains unauthorized.",
    record_mapper = blue_sky_decision_record_mapper
  )
  state$decision_run <- committed_decision$run
  state$ingests[[3L]] <- committed_decision$ingest

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
  state$monitor_runs[[3L]] <- day_three
  briefing <- tempest::tempest_run_artifact(
    day_three,
    "daily-briefing-md"
  )@content
  proceed <- ci_walkthrough_apply_gate(
    gate,
    "no-change-briefing",
    "continue",
    "Morning three: no material change",
    briefing
  )
  if (!proceed) {
    return(ci_walkthrough_result(
      state,
      "stopped",
      stopped_at = "no-change-briefing",
      store = store
    ))
  }

  ci_walkthrough_result(
    state,
    "completed",
    store = store
  )
}
