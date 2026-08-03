local_okf_store <- function(env = parent.frame()) {
  directory <- withr::local_tempdir(.local_envir = env)
  path <- file.path(directory, "knowledge.duckdb")
  store <- local_ingest_store(path = path, env = env)
  records <- valid_atomic_records()
  result <- graft_ingest(
    store,
    records,
    graft_provenance(
      producer = "okf-test",
      version = "1.0.0",
      idempotency_key = "initial"
    )
  )
  list(
    store = store,
    records = records,
    result = result,
    path = path
  )
}

okf_fixture_concept <- function(bundle, record_class, record_id) {
  file.path(
    bundle$path,
    "concepts",
    utils::URLencode(record_class, reserved = TRUE),
    paste0(utils::URLencode(record_id, reserved = TRUE), ".md")
  )
}

replace_okf_line <- function(path, old, new) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  replaced <- sub(old, new, lines, fixed = TRUE)
  stopifnot(!identical(lines, replaced))
  writeLines(replaced, path, useBytes = TRUE)
  invisible(path)
}

local_sync_okf <- function(store, env = parent.frame()) {
  directory <- withr::local_tempdir(.local_envir = env)
  kg_sync_okf(store, file.path(directory, "knowledge.okf"))
}
