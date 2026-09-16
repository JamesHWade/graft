test_that("dependency snapshots reject missing packages and version drift", {
  expect_error(
    experiment_check_versions(list(example = "1.0.0"), list()),
    "snapshot mismatch: example",
    class = "simpleError"
  )
  expect_error(
    experiment_check_versions(list(example = "1.0.0"), list(example = "1.0.1")),
    "snapshot mismatch: example",
    class = "simpleError"
  )
  expect_no_error(experiment_check_versions(
    list(example = "0.1-6"),
    list(example = "0.1.6")
  ))
})

test_that("development builds require matching source identity despite equal versions", {
  pins <- list(list(package = "example", sha = strrep("a", 40)))
  description <- list(Version = "0.1.0.9000", RemoteSha = strrep("b", 40))
  expect_error(
    experiment_check_sources(pins, list(example = description)),
    "source pin mismatch or missing RemoteSha: example",
    class = "simpleError"
  )
  description$RemoteSha <- NULL
  expect_error(
    experiment_check_sources(pins, list(example = description)),
    "source pin mismatch or missing RemoteSha: example",
    class = "simpleError"
  )
  description$RemoteSha <- pins[[1]]$sha
  expect_no_error(experiment_check_sources(pins, list(example = description)))
})

test_that("standalone context runners reject an empty FTS cache before execution", {
  for (runner in c("vocabulary", "roundtrip")) {
    cache <- withr::local_tempdir()
    result <- callr::r(
      function(checkout, runner, cache) {
        setwd(checkout)
        Sys.setenv(GRAFT_EXPERIMENT_HOME = "", DUCKDB_R_HOME = cache)
        options(duckdb.home = NULL)
        tryCatch(
          {
            source(file.path("tools/experiments", runner, "run.R"))
            "unexpected success"
          },
          error = conditionMessage
        )
      },
      args = list(experiment_checkout, runner, cache),
      libpath = .libPaths()
    )
    expect_match(
      result,
      "provision the recorded DuckDB FTS extension",
      fixed = TRUE
    )
    expect_length(
      list.files(cache, pattern = "duckdb_extension", recursive = TRUE),
      0L
    )
  }
})
