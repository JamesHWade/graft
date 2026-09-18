local_decision_fixture <- function(envir = parent.frame()) {
  path <- withr::local_tempdir(.local_envir = envir)
  store <- graft_artifact_store(path, create = TRUE)
  source <- graft_artifact_save(
    store,
    "source",
    charToRaw("evidence"),
    "text/plain"
  )
  first <- graft_artifact_save(
    store,
    "report",
    charToRaw("first"),
    "text/plain",
    list(source)
  )
  correction <- graft_artifact_save(
    store,
    "report",
    charToRaw("corrected"),
    "text/plain",
    list(source)
  )
  selection <- graft_artifact_select(store, list(first))
  list(
    store = store,
    first = first,
    source = source,
    selection = selection,
    correction = graft_artifact_select(store, list(correction)),
    request = list(
      store = store,
      stream = "topic",
      key = "review-1",
      expected = NULL,
      selection = selection,
      action = "accept",
      actor = "reviewer",
      reason = "Evidence reviewed",
      purpose = "research"
    )
  )
}

decision_submit <- function(request, ...) {
  do.call(
    graft_artifact_decide,
    utils::modifyList(request, list(...), keep.null = TRUE)
  )
}

decision_journal_files <- function(store) {
  list.files(
    file.path(store$path, "decisions"),
    recursive = TRUE,
    full.names = TRUE
  )
}
