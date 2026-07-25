market_intelligence_example_path <- function(...) {
  source_path <- testthat::test_path(
    "..",
    "..",
    "inst",
    "examples",
    "market-intelligence",
    ...
  )
  if (file.exists(source_path) || dir.exists(source_path)) {
    return(source_path)
  }
  system.file(
    "examples",
    "market-intelligence",
    ...,
    package = "graft",
    mustWork = TRUE
  )
}

market_intelligence_runtime_available <- function() {
  required_packages <- c(
    "bsicons",
    "bslib",
    "dsprrr",
    "ellmer",
    "shiny",
    "tempest"
  )
  if (
    getRversion() < "4.3.0" ||
      !all(
        vapply(
          required_packages,
          requireNamespace,
          logical(1),
          quietly = TRUE
        )
      )
  ) {
    return(FALSE)
  }
  required_tempest <- c(
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
  all(required_tempest %in% getNamespaceExports("tempest"))
}

local_market_intelligence_environment <- function(include_app = FALSE) {
  environment <- new.env(parent = globalenv())
  files <- c(
    file.path("R", "planner.R"),
    file.path("R", "workflow.R"),
    file.path("R", "worker.R")
  )
  if (include_app) {
    files <- c(
      files,
      file.path("app", "R", "presentation.R"),
      file.path("app", "R", "server.R")
    )
  }
  for (path in files) {
    sys.source(
      market_intelligence_example_path(path),
      envir = environment
    )
  }
  environment
}

local_market_intelligence_worker <- function(environment) {
  worker <- environment$mi_worker_new(
    market_intelligence_example_path()
  )
  withr::defer(
    environment$mi_worker_close(worker),
    envir = parent.frame()
  )
  worker
}
