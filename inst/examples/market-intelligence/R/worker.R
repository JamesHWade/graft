mi_tempest_exports <- function() {
  c(
    "tempest_artifact_representation",
    "tempest_builtin_operation_registry",
    "tempest_deliverable_spec",
    "tempest_expert",
    "tempest_generate_deliverable",
    "tempest_objective",
    "tempest_run_approvals",
    "tempest_run_artifact",
    "tempest_run_events",
    "tempest_run_record_approval",
    "tempest_run_status",
    "tempest_run_workflow",
    "tempest_workflow_spec",
    "tempest_workflow_step"
  )
}

mi_require_runtime <- function() {
  packages <- c(
    "dplyr",
    "dsprrr",
    "ellmer",
    "graft",
    "jsonlite",
    "tempest"
  )
  missing <- packages[
    !vapply(packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing) > 0L) {
    stop(
      "Install the market-intelligence runtime dependencies: ",
      paste(missing, collapse = ", ")
    )
  }
  unavailable <- setdiff(
    mi_tempest_exports(),
    getNamespaceExports("tempest")
  )
  if (length(unavailable) > 0L) {
    stop(
      paste(
        "Install the current development version of Tempest.",
        "The installed package is missing:",
        paste(unavailable, collapse = ", ")
      )
    )
  }
  invisible(TRUE)
}

