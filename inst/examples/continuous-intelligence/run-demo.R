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
source(file.path(example_dir, "R", "scenario.R"))

run_continuous_intelligence_demo <- function(example_dir) {
  scenario <- ci_scenario_new(example_dir)
  on.exit(ci_scenario_close(scenario), add = TRUE)

  while (identical(scenario$status, "active")) {
    stage <- ci_scenario_stage(scenario)
    if (identical(stage$format, "markdown")) {
      cat(stage$detail, "\n\n")
    }
    if (identical(stage$id, "decision-approval")) {
      cat("# Promoted workflow\n\n", stage$detail, "\n\n", sep = "")
    }
    ci_scenario_advance(scenario)
  }

  result <- ci_scenario_result(scenario)
  list(
    monitor_runs = result$monitor_runs,
    review_runs = result$review_runs,
    decision_run = result$decision_run,
    promotion_record = result$promotion_record,
    assessment_count = result$assessment_count,
    decision_count = result$decision_count
  )
}

continuous_intelligence_demo <- run_continuous_intelligence_demo(
  example_dir
)
