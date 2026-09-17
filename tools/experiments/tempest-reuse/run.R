source("tools/experiments/runtime.R")
experiment_prepare()
checkout <- normalizePath(".")
for (file in c(
  "artifacts/content.R",
  "artifacts/backends.R",
  "tempest-migration/migration.R",
  "tempest-reuse/reuse.R"
)) {
  source(file.path("tools/experiments", file))
}
output_root <- Sys.getenv("GRAFT_EXPERIMENT_OUTPUT")
handoff_path <- file.path(output_root, "tempest-migration", "handoff.json")
if (!file.exists(handoff_path)) {
  stop("Run tempest-migration/run.R first in the same fresh output directory.")
}
handoff <- artifact_read_json(handoff_path)
target <- file.path(dirname(handoff_path), handoff$target)
historical_handle <- handoff$handle
export <- migration_open(target, historical_handle)
store <- artifact_store(target, "manifest", "unused")
handle <- historical_handle
handle$basis <- artifact_approve(store, list(handle$root), "Tempest research")
inputs <- lapply(c("initial", "correction"), function(name) {
  reuse_input(target, handle, name)
})
names(inputs) <- c("initial", "correction")
output <- file.path(output_root, "tempest-reuse")
dir.create(output)
# Copy only Tempest's required runtime packages, excluding Graft and all optional
# suggestions. A fresh process proves the consumer has no Graft installation.
library <- tempfile("tempest-without-graft-")
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
consumer_run <- function(phase) {
  callr::r(
    function(checkout, target, handle, output, phase) {
      stopifnot(!requireNamespace("graft", quietly = TRUE))
      for (file in c(
        "artifacts/content.R",
        "artifacts/backends.R",
        "tempest-migration/migration.R",
        "tempest-reuse/reuse.R"
      )) {
        source(file.path(checkout, "tools/experiments", file))
      }
      exercise <- switch(
        phase,
        save = reuse_session_save,
        resume = reuse_session_restore
      )
      values <- lapply(c("initial", "unchanged", "correction"), function(name) {
        checkpoint <- if (name == "unchanged") "initial" else name
        exercise(target, handle, checkpoint, file.path(output, name))
      })
      names(values) <- c("initial", "unchanged", "correction")
      list(
        values = values,
        process_id = Sys.getpid(),
        graft_available = requireNamespace("graft", quietly = TRUE),
        graft_loaded = "graft" %in% loadedNamespaces()
      )
    },
    args = list(checkout, target, handle, output, phase),
    libpath = c(library, .Library)
  )
}
saved <- consumer_run("save")
consumer <- consumer_run("resume")
unlink(library, recursive = TRUE)
options(
  graft.experiment.checkout = checkout,
  graft.reuse.fixture = list(
    inputs = inputs,
    sessions = output,
    saved = saved$values,
    consumer = consumer$values,
    save_process = saved,
    resume_process = consumer,
    export = export,
    target = target,
    handle = handle,
    historical_handle = historical_handle,
    graft_available = consumer$graft_available,
    graft_loaded = consumer$graft_loaded
  )
)
tests <- testthat::test_dir(
  "tools/experiments/tempest-reuse/tests",
  stop_on_failure = TRUE
)
result <- list(
  outcome = "Public Tempest artifact input and saved-session reuse without Graft",
  assertions = sum(as.data.frame(tests)$passed),
  graft_available = consumer$graft_available,
  graft_loaded = consumer$graft_loaded,
  retained_sessions = c("initial", "unchanged", "correction"),
  purpose_and_withdrawal_checked = TRUE,
  resume_eligibility_checked = TRUE,
  resumed_selection_verified = TRUE,
  separate_save_resume_processes = TRUE,
  scope = "Admission and cross-run evidence reuse; no new research acceptance or model-generated report",
  packages = jsonlite::read_json("tools/experiments/pins.json")$packages
)
jsonlite::write_json(
  result,
  file.path(output, "results.json"),
  pretty = TRUE,
  auto_unbox = TRUE
)
cat("Tempest artifact reuse passed. Evidence:", output, "\n")
