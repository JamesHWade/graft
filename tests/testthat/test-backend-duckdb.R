test_that("DuckDB lock errors are recognized", {
  lock <- simpleError(paste(
    "IO Error: Could not set lock on file \"a.duckdb\":",
    "Conflicting lock is held in R (PID 1)"
  ))
  expect_identical(is_duckdb_lock_error(lock), TRUE)
  expect_identical(is_duckdb_lock_error(simpleError("disk full")), FALSE)
})

test_that("a store held by another process signals graft_store_busy", {
  skip_on_cran()
  rscript <- file.path(R.home("bin"), "Rscript")
  skip_if_not(file.exists(rscript))
  directory <- withr::local_tempdir()
  path <- file.path(directory, "held.duckdb")
  ready <- file.path(directory, "ready")
  holder <- sprintf(
    paste0(
      "con <- DBI::dbConnect(duckdb::duckdb(), dbdir = '%s'); ",
      "writeLines('ok', '%s'); Sys.sleep(20)"
    ),
    path,
    ready
  )
  system2(
    rscript,
    c("-e", shQuote(holder)),
    wait = FALSE,
    stdout = FALSE,
    stderr = FALSE
  )
  for (i in seq_len(100)) {
    if (file.exists(ready)) {
      break
    }
    Sys.sleep(0.1)
  }
  skip_if_not(file.exists(ready), "The holding process did not start.")

  schema <- graft_schema(system.file(
    "extdata",
    "team-directory.data-dict.json",
    package = "graft",
    mustWork = TRUE
  ))
  expect_error(
    graft_open(schema, path, okf = "disabled"),
    class = "graft_store_busy"
  )
  expect_error(
    graft_open(schema, path, read_only = TRUE, okf = "disabled"),
    class = "graft_store_busy"
  )
})
