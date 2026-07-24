cw_tempest_exports <- function() {
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

cw_require_runtime <- function() {
  packages <- c("dsprrr", "ellmer", "graft", "jsonlite", "tempest")
  missing <- packages[
    !vapply(packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing) > 0L) {
    stop(
      "Install the coworker runtime dependencies: ",
      paste(missing, collapse = ", ")
    )
  }
  unavailable <- setdiff(
    cw_tempest_exports(),
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

cw_default_data_dir <- function() {
  configured <- getOption("graft.coworker.data_dir")
  if (!is.null(configured)) {
    return(path.expand(cw_text(configured, "graft.coworker.data_dir")))
  }
  from_environment <- Sys.getenv("GRAFT_COWORKER_HOME", unset = "")
  if (nzchar(from_environment)) {
    return(path.expand(from_environment))
  }
  file.path(tools::R_user_dir("graft", "data"), "coworker")
}

cw_run_id <- function() {
  paste0(
    "coworker-",
    format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"),
    "-",
    sprintf("%06d", sample.int(999999L, 1L))
  )
}

cw_id_suffix <- function(value) {
  value <- tolower(cw_text(value, "id"))
  value <- gsub("[^a-z0-9._~-]+", "-", value)
  gsub("(^-+|-+$)", "", value)
}

cw_iso_time <- function(value = Sys.time()) {
  format(
    as.POSIXct(value, tz = "UTC"),
    "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  )
}

cw_worker_new <- function(example_dir, data_dir = cw_default_data_dir()) {
  cw_require_runtime()
  example_dir <- normalizePath(example_dir, mustWork = TRUE)
  data_dir <- path.expand(cw_text(data_dir, "data_dir"))
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
  output_dir <- file.path(data_dir, "deliverables")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  schema <- graft::kg_schema(
    file.path(example_dir, "schema", "coworker.graft.json")
  )
  store_path <- file.path(data_dir, "coworker.duckdb")
  store <- graft::kg_connect_duckdb(schema, store_path)
  initialized <- FALSE
  on.exit(
    {
      if (!initialized) {
        graft::kg_disconnect(store)
      }
    },
    add = TRUE
  )
  graft::kg_init(store)
  bundle <- cw_read_json(
    file.path(example_dir, "corpus", "project-atlas.json")
  )
  workspace <- data.frame(
    id = bundle$workspace$id,
    name = bundle$workspace$name,
    description = bundle$workspace$description,
    stringsAsFactors = FALSE
  )
  sources <- data.frame(
    id = vapply(bundle$sources, `[[`, character(1), "id"),
    workspace = rep(bundle$workspace$id, length(bundle$sources)),
    title = vapply(bundle$sources, `[[`, character(1), "title"),
    source_kind = vapply(
      bundle$sources,
      `[[`,
      character(1),
      "source_kind"
    ),
    uri = vapply(bundle$sources, `[[`, character(1), "uri"),
    content = vapply(bundle$sources, `[[`, character(1), "content"),
    content_hash = vapply(
      bundle$sources,
      `[[`,
      character(1),
      "content_hash"
    ),
    observed_at = vapply(
      bundle$sources,
      `[[`,
      character(1),
      "observed_at"
    ),
    stringsAsFactors = FALSE
  )
  invisible(graft::kg_ingest(
    store,
    graft::kg_batch(
      "graft-coworker",
      producer_version = "1",
      idempotency_key = paste0(
        "coworker-baseline-",
        bundle$workspace$id
      )
    ),
    list(
      CoworkerWorkspace = workspace,
      SourceSnapshot = sources
    )
  ))

  worker <- new.env(parent = emptyenv())
  worker$example_dir <- example_dir
  worker$data_dir <- normalizePath(data_dir, mustWork = TRUE)
  worker$output_dir <- normalizePath(output_dir, mustWork = TRUE)
  worker$store <- store
  worker$store_path <- store_path
  worker$bundle <- bundle
  worker$session_id <- paste0("coworker:session-", cw_id_suffix(cw_run_id()))
  worker$started_at <- cw_iso_time()
  worker$current_run_id <- NULL
  worker$runs <- list()
  worker$run_metadata <- list()
  worker$commits <- list()
  worker$closed <- FALSE
  class(worker) <- "cw_worker"
  initialized <- TRUE
  worker
}

cw_worker_validate <- function(worker) {
  if (!inherits(worker, "cw_worker")) {
    stop("`worker` must be a Graft Coworker worker.")
  }
  if (isTRUE(worker$closed)) {
    stop("The Graft Coworker worker is closed.")
  }
  invisible(worker)
}

cw_worker_close <- function(worker) {
  if (!inherits(worker, "cw_worker") || isTRUE(worker$closed)) {
    return(invisible(NULL))
  }
  graft::kg_disconnect(worker$store)
  worker$closed <- TRUE
  invisible(NULL)
}

cw_worker_current_run <- function(worker) {
  cw_worker_validate(worker)
  if (is.null(worker$current_run_id)) {
    return(NULL)
  }
  worker$runs[[worker$current_run_id]]
}

cw_worker_memory_context <- function(worker) {
  cw_worker_validate(worker)
  memories <- graft::kg_records(worker$store, "Memory") |>
    dplyr::collect()
  if (nrow(memories) == 0L) {
    return("No accepted workspace memory yet.")
  }
  memories <- utils::tail(memories, 10L)
  paste(
    paste0(
      "- ",
      memories$key,
      ": ",
      memories$content,
      " (accepted ",
      memories$accepted_at,
      ")"
    ),
    collapse = "\n"
  )
}

cw_planner_engine <- function(planner) {
  cw_or(planner$config$engine, class(planner)[[1L]])
}

cw_worker_prepare <- function(worker, request, planner = NULL) {
  cw_worker_validate(worker)
  request <- cw_text(request, "request")
  current <- cw_worker_current_run(worker)
  if (
    !is.null(current) &&
      identical(tempest::tempest_run_status(current), "awaiting_approval")
  ) {
    stop(
      paste(
        "Resolve the current approval before starting another outcome.",
        "This keeps each reviewed artifact bound to one request."
      )
    )
  }
  planner <- cw_or(planner, cw_reference_planner(worker$bundle))
  run_id <- cw_run_id()
  started_at <- cw_iso_time()
  run <- cw_run_workflow(
    request = request,
    planner = planner,
    source_bundle = worker$bundle,
    accepted_memory = cw_worker_memory_context(worker),
    output_dir = worker$output_dir,
    run_id = run_id
  )
  worker$runs[[run_id]] <- run
  worker$run_metadata[[run_id]] <- list(
    request = request,
    started_at = started_at,
    planning_engine = cw_planner_engine(planner)
  )
  worker$current_run_id <- run_id
  cw_worker_snapshot(worker)
}

cw_worker_pending <- function(worker) {
  run <- cw_worker_current_run(worker)
  if (is.null(run)) {
    return(list())
  }
  tempest::tempest_run_approvals(run, status = "pending")
}

cw_worker_artifact <- function(worker, artifact_id) {
  run <- cw_worker_current_run(worker)
  if (is.null(run)) {
    return(NULL)
  }
  tempest::tempest_run_artifact(run, artifact_id)
}

cw_worker_snapshot <- function(worker) {
  cw_worker_validate(worker)
  run <- cw_worker_current_run(worker)
  if (is.null(run)) {
    return(list(
      run_id = NULL,
      status = "ready",
      request = NULL,
      plan = NULL,
      deliverable = NULL,
      pending = list(),
      exported_path = NULL
    ))
  }
  run_id <- worker$current_run_id
  plan <- cw_worker_artifact(worker, "coworker-work-plan-json")
  deliverable <- cw_worker_artifact(
    worker,
    "coworker-outcome-package-md"
  )
  list(
    run_id = run_id,
    status = tempest::tempest_run_status(run),
    request = worker$run_metadata[[run_id]]$request,
    plan = plan@content,
    deliverable = deliverable@content,
    pending = cw_worker_pending(worker),
    exported_path = cw_or(deliverable@metadata$exported_path, NULL)
  )
}

cw_worker_commit <- function(worker, approval_id, note) {
  run_id <- worker$current_run_id
  if (!is.null(worker$commits[[run_id]])) {
    return(worker$commits[[run_id]])
  }
  run <- cw_worker_current_run(worker)
  if (!identical(tempest::tempest_run_status(run), "succeeded")) {
    stop("Only a succeeded approved run can enter Graft.")
  }
  plan <- tempest::tempest_run_artifact(
    run,
    "coworker-work-plan-json"
  )
  deliverable <- tempest::tempest_run_artifact(
    run,
    "coworker-outcome-package-md"
  )
  metadata <- worker$run_metadata[[run_id]]
  suffix <- cw_id_suffix(run_id)
  run_record_id <- paste0("coworker:run-", suffix)
  deliverable_id <- paste0("coworker:deliverable-", suffix)
  approval_record_id <- paste0("coworker:approval-", suffix)
  memory_id <- paste0("coworker:memory-", suffix)
  completed_at <- cw_iso_time()
  source_ids <- cw_source_ids(worker$bundle)
  work_session <- data.frame(
    id = worker$session_id,
    workspace = worker$bundle$workspace$id,
    title = paste(worker$bundle$workspace$name, "coworker session"),
    started_at = worker$started_at,
    stringsAsFactors = FALSE
  )
  work_run <- data.frame(
    id = run_record_id,
    session = worker$session_id,
    workspace = worker$bundle$workspace$id,
    title = plan@content$title,
    requested_outcome = metadata$request,
    status = "succeeded",
    workflow_run_id = run_id,
    planning_engine = metadata$planning_engine,
    summary = plan@content$summary,
    started_at = metadata$started_at,
    completed_at = completed_at,
    stringsAsFactors = FALSE
  )
  work_run$source_snapshots <- I(list(source_ids))
  deliverable_record <- data.frame(
    id = deliverable_id,
    run = run_record_id,
    workspace = worker$bundle$workspace$id,
    title = plan@content$title,
    summary = plan@content$summary,
    status = "succeeded",
    media_type = "text/markdown",
    file_path = deliverable@metadata$exported_path,
    content_hash = paste0(
      "sha256:",
      digest::digest(
        deliverable@content,
        algo = "sha256",
        serialize = FALSE
      )
    ),
    completed_at = completed_at,
    stringsAsFactors = FALSE
  )
  approval <- data.frame(
    id = approval_record_id,
    run = run_record_id,
    deliverable = deliverable_id,
    workspace = worker$bundle$workspace$id,
    approval_id = approval_id,
    decision = "approved",
    reviewer = "local operator",
    decided_at = completed_at,
    note = note,
    stringsAsFactors = FALSE
  )
  memory <- data.frame(
    id = memory_id,
    run = run_record_id,
    workspace = worker$bundle$workspace$id,
    key = paste0("accepted-outcome-", suffix),
    content = plan@content$summary,
    scope = "workspace",
    accepted_at = completed_at,
    stringsAsFactors = FALSE
  )
  memory$source_snapshots <- I(list(source_ids))
  result <- graft::kg_ingest(
    worker$store,
    graft::kg_batch(
      "graft-coworker",
      producer_version = "1",
      source_run_id = run_id,
      idempotency_key = paste0("coworker-approved-", run_id),
      metadata = list(
        approval_id = approval_id,
        artifact_id = "coworker-outcome-package-md"
      )
    ),
    list(
      WorkSession = work_session,
      WorkRun = work_run,
      Deliverable = deliverable_record,
      ApprovalDecision = approval,
      Memory = memory
    )
  )
  worker$commits[[run_id]] <- result
  result
}

cw_worker_resolve <- function(
  worker,
  decision = c("approved", "rejected"),
  note = NULL
) {
  cw_worker_validate(worker)
  decision <- match.arg(decision)
  pending <- cw_worker_pending(worker)
  if (length(pending) != 1L) {
    stop("The current run must have exactly one pending approval.")
  }
  approval_id <- names(pending)[[1L]]
  note <- cw_or(
    note,
    if (identical(decision, "approved")) {
      "Approved in the local Graft Coworker."
    } else {
      "Rejected in the local Graft Coworker."
    }
  )
  tempest::tempest_run_record_approval(
    cw_worker_current_run(worker),
    approval_id,
    decision = decision,
    note = note,
    metadata = list(reviewer = "local operator"),
    resume = TRUE
  )
  if (identical(decision, "approved")) {
    cw_worker_commit(worker, approval_id, note)
  }
  cw_worker_snapshot(worker)
}

cw_worker_records <- function(worker, class) {
  cw_worker_validate(worker)
  graft::kg_records(worker$store, class) |>
    dplyr::collect()
}

cw_worker_recall <- function(worker, query, limit = 5L) {
  cw_worker_validate(worker)
  graft::kg_find(
    worker$store,
    cw_text(query, "query"),
    class = "Memory",
    limit = limit
  )
}

cw_worker_events <- function(worker) {
  run <- cw_worker_current_run(worker)
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
      \(event) cw_or(event$step_id, ""),
      character(1)
    ),
    stringsAsFactors = FALSE
  )
}
