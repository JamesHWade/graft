test_that("source archives cannot drift from their declared pins", {
  cache <- withr::local_tempdir()
  pin <- fixture_pins$sources$datadict
  writeBin(
    charToRaw("not the pinned source archive"),
    file.path(cache, pin$archive)
  )
  expect_error(
    resolved_runtime_archive(cache, pin),
    class = "graft_resolved_runtime_error"
  )
})

test_that("a CLI build record cannot silently select another source", {
  cache <- withr::local_tempdir()
  record <- jsonlite::read_json(file.path(fixture_cache, "cli.json"))
  record$source_commit <- paste(rep("0", 40L), collapse = "")
  jsonlite::write_json(record, file.path(cache, "cli.json"), auto_unbox = TRUE)
  expect_error(
    resolved_runtime_cli(cache, fixture_pins),
    class = "graft_resolved_runtime_error"
  )
})

test_that("changed CLI bytes fail before they can be executed", {
  cache <- withr::local_tempdir()
  dir.create(file.path(cache, "bin"))
  file.copy(file.path(fixture_cache, "cli.json"), file.path(cache, "cli.json"))
  writeBin(
    charToRaw("unqualified executable"),
    file.path(cache, "bin", "data-dict")
  )
  expect_error(
    resolved_runtime_cli(cache, fixture_pins),
    class = "graft_resolved_runtime_error"
  )
})
