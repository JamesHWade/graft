local_decision_fixture <- function(envir = parent.frame()) {
  path <- withr::local_tempdir(.local_envir = envir)
  store <- graft_store(path, create = TRUE)
  source <- artifact_save(
    store,
    "source",
    charToRaw("evidence"),
    "text/plain"
  )
  first <- artifact_save(
    store,
    "report",
    charToRaw("first"),
    "text/plain",
    list(source)
  )
  correction <- artifact_save(
    store,
    "report",
    charToRaw("corrected"),
    "text/plain",
    list(source)
  )
  selection <- artifact_select(store, list(first))
  list(
    store = store,
    first = first,
    source = source,
    selection = selection,
    correction = artifact_select(store, list(correction)),
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
    artifact_decide,
    utils::modifyList(request, list(...), keep.null = TRUE)
  )
}

decision_journal_files <- function(store) {
  list.files(
    file.path(store@path, "decisions"),
    recursive = TRUE,
    full.names = TRUE
  )
}

graft_checkout <- function() {
  if (pkgload::is_dev_package("graft")) normalizePath("../..") else NULL
}

# Records `rounds` accepts in `stream`, each naming the head it read, and
# retries when another process moved the head first.
decision_race_worker <- function(
  path,
  stream,
  selection,
  prefix,
  rounds,
  go,
  checkout
) {
  if (!is.null(checkout)) {
    pkgload::load_all(checkout, quiet = TRUE)
  }
  store <- graft::graft_store(path)
  while (!file.exists(go)) {
    Sys.sleep(0.01)
  }
  done <- 0L
  attempts <- 0L
  while (done < rounds && attempts < rounds * 50L) {
    attempts <- attempts + 1L
    head <- graft:::artifact_read_decision(store, stream)
    ok <- tryCatch(
      {
        graft:::artifact_decide(
          store,
          stream = stream,
          key = sprintf("%s-%d", prefix, done + 1L),
          expected = if (is.null(head)) NULL else head$id,
          selection = selection,
          action = "accept",
          actor = prefix,
          reason = "race",
          purpose = "research"
        )
        TRUE
      },
      graft_artifact_error = function(e) FALSE
    )
    if (ok) done <- done + 1L
  }
  done
}
