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
sys.source(
  file.path(
    continuous_intelligence_example_dir,
    "R",
    "scenario.R"
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

run_continuous_intelligence_walkthrough <- function(
  example_dir = continuous_intelligence_example_dir,
  gate = ci_walkthrough_console_gate
) {
  scenario <- ci_scenario_new(example_dir)
  on.exit(ci_scenario_close(scenario), add = TRUE)

  repeat {
    stage <- ci_scenario_stage(scenario)
    proceed <- ci_walkthrough_apply_gate(
      gate,
      stage$id,
      stage$action,
      stage$title,
      stage$detail
    )
    if (!proceed) {
      ci_scenario_stop(scenario)
      return(ci_scenario_result(scenario))
    }
    ci_scenario_advance(scenario)
    if (!identical(scenario$status, "active")) {
      return(ci_scenario_result(scenario))
    }
  }
}
