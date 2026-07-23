ci_scenario_new <- function(example_dir, store_path = NULL) {
  if (!dir.exists(example_dir)) {
    stop("`example_dir` must identify the continuous-intelligence example.")
  }
  example_dir <- normalizePath(example_dir, mustWork = TRUE)
  owns_store_path <- is.null(store_path)
  if (owns_store_path) {
    store_path <- tempfile("blue-sky-scenario-", fileext = ".duckdb")
  }

  profile <- ci_read_json(
    file.path(example_dir, "profiles", "blue-sky.json")
  )
  schema <- graft::kg_schema(
    file.path(example_dir, "schema", "blue-sky.graft.json")
  )
  store <- graft::kg_connect_duckdb(schema, store_path)
  initialized <- FALSE
  on.exit(
    {
      if (!initialized) {
        graft::kg_disconnect(store)
        if (owns_store_path) {
          unlink(store_path)
        }
      }
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
      "blue-sky-scenario",
      idempotency_key = "blue-sky-baseline"
    ),
    baseline
  ))

  scenario <- new.env(parent = emptyenv())
  scenario$example_dir <- example_dir
  scenario$profile <- profile
  scenario$store <- store
  scenario$store_path <- store_path
  scenario$owns_store_path <- owns_store_path
  scenario$status <- "active"
  scenario$stage <- "welcome"
  scenario$stopped_at <- NULL
  scenario$closed <- FALSE
  scenario$promotion_store <- NULL
  scenario$state <- list(
    monitor_runs = list(),
    review_runs = list(),
    decision_run = NULL,
    promotion_record = NULL,
    ingests = list()
  )
  class(scenario) <- "ci_scenario"
  initialized <- TRUE
  scenario
}

ci_scenario_validate <- function(scenario, require_active = FALSE) {
  if (!inherits(scenario, "ci_scenario")) {
    stop("`scenario` must be a continuous-intelligence scenario.")
  }
  if (isTRUE(scenario$closed)) {
    stop("The continuous-intelligence scenario is closed.")
  }
  if (require_active && !identical(scenario$status, "active")) {
    stop("The continuous-intelligence scenario is not active.")
  }
  invisible(scenario)
}

ci_scenario_close <- function(scenario) {
  if (!inherits(scenario, "ci_scenario") || isTRUE(scenario$closed)) {
    return(invisible(NULL))
  }
  disconnect_error <- NULL
  tryCatch(
    graft::kg_disconnect(scenario$store),
    error = function(error) {
      disconnect_error <<- error
    }
  )
  if (isTRUE(scenario$owns_store_path)) {
    unlink(scenario$store_path)
  }
  scenario$closed <- TRUE
  if (!is.null(disconnect_error)) {
    stop(disconnect_error)
  }
  invisible(NULL)
}

ci_scenario_run_signal_day <- function(scenario, date, corpus_file) {
  monitor_id <- paste0("blue-sky-monitor-", date)
  review_id <- paste0("blue-sky-review-", date)
  daily_bundle <- ci_read_json(
    file.path(scenario$example_dir, "corpus", corpus_file)
  )
  monitor <- ci_run_monitor(
    scenario$profile,
    daily_bundle,
    scenario$store,
    monitor_id
  )
  review <- ci_run_knowledge_review(
    monitor,
    monitor_id,
    review_id,
    scenario$store
  )
  list(
    monitor_id = monitor_id,
    review_id = review_id,
    monitor = monitor,
    review = review
  )
}

ci_scenario_artifact_content <- function(run, artifact_id) {
  tempest::tempest_run_artifact(run, artifact_id)@content
}

