artifact_checkout <- getOption("graft.experiment.checkout")
artifact_dir <- file.path(artifact_checkout, "tools/experiments/artifacts")
for (file in c("content.R", "backends.R", "fixture.R")) {
  sys.source(file.path(artifact_dir, file), environment())
}
local_artifact_store <- function(backend, .local_envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = .local_envir)
  store <- artifact_store(
    root,
    backend,
    file.path(artifact_dir, "artifact.data-dict.json")
  )
  withr::defer(artifact_close(store), envir = .local_envir)
  store
}
