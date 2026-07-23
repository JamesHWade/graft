ci_app_latest_monitor <- function(scenario) {
  runs <- scenario$state$monitor_runs
  if (length(runs) == 0L) {
    return(NULL)
  }
  runs[[length(runs)]]
}

ci_app_latest_briefing <- function(scenario) {
  monitor <- ci_app_latest_monitor(scenario)
  if (is.null(monitor)) {
    return(NULL)
  }
  ci_scenario_artifact_content(monitor, "daily-briefing-md")
}

ci_app_latest_monitor_content <- function(scenario) {
  monitor <- ci_app_latest_monitor(scenario)
  if (is.null(monitor)) {
    return(NULL)
  }
  ci_scenario_artifact_content(monitor, "monitor-result-json")
}

ci_app_decision_content <- function(scenario) {
  if (is.null(scenario$state$decision_run)) {
    return(NULL)
  }
  ci_scenario_artifact_content(
    scenario$state$decision_run,
    "workflow-referral-result-json"
  )
}

ci_app_decision_records <- function(scenario) {
  records <- dplyr::collect(
    graft::kg_records(scenario$store, "ReviewDecision")
  )
  columns <- intersect(
    c(
      "status",
      "disposition",
      "statement_text",
      "reviewer_role",
      "asserted_at"
    ),
    names(records)
  )
  records <- records[, columns, drop = FALSE]
  if ("asserted_at" %in% names(records)) {
    records$asserted_at <- format(
      records$asserted_at,
      "%Y-%m-%d %H:%M UTC",
      tz = "UTC"
    )
  }
  names(records) <- c(
    status = "Status",
    disposition = "Position",
    statement_text = "Decision",
    reviewer_role = "Reviewer",
    asserted_at = "Accepted at"
  )[names(records)]
  records
}

ci_app_decision_evidence <- function(scenario) {
  decisions <- dplyr::collect(
    graft::kg_records(scenario$store, "ReviewDecision")
  )
  active <- decisions[decisions$status == "active", , drop = FALSE]
  if (nrow(active) == 0L) {
    return(data.frame())
  }
  accepted <- graft::kg_get(
    scenario$store,
    active$id[[nrow(active)]],
    include = "evidence"
  )
  evidence <- accepted$evidence
  columns <- intersect(
    c("support_type", "excerpt", "locator_type", "locator_value"),
    names(evidence)
  )
  evidence <- evidence[, columns, drop = FALSE]
  names(evidence) <- c(
    support_type = "Support",
    excerpt = "Evidence excerpt",
    locator_type = "Locator",
    locator_value = "Location"
  )[names(evidence)]
  evidence
}

ci_app_batch_history <- function(scenario) {
  batches <- graft::kg_batches(scenario$store, limit = 20L)
  columns <- intersect(
    c(
      "commit_order",
      "producer",
      "source_run_id",
      "status",
      "committed_at"
    ),
    names(batches)
  )
  batches <- batches[, columns, drop = FALSE]
  if ("commit_order" %in% names(batches)) {
    batches$commit_order <- as.integer(batches$commit_order)
  }
  if ("source_run_id" %in% names(batches)) {
    batches$source_run_id[is.na(batches$source_run_id)] <- "baseline"
  }
  if ("committed_at" %in% names(batches)) {
    batches$committed_at <- format(
      batches$committed_at,
      "%Y-%m-%d %H:%M UTC",
      tz = "UTC"
    )
  }
  names(batches) <- c(
    commit_order = "Commit",
    producer = "Producer",
    source_run_id = "Source run",
    status = "Status",
    committed_at = "Committed at"
  )[names(batches)]
  batches
}

ci_app_workflow_runs <- function(scenario) {
  state <- scenario$state
  run_status <- function(run) {
    if (is.null(run)) {
      return(NA_character_)
    }
    tempest::tempest_run_status(run)
  }
  data.frame(
    workflow = c(
      sprintf("Monitor %d", seq_along(state$monitor_runs)),
      sprintf("Knowledge review %d", seq_along(state$review_runs)),
      if (!is.null(state$decision_run)) "Promoted decision" else character()
    ),
    status = c(
      vapply(state$monitor_runs, run_status, character(1)),
      vapply(state$review_runs, run_status, character(1)),
      if (!is.null(state$decision_run)) {
        run_status(state$decision_run)
      } else {
        character()
      }
    ),
    stringsAsFactors = FALSE
  ) |>
    stats::setNames(c("Workflow", "Status"))
}

ci_app_pending_count <- function(scenario) {
  if (!identical(scenario$status, "active")) {
    return(0L)
  }
  runs <- c(
    scenario$state$review_runs,
    if (!is.null(scenario$state$decision_run)) {
      list(scenario$state$decision_run)
    } else {
      list()
    }
  )
  awaiting_approval <- sum(vapply(
    runs,
    \(run) {
      identical(
        tempest::tempest_run_status(run),
        "awaiting_approval"
      )
    },
    logical(1)
  ))
  as.integer(awaiting_approval) +
    as.integer(identical(scenario$stage, "workflow-promotion"))
}

ci_app_active_position <- function(scenario) {
  decisions <- dplyr::collect(
    graft::kg_records(scenario$store, "ReviewDecision")
  )
  active <- decisions[decisions$status == "active", , drop = FALSE]
  if (nrow(active) == 0L || !"disposition" %in% names(active)) {
    return("None")
  }
  tools::toTitleCase(active$disposition[[nrow(active)]])
}