ci_scenario_stage <- function(scenario) {
  ci_scenario_validate(scenario)
  state <- scenario$state
  stage <- scenario$stage

  if (identical(stage, "welcome")) {
    return(list(
      id = stage,
      phase = "Before the first morning",
      title = "The Blue-Sky Briefing Room",
      detail = paste(
        "You are the technology executive for a themed-experience",
        "organization. Over three simulated mornings, you will review",
        "briefings, govern candidate knowledge, and make one bounded",
        "decision without authorizing deployment."
      ),
      format = "text",
      action = "continue",
      action_label = "Run morning one"
    ))
  }
  if (identical(stage, "supplier-briefing")) {
    return(list(
      id = stage,
      phase = "Morning one · July 14",
      title = "Supplier signal",
      detail = ci_scenario_artifact_content(
        state$monitor_runs[[1L]],
        "daily-briefing-md"
      ),
      format = "markdown",
      action = "continue",
      action_label = "Review candidate knowledge"
    ))
  }
  if (identical(stage, "supplier-knowledge")) {
    content <- ci_scenario_artifact_content(
      state$review_runs[[1L]],
      "knowledge-change-set-json"
    )
    return(list(
      id = stage,
      phase = "Morning one · Review boundary",
      title = "Supplier records await approval",
      detail = paste(
        ci_proposal_count(content$knowledge_changes),
        paste(
          "candidate records remain outside Graft.",
          "Approval accepts the observations and their evidence lineage;",
          "it does not authorize a prototype or deployment."
        )
      ),
      format = "text",
      action = "approve",
      action_label = "Approve into Graft"
    ))
  }
  if (identical(stage, "independent-briefing")) {
    return(list(
      id = stage,
      phase = "Morning two · July 15",
      title = "Independent evidence",
      detail = ci_scenario_artifact_content(
        state$monitor_runs[[2L]],
        "daily-briefing-md"
      ),
      format = "markdown",
      action = "continue",
      action_label = "Review candidate knowledge"
    ))
  }
  if (identical(stage, "independent-knowledge")) {
    content <- ci_scenario_artifact_content(
      state$review_runs[[2L]],
      "knowledge-change-set-json"
    )
    return(list(
      id = stage,
      phase = "Morning two · Review boundary",
      title = "Independent records await approval",
      detail = paste(
        ci_proposal_count(content$knowledge_changes),
        paste(
          "candidate records remain outside Graft.",
          "Approval accepts the source-faithful observations,",
          "but does not authorize the referred workflow."
        )
      ),
      format = "text",
      action = "approve",
      action_label = "Approve into Graft"
    ))
  }
  if (identical(stage, "workflow-promotion")) {
    content <- ci_scenario_artifact_content(
      state$monitor_runs[[2L]],
      "monitor-result-json"
    )
    referral <- content$referrals[[1L]]
    return(list(
      id = stage,
      phase = "Morning two · Routing boundary",
      title = "A decision workflow is ready",
      detail = paste(
        referral$reason,
        paste0("Objective: ", referral$objective),
        "Promotion opens the workflow; it does not approve its result.",
        sep = "\n\n"
      ),
      format = "text",
      action = "promote",
      action_label = "Promote decision workflow"
    ))
  }
  if (identical(stage, "decision-approval")) {
    content <- ci_scenario_artifact_content(
      state$decision_run,
      "workflow-referral-result-json"
    )
    return(list(
      id = stage,
      phase = "Morning two · Decision boundary",
      title = "Bounded prototype test",
      detail = paste(
        content$recommendation,
        paste(
          "Approval commits this decision and supersedes the prior hold.",
          "It does not authorize deployment."
        ),
        sep = "\n\n"
      ),
      format = "text",
      action = "approve",
      action_label = "Approve bounded test"
    ))
  }
  if (identical(stage, "no-change-briefing")) {
    return(list(
      id = stage,
      phase = "Morning three · July 16",
      title = "No material change",
      detail = ci_scenario_artifact_content(
        state$monitor_runs[[3L]],
        "daily-briefing-md"
      ),
      format = "markdown",
      action = "continue",
      action_label = "Complete the walkthrough"
    ))
  }
  if (identical(stage, "completed")) {
    return(list(
      id = stage,
      phase = "Scenario complete",
      title = "The decision memory is ready for tomorrow",
      detail = paste(
        "The prior hold is superseded, the bounded test is the active",
        "decision, and the final briefing retrieved that accepted history",
        "without inventing a new signal."
      ),
      format = "text",
      action = NULL,
      action_label = NULL
    ))
  }
  if (identical(stage, "stopped")) {
    return(list(
      id = stage,
      phase = "Scenario stopped",
      title = "No pending action was performed",
      detail = paste(
        "The operator stopped at",
        scenario$stopped_at,
        "and the corresponding write or promotion did not occur."
      ),
      format = "text",
      action = NULL,
      action_label = NULL
    ))
  }
  stop("The continuous-intelligence scenario has an unknown stage.")
}

