local_vocabulary <- function(version = "v1", envir = parent.frame()) {
  skip_if_not_installed("datadict")
  available <- nzchar(datadict::dd_path(check = FALSE))
  if (identical(Sys.getenv("GRAFT_REQUIRE_VOCABULARY"), "true") && !available) {
    stop("Vocabulary integration requires the pinned data-dict binary")
  }
  skip_if_not(available, "data-dict binary is unavailable")
  path <- withr::local_tempdir(.local_envir = envir)
  source <- system.file("examples", "vocabulary", version, package = "graft")
  file.copy(list.files(source, full.names = TRUE), path)
  store <- graft_artifact_store(file.path(path, "artifacts"), create = TRUE)
  list(path = file.path(path, "bindings.json"), store = store)
}
