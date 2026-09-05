local_dictionary_store <- function(
  document = NULL,
  .local_envir = parent.frame()
) {
  if (is.null(document)) {
    document <- jsonlite::fromJSON(
      system.file("extdata/team-directory.data-dict.json", package = "graft"),
      simplifyVector = FALSE
    )
  }
  path <- tempfile(fileext = ".json")
  withr::defer(unlink(path), envir = .local_envir)
  writeLines(canonical_json(document), path)
  store <- graft_open(graft_schema(path), okf = "disabled")
  withr::defer(graft_close(store), envir = .local_envir)
  store
}
