example_dir <- if (dir.exists("inst/examples/market-intelligence")) {
  "inst/examples/market-intelligence"
} else {
  system.file(
    "examples",
    "market-intelligence",
    package = "graft",
    mustWork = TRUE
  )
}

for (path in c("planner.R", "workflow.R", "worker.R")) {
  source(file.path(example_dir, "R", path))
}
rm(path)

run_market_intelligence_demo <- function(example_dir) {
  worker <- mi_worker_new(example_dir)
  on.exit(mi_worker_close(worker), add = TRUE)

  first <- mi_worker_prepare(worker)
  cat(first$briefing$markdown, "\n\n")
  cat("Status:", first$status, "\n\n")
  mi_worker_resolve(
    worker,
    "approved",
    note = "Accepted by the provider-free walkthrough."
  )

  second <- mi_worker_prepare(worker)
  cat(second$briefing$markdown, "\n\n")
  cat(
    "Accepted memory changed the second readout:",
    second$briefing$memory_used,
    "\n\n"
  )
  mi_worker_resolve(
    worker,
    "rejected",
    note = "The walkthrough leaves the second thesis uncommitted."
  )

  list(
    accepted_assessments = mi_worker_records(worker, "Assessment"),
    open_actions = mi_worker_records(worker, "IntelligenceAction"),
    monitor_runs = mi_worker_records(worker, "MonitorRun")
  )
}

market_intelligence_demo <- run_market_intelligence_demo(example_dir)