ci_scenario_advance <- function(scenario) {
  ci_scenario_validate(scenario, require_active = TRUE)
  state <- scenario$state
  stage <- scenario$stage

  if (identical(stage, "welcome")) {
    if (length(state$monitor_runs) < 1L) {
      day_one <- ci_scenario_run_signal_day(
        scenario,
        "2026-07-14",
        "2026-07-14-supplier.json"
      )
      state$monitor_runs[[1L]] <- day_one$monitor
      state$review_runs[[1L]] <- day_one$review
    }
    scenario$stage <- "supplier-briefing"
  } else if (identical(stage, "supplier-briefing")) {
    scenario$stage <- "supplier-knowledge"
  } else if (identical(stage, "supplier-knowledge")) {
    if (length(state$ingests) < 1L) {
      committed <- ci_approve_and_commit(
        state$review_runs[[1L]],
        "knowledge-change-set-json",
        scenario$store,
        "blue-sky-review-2026-07-14",
        "Approved source-faithful supplier observations."
      )
      state$review_runs[[1L]] <- committed$run
      state$ingests[[1L]] <- committed$ingest
      scenario$state <- state
    }
    if (length(state$monitor_runs) < 2L) {
      day_two <- ci_scenario_run_signal_day(
        scenario,
        "2026-07-15",
        "2026-07-15-independent.json"
      )
      state$monitor_runs[[2L]] <- day_two$monitor
      state$review_runs[[2L]] <- day_two$review
    }
    scenario$stage <- "independent-briefing"
  } else if (identical(stage, "independent-briefing")) {
    scenario$stage <- "independent-knowledge"
  } else if (identical(stage, "independent-knowledge")) {
    if (length(state$ingests) < 2L) {
      committed <- ci_approve_and_commit(
        state$review_runs[[2L]],
        "knowledge-change-set-json",
        scenario$store,
        "blue-sky-review-2026-07-15",
        "Approved source-faithful independent observations."
      )
      state$review_runs[[2L]] <- committed$run
      state$ingests[[2L]] <- committed$ingest
      scenario$state <- state
    }
    scenario$stage <- "workflow-promotion"
  } else if (identical(stage, "workflow-promotion")) {
    monitor_content <- ci_scenario_artifact_content(
      state$monitor_runs[[2L]],
      "monitor-result-json"
    )
    referral <- monitor_content$referrals[[1L]]
    if (is.null(scenario$promotion_store)) {
      scenario$promotion_store <- ci_promotion_store()
    }
    promotion_id <- "blue-sky:promotion:prototype-gate:2026-07-15"
    if (is.null(state$promotion_record)) {
      ci_record_promotion(
        scenario$promotion_store,
        promotion_id,
        referral,
        reviewer = "technology portfolio owner",
        decided_at = "2026-07-15T13:30:00Z",
        note = "Open the prototype-gate decision workflow."
      )
      state$promotion_record <-
        scenario$promotion_store$records[[promotion_id]]
      scenario$state <- state
    }
    if (is.null(state$decision_run)) {
      state$decision_run <- ci_run_referral(
        referral,
        scenario$profile,
        scenario$store,
        blue_sky_result_builder,
        "blue-sky-decision-2026-07-15",
        promotion_store = scenario$promotion_store,
        promotion_id = promotion_id
      )
    }
    scenario$stage <- "decision-approval"
  } else if (identical(stage, "decision-approval")) {
    if (length(state$ingests) < 3L) {
      committed <- ci_approve_and_commit(
        state$decision_run,
        "workflow-referral-result-json",
        scenario$store,
        "blue-sky-decision-2026-07-15",
        "Approved a bounded bench test; deployment remains unauthorized.",
        record_mapper = blue_sky_decision_record_mapper
      )
      state$decision_run <- committed$run
      state$ingests[[3L]] <- committed$ingest
      scenario$state <- state
    }
    if (length(state$monitor_runs) < 3L) {
      state$monitor_runs[[3L]] <- ci_run_monitor(
        scenario$profile,
        ci_read_json(file.path(
          scenario$example_dir,
          "corpus",
          "2026-07-16-no-change.json"
        )),
        scenario$store,
        "blue-sky-monitor-2026-07-16"
      )
    }
    scenario$stage <- "no-change-briefing"
  } else if (identical(stage, "no-change-briefing")) {
    scenario$stage <- "completed"
    scenario$status <- "completed"
  } else {
    stop("The current scenario stage cannot advance.")
  }

  scenario$state <- state
  invisible(ci_scenario_stage(scenario))
}

ci_scenario_stop <- function(scenario) {
  ci_scenario_validate(scenario, require_active = TRUE)
  scenario$stopped_at <- scenario$stage
  scenario$stage <- "stopped"
  scenario$status <- "stopped"
  invisible(ci_scenario_stage(scenario))
}

ci_scenario_counts <- function(scenario) {
  ci_scenario_validate(scenario)
  list(
    assessment_count = nrow(dplyr::collect(
      graft::kg_records(scenario$store, "Assessment")
    )),
    decision_count = nrow(dplyr::collect(
      graft::kg_records(scenario$store, "ReviewDecision")
    ))
  )
}

ci_scenario_result <- function(scenario) {
  ci_scenario_validate(scenario)
  counts <- ci_scenario_counts(scenario)
  c(
    list(
      status = scenario$status,
      stopped_at = scenario$stopped_at
    ),
    scenario$state,
    counts
  )
}

ci_scenario_timeline <- function(scenario) {
  ci_scenario_validate(scenario)
  stages <- c(
    "welcome",
    "supplier-briefing",
    "supplier-knowledge",
    "independent-briefing",
    "independent-knowledge",
    "workflow-promotion",
    "decision-approval",
    "no-change-briefing",
    "completed"
  )
  labels <- c(
    "Baseline accepted",
    "Supplier briefing",
    "Supplier knowledge review",
    "Independent briefing",
    "Independent knowledge review",
    "Decision workflow promotion",
    "Bounded decision review",
    "No-change briefing",
    "Decision memory ready"
  )
  current_index <- if (identical(scenario$stage, "stopped")) {
    match(scenario$stopped_at, stages)
  } else {
    match(scenario$stage, stages)
  }
  status <- rep("upcoming", length(stages))
  status[seq_len(max(1L, current_index - 1L))] <- "complete"
  status[[current_index]] <- if (identical(scenario$stage, "stopped")) {
    "stopped"
  } else {
    "current"
  }
  if (identical(scenario$stage, "completed")) {
    status[] <- "complete"
  }
  data.frame(
    stage = stages,
    label = labels,
    status = status,
    stringsAsFactors = FALSE
  )
}
