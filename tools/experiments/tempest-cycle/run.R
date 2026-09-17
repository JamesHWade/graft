source("tools/experiments/runtime.R")
experiment_prepare()
checkout <- normalizePath(".")
output <- file.path(
  Sys.getenv("GRAFT_EXPERIMENT_OUTPUT", tempfile("cycle-")),
  "tempest-cycle"
)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
# Both acceptance and consultation run without Graft for the manifest candidate.
library <- tempfile("cycle-without-graft-")
dir.create(library)
packages <- unique(c(
  "tempest",
  tools::package_dependencies(
    "tempest",
    db = installed.packages(),
    which = c("Depends", "Imports", "LinkingTo"),
    recursive = TRUE
  )[["tempest"]]
))
packages <- setdiff(
  packages,
  c("R", rownames(installed.packages(priority = c("base", "recommended"))))
)
stopifnot(!"graft" %in% packages)
for (package in packages) {
  stopifnot(file.copy(find.package(package), library, recursive = TRUE))
}
observed <- new.env(parent = emptyenv())
options(
  graft.cycle.fixture = list(
    checkout = checkout,
    output = output,
    library = library,
    observed = observed
  )
)
# Tests explicitly orchestrate separate writer and reader processes.
Sys.setenv(TESTTHAT_PARALLEL = "false")
tests <- testthat::test_dir(
  "tools/experiments/tempest-cycle/tests",
  stop_on_failure = TRUE
)
unlink(library, recursive = TRUE)
jsonlite::write_json(
  list(
    outcome = "Direct research acceptance, correction and withdrawal with both metadata drivers",
    assertions = sum(as.data.frame(tests)$passed),
    observations = as.list(observed),
    source_lines = lapply(
      stats::setNames(
        c(
          "tempest-cycle/host.R",
          "tempest-cycle/run.R",
          "artifacts/content.R",
          "artifacts/backends.R"
        ),
        c("host", "runner", "shared_content", "metadata_drivers")
      ),
      function(path) {
        length(readLines(file.path("tools/experiments", path)))
      }
    ),
    scope = "Trusted single-writer host; shipped completed research fixtures; no model requests or production recovery",
    packages = jsonlite::read_json("tools/experiments/pins.json")$packages
  ),
  file.path(output, "results.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)
cat("Tempest acceptance cycle passed. Evidence:", output, "\n")
