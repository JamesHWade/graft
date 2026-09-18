# Public application adoption, independent of the experimental metadata drivers.
source("tools/experiments/runtime.R")
experiment_prepare()
output <- file.path(
  Sys.getenv("GRAFT_EXPERIMENT_OUTPUT", tempfile("adoption-")),
  "tempest-artifact-adoption"
)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
example <- new.env()
sys.source(
  system.file("examples", "artifact-research.R", package = "tempest"),
  example
)
observed <- example$artifact_research_example()
stopifnot(
  identical(observed$evidence_records, 4L),
  identical(observed$historical_report_retained, TRUE),
  identical(observed$unchanged_review_is_distinct, TRUE),
  identical(observed$corrected_selection_is_distinct, TRUE),
  identical(observed$withdrawal_blocks_reuse, TRUE),
  identical(observed$retry_preserves_withdrawal, TRUE)
)
jsonlite::write_json(
  list(
    outcome = "Tempest publishes and consults research through public Graft artifacts and decisions",
    observations = observed,
    scope = "Offline completed-product fixtures; trusted local single writer; no production access or erasure claim",
    packages = jsonlite::read_json("tools/experiments/pins.json")$packages
  ),
  file.path(output, "results.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)
cat("Public Tempest artifact adoption passed. Evidence:", output, "\n")
