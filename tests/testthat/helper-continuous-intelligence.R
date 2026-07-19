continuous_intelligence_example_path <- function(...) {
  source_path <- testthat::test_path(
    "..",
    "..",
    "inst",
    "examples",
    "continuous-intelligence",
    ...
  )
  if (file.exists(source_path) || dir.exists(source_path)) {
    return(source_path)
  }
  system.file(
    "examples",
    "continuous-intelligence",
    ...,
    package = "graft",
    mustWork = TRUE
  )
}

continuous_intelligence_tempest_available <- function() {
  if (!requireNamespace("tempest", quietly = TRUE)) {
    return(FALSE)
  }
  required <- c(
    "tempest_artifact_representation",
    "tempest_builtin_operation_registry",
    "tempest_deliverable_spec",
    "tempest_expert",
    "tempest_generate_deliverable",
    "tempest_objective",
    "tempest_run_approvals",
    "tempest_run_artifact",
    "tempest_run_record_approval",
    "tempest_run_status",
    "tempest_run_workflow",
    "tempest_workflow_spec",
    "tempest_workflow_step"
  )
  all(required %in% getNamespaceExports("tempest"))
}

local_continuous_intelligence_environment <- function() {
  environment <- new.env(parent = globalenv())
  sys.source(
    continuous_intelligence_example_path("R", "host.R"),
    envir = environment
  )
  sys.source(
    continuous_intelligence_example_path("R", "blue-sky.R"),
    envir = environment
  )
  environment
}

local_continuous_intelligence_store <- function(environment) {
  schema <- kg_schema(
    continuous_intelligence_example_path(
      "schema",
      "blue-sky.graft.json"
    )
  )
  path <- tempfile("continuous-intelligence-", fileext = ".duckdb")
  store <- kg_connect_duckdb(schema, path)
  kg_init(store)
  withr::defer(
    {
      kg_disconnect(store)
      unlink(path)
    },
    envir = parent.frame()
  )
  baseline <- jsonlite::fromJSON(
    continuous_intelligence_example_path("corpus", "baseline.json")
  )
  kg_ingest(
    store,
    kg_batch(
      "continuous-intelligence-test",
      idempotency_key = "baseline"
    ),
    baseline
  )
  store
}

continuous_intelligence_run_signal_day <- function(
  environment,
  profile,
  store,
  date,
  corpus_file
) {
  monitor_id <- paste0("blue-sky-monitor-", date)
  review_id <- paste0("blue-sky-review-", date)
  daily_bundle <- environment$ci_read_json(
    continuous_intelligence_example_path("corpus", corpus_file)
  )
  monitor <- environment$ci_run_monitor(
    profile,
    daily_bundle,
    store,
    monitor_id
  )
  review <- environment$ci_run_knowledge_review(
    monitor,
    monitor_id,
    review_id
  )
  list(
    monitor_id = monitor_id,
    review_id = review_id,
    monitor = monitor,
    review = review
  )
}
