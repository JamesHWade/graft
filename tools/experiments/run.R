# Run from the repository root after setup.R. No installation or model network.
experiment_home <- Sys.getenv("GRAFT_EXPERIMENT_HOME")
if (nzchar(experiment_home)) {
  source(file.path(experiment_home, "environment.R"))
}
output <- Sys.getenv(
  "GRAFT_EXPERIMENT_OUTPUT",
  tempfile("artifact-memory-evidence-")
)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
output <- normalizePath(output)
Sys.setenv(
  GRAFT_EXPERIMENT_OUTPUT = output,
  GRAFT_SEMANTIC_OUTPUT = file.path(output, "semantics")
)
steps <- c("artifacts", "vocabulary", "semantic-compatibility", "roundtrip")
for (step in steps) {
  cat("\nRunning", step, "\n")
  script <- file.path("tools/experiments", step, "run.R")
  args <- if (step == "vocabulary") {
    file.path(output, "vocabulary")
  } else {
    character()
  }
  callr::rscript(script, cmdargs = args, libpath = .libPaths(), show = TRUE)
}
jsonlite::write_json(
  list(
    completed = steps,
    packages = lapply(
      c(
        "graft",
        "commons",
        "ellmer",
        "datadict",
        "shinychat",
        "duckdb",
        "testthat"
      ),
      function(pkg) {
        list(package = pkg, version = as.character(utils::packageVersion(pkg)))
      }
    ),
    R = R.version.string,
    data_dict = datadict::dd_run("--version")$output
  ),
  file.path(output, "suite.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)
cat("\nAll experiment commands completed. Evidence:", output, "\n")