mi_iso_time <- function(value = Sys.time()) {
  format(
    as.POSIXct(value, tz = "UTC"),
    "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  )
}

mi_run_id <- function() {
  paste0(
    "market-",
    format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"),
    "-",
    sprintf("%06d", sample.int(999999L, 1L))
  )
}

mi_id_suffix <- function(value) {
  value <- tolower(mi_text(value, "id"))
  value <- gsub("[^a-z0-9._~-]+", "-", value)
  gsub("(^-+|-+$)", "", value)
}

mi_rows_frame <- function(rows, fields) {
  values <- lapply(
    fields,
    function(field) {
      vapply(
        rows,
        function(row) {
          value <- row[[field]]
          if (is.null(value)) NA_character_ else as.character(value)
        },
        character(1)
      )
    }
  )
  names(values) <- fields
  as.data.frame(values, stringsAsFactors = FALSE)
}

mi_baseline_records <- function(baseline) {
  list(
    Business = mi_rows_frame(
      baseline$businesses,
      c("id", "name", "segment", "description")
    ),
    Competitor = mi_rows_frame(
      baseline$competitors,
      c("id", "name", "description")
    ),
    DownstreamMarket = mi_rows_frame(
      baseline$downstream_markets,
      c("id", "name", "description")
    )
  )
}

mi_bundle_files <- function(example_dir) {
  files <- list.files(
    file.path(example_dir, "corpus"),
    pattern = "^20[0-9]{2}-[0-9]{2}-[0-9]{2}.*[.]json$",
    full.names = TRUE
  )
  sort(files)
}

mi_worker_new <- function(example_dir, store_path = NULL) {
  mi_require_runtime()
  example_dir <- normalizePath(example_dir, mustWork = TRUE)
  owns_store_path <- is.null(store_path)
  if (owns_store_path) {
    store_path <- tempfile("market-intelligence-", fileext = ".duckdb")
  }
  schema <- graft::kg_schema(
    file.path(
      example_dir,
      "schema",
      "market-intelligence.graft.json"
    )
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
  baseline <- mi_read_json(
    file.path(example_dir, "corpus", "baseline.json")
  )
  invisible(graft::kg_ingest(
    store,
    graft::kg_batch(
      "graft-market-intelligence",
      producer_version = "1",
      idempotency_key = "market-intelligence-baseline"
    ),
    mi_baseline_records(baseline)
  ))

  worker <- new.env(parent = emptyenv())
  worker$example_dir <- example_dir
  worker$store <- store
  worker$store_path <- store_path
  worker$owns_store_path <- owns_store_path
  worker$bundle_files <- mi_bundle_files(example_dir)
  worker$resolved_bundles <- character()
  worker$current_run_id <- NULL
  worker$runs <- list()
  worker$run_metadata <- list()
  worker$commits <- list()
  worker$closed <- FALSE
  class(worker) <- "mi_worker"
  initialized <- TRUE
  worker
}

mi_worker_validate <- function(worker) {
  if (!inherits(worker, "mi_worker")) {
    stop("`worker` must be a market-intelligence worker.")
  }
  if (isTRUE(worker$closed)) {
    stop("The market-intelligence worker is closed.")
  }
  invisible(worker)
}

mi_worker_close <- function(worker) {
  if (!inherits(worker, "mi_worker") || isTRUE(worker$closed)) {
    return(invisible(NULL))
  }
  graft::kg_disconnect(worker$store)
  if (isTRUE(worker$owns_store_path)) {
    unlink(worker$store_path)
  }
  worker$closed <- TRUE
  invisible(NULL)
}

mi_worker_records <- function(worker, class) {
  mi_worker_validate(worker)
  graft::kg_records(worker$store, class) |>
    dplyr::collect()
}

mi_worker_current_run <- function(worker) {
  mi_worker_validate(worker)
  if (is.null(worker$current_run_id)) {
    return(NULL)
  }
  worker$runs[[worker$current_run_id]]
}

mi_worker_pending <- function(worker) {
  run <- mi_worker_current_run(worker)
  if (is.null(run)) {
    return(list())
  }
  tempest::tempest_run_approvals(run, status = "pending")
}

mi_worker_next_bundle <- function(worker) {
  mi_worker_validate(worker)
  for (path in worker$bundle_files) {
    bundle <- mi_read_json(path)
    if (!bundle$bundle_id %in% worker$resolved_bundles) {
      return(bundle)
    }
  }
  NULL
}

mi_worker_memory_context <- function(worker) {
  assessments <- mi_worker_records(worker, "Assessment") |>
    dplyr::arrange(.data$accepted_at, .data$id)
  if (nrow(assessments) == 0L) {
    return("No accepted market assessments yet.")
  }
  paste(
    vapply(
      seq_len(nrow(assessments)),
      function(index) {
        paste0(
          "- ",
          assessments$headline[[index]],
          ": ",
          assessments$implication[[index]],
          " [accepted ",
          assessments$accepted_at[[index]],
          "]"
        )
      },
      character(1)
    ),
    collapse = "\n"
  )
}

mi_planner_engine <- function(planner) {
  mi_or(planner$config$engine, class(planner)[[1L]])
}

mi_worker_prepare <- function(
  worker,
  bundle = mi_worker_next_bundle(worker),
  request = NULL,
  planner = NULL
) {
  mi_worker_validate(worker)
  current <- mi_worker_current_run(worker)
  if (
    !is.null(current) &&
      identical(tempest::tempest_run_status(current), "awaiting_approval")
  ) {
    stop(
      paste(
        "Resolve the current assessment before starting another scan.",
        "This keeps each approval bound to one evidence package."
      )
    )
  }
  if (is.null(bundle)) {
    stop("No unresolved signal bundle remains.")
  }
  request <- mi_or(request, bundle$suggested_request)
  request <- mi_text(request, "request")
  planner <- mi_or(planner, mi_reference_planner(bundle))
  run_id <- mi_run_id()
  memory <- mi_worker_memory_context(worker)
  run <- mi_run_workflow(
    request = request,
    planner = planner,
    bundle = bundle,
    accepted_memory = memory,
    run_id = run_id
  )
  worker$runs[[run_id]] <- run
  worker$run_metadata[[run_id]] <- list(
    bundle = bundle,
    request = request,
    planning_engine = mi_planner_engine(planner),
    started_at = mi_iso_time(),
    accepted_memory = memory
  )
  worker$current_run_id <- run_id
  mi_worker_snapshot(worker)
}

mi_worker_artifact <- function(worker, artifact_id) {
  run <- mi_worker_current_run(worker)
  if (is.null(run)) {
    return(NULL)
  }
  tempest::tempest_run_artifact(run, artifact_id)
}

mi_worker_snapshot <- function(worker) {
  mi_worker_validate(worker)
  run <- mi_worker_current_run(worker)
  if (is.null(run)) {
    return(list(
      run_id = NULL,
      status = "ready",
      bundle_id = NULL,
      scan_date = NULL,
      request = NULL,
      planning_engine = NULL,
      briefing = NULL,
      change_set = NULL,
      pending = list()
    ))
  }
  run_id <- worker$current_run_id
  metadata <- worker$run_metadata[[run_id]]
  briefing <- mi_worker_artifact(worker, "market-briefing-md")
  change_set <- mi_worker_artifact(worker, "market-change-set-json")
  change_content <- change_set@content
  list(
    run_id = run_id,
    status = tempest::tempest_run_status(run),
    bundle_id = metadata$bundle$bundle_id,
    scan_date = metadata$bundle$scan_date,
    request = metadata$request,
    planning_engine = metadata$planning_engine,
    briefing = list(
      markdown = briefing@content,
      headline = change_content$headline,
      summary = change_content$summary,
      implication = change_content$implication,
      materiality = change_content$materiality,
      continuity = change_content$continuity,
      memory_used = change_content$memory_used
    ),
    change_set = change_content,
    pending = mi_worker_pending(worker)
  )
}

mi_sources_frame <- function(sources) {
  mi_rows_frame(
    sources,
    c("id", "title", "uri", "source_type", "published_at")
  )
}

mi_observations_frame <- function(observations) {
  frame <- mi_rows_frame(
    observations,
    c(
      "id",
      "source",
      "observed_at",
      "statement",
      "metric_name",
      "metric_value",
      "metric_unit",
      "signal_type",
      "direction"
    )
  )
  frame$metric_value <- as.numeric(frame$metric_value)
  frame$businesses <- I(lapply(observations, \(x) mi_character(x$businesses)))
  frame$competitors <- I(lapply(observations, \(x) mi_character(x$competitors)))
  frame$downstream_markets <- I(lapply(
    observations,
    \(x) mi_character(x$downstream_markets)
  ))
  frame
}

mi_worker_commit <- function(worker, approval_id, note) {
  run_id <- worker$current_run_id
  if (!is.null(worker$commits[[run_id]])) {
    return(worker$commits[[run_id]])
  }
  run <- mi_worker_current_run(worker)
  if (!identical(tempest::tempest_run_status(run), "succeeded")) {
    stop("Only a succeeded approved scan can enter Graft.")
  }
  content <- mi_worker_artifact(
    worker,
    "market-change-set-json"
  )@content
  metadata <- worker$run_metadata[[run_id]]
  suffix <- mi_id_suffix(run_id)
  assessment_id <- paste0("market:assessment-", suffix)
  action_id <- paste0("market:action-", suffix)
  monitor_run_id <- paste0("market:run-", suffix)
  accepted_at <- mi_iso_time()
  observation_ids <- vapply(
    content$observations,
    `[[`,
    character(1),
    "id"
  )
  source_ids <- vapply(content$sources, `[[`, character(1), "id")
  assessment <- data.frame(
    id = assessment_id,
    headline = content$headline,
    summary = content$summary,
    implication = content$implication,
    materiality = content$materiality,
    confidence = content$confidence,
    status = "accepted",
    valid_from = paste0(content$scan_date, "T00:00:00Z"),
    accepted_at = accepted_at,
    stringsAsFactors = FALSE
  )
  assessment$businesses <- I(list(mi_character(content$businesses)))
  assessment$competitors <- I(list(mi_character(content$competitors)))
  assessment$downstream_markets <- I(list(
    mi_character(content$downstream_markets)
  ))
  assessment$observations <- I(list(observation_ids))
  action <- data.frame(
    id = action_id,
    assessment = assessment_id,
    action_title = content$action$title,
    owner = content$action$owner,
    action_status = "open",
    due_date = content$action$due_date,
    stringsAsFactors = FALSE
  )
  monitor_run <- data.frame(
    id = monitor_run_id,
    title = content$headline,
    scan_date = content$scan_date,
    run_status = "succeeded",
    workflow_run_id = run_id,
    planning_engine = metadata$planning_engine,
    memory_used = isTRUE(content$memory_used),
    assessment = assessment_id,
    approval_id = approval_id,
    reviewer = "local operator",
    note = note,
    stringsAsFactors = FALSE
  )
  monitor_run$source_documents <- I(list(source_ids))
  result <- graft::kg_ingest(
    worker$store,
    graft::kg_batch(
      "graft-market-intelligence",
      producer_version = "1",
      source_run_id = run_id,
      idempotency_key = paste0("market-approved-", run_id),
      metadata = list(
        approval_id = approval_id,
        artifact_id = "market-change-set-json"
      )
    ),
    list(
      SourceDocument = mi_sources_frame(content$sources),
      Observation = mi_observations_frame(content$observations),
      Assessment = assessment,
      IntelligenceAction = action,
      MonitorRun = monitor_run
    )
  )
  worker$commits[[run_id]] <- result
  result
}

mi_worker_resolve <- function(
  worker,
  decision = c("approved", "rejected"),
  note = NULL
) {
  mi_worker_validate(worker)
  decision <- match.arg(decision)
  pending <- mi_worker_pending(worker)
  if (length(pending) != 1L) {
    stop("The current scan must have exactly one pending approval.")
  }
  run_id <- worker$current_run_id
  bundle_id <- worker$run_metadata[[run_id]]$bundle$bundle_id
  approval_id <- names(pending)[[1L]]
  note <- mi_or(
    note,
    if (identical(decision, "approved")) {
      "Approved in the local Market Intelligence Room."
    } else {
      "Rejected in the local Market Intelligence Room."
    }
  )
  tempest::tempest_run_record_approval(
    mi_worker_current_run(worker),
    approval_id,
    decision = decision,
    note = note,
    metadata = list(reviewer = "local operator"),
    resume = TRUE
  )
  if (identical(decision, "approved")) {
    mi_worker_commit(worker, approval_id, note)
  }
  worker$resolved_bundles <- unique(c(
    worker$resolved_bundles,
    bundle_id
  ))
  mi_worker_snapshot(worker)
}

mi_worker_events <- function(worker) {
  run <- mi_worker_current_run(worker)
  if (is.null(run)) {
    return(data.frame())
  }
  events <- tempest::tempest_run_events(run)
  if (length(events) == 0L) {
    return(data.frame())
  }
  data.frame(
    sequence = vapply(events, \(event) event$sequence, integer(1)),
    event = vapply(events, \(event) event$event_type, character(1)),
    status = vapply(events, \(event) event$status, character(1)),
    step = vapply(
      events,
      \(event) mi_or(event$step_id, ""),
      character(1)
    ),
    stringsAsFactors = FALSE
  )
}

mi_worker_progress <- function(worker) {
  mi_worker_validate(worker)
  list(
    total = length(worker$bundle_files),
    resolved = length(worker$resolved_bundles),
    remaining = length(worker$bundle_files) -
      length(worker$resolved_bundles),
    next_bundle = mi_worker_next_bundle(worker)
  )
}
