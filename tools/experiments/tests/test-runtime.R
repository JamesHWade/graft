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

test_that("Graft attestation rejects changed source and replaced installed code", {
  checkout <- withr::local_tempdir()
  installed <- withr::local_tempdir()
  dir.create(file.path(checkout, "R"))
  source <- file.path(checkout, "R", "graft.R")
  payload <- file.path(installed, "graft.rdb")
  writeLines("original source", source)
  writeLines("original installed code", payload)
  attestation <- list(
    graft = list(
      source_sha256 = experiment_graft_sources(checkout),
      installed_sha256 = experiment_tree_digest(installed)
    )
  )
  expect_no_error(experiment_check_graft(attestation, checkout, installed))
  writeLines("changed source without a version bump", source)
  expect_error(
    experiment_check_graft(attestation, checkout, installed),
    "Graft checkout or installed build changed",
    class = "simpleError"
  )
  writeLines("original source", source)
  writeLines("replacement installed code with the same version", payload)
  expect_error(
    experiment_check_graft(attestation, checkout, installed),
    "Graft checkout or installed build changed",
    class = "simpleError"
  )
})

test_that("CLI attestation binds exact bytes and the declared source pins", {
  binary <- withr::local_tempfile()
  writeBin(charToRaw("data-dict 0.0.3 original build"), binary)
  pins <- list(data_dict_cli_version = "0.0.3", source = "expected commit")
  attestation <- list(
    source_pins = pins,
    cli = "data-dict 0.0.3",
    cli_sha256 = unname(cli::hash_file_sha256(binary))
  )
  expect_no_error(experiment_check_cli(attestation, pins, binary))
  writeBin(charToRaw("data-dict 0.0.3 different build"), binary)
  expect_error(
    experiment_check_cli(attestation, pins, binary),
    "does not match the setup attestation",
    class = "simpleError"
  )
  attestation$cli_sha256 <- unname(cli::hash_file_sha256(binary))
  attestation$source_pins$source <- "different commit"
  expect_error(
    experiment_check_cli(attestation, pins, binary),
    "does not match the setup attestation",
    class = "simpleError"
  )
})

test_that("runners reject manually prepared environments without attestation", {
  withr::local_envvar(GRAFT_EXPERIMENT_HOME = "")
  expect_error(
    experiment_prepare(),
    "environment attested by setup.R",
    class = "simpleError"
  )
})

test_that("standalone context runners reject an empty FTS cache before execution", {
  original_home <- Sys.getenv("GRAFT_EXPERIMENT_HOME")
  for (runner in c("vocabulary", "roundtrip")) {
    cache <- withr::local_tempdir()
    prepared <- withr::local_tempdir()
    file.copy(file.path(original_home, "versions.json"), prepared)
    writeLines(
      c(
        paste0(".libPaths(", paste(deparse(.libPaths()), collapse = ""), ")"),
        paste0(
          "Sys.setenv(DATA_DICT = ",
          encodeString(datadict::dd_path(), quote = '"'),
          ")"
        ),
        paste0("options(duckdb.home = ", encodeString(cache, quote = '"'), ")"),
        paste0(
          "Sys.setenv(DUCKDB_R_HOME = ",
          encodeString(cache, quote = '"'),
          ")"
        )
      ),
      file.path(prepared, "environment.R")
    )
    result <- callr::r(
      function(checkout, runner, prepared) {
        setwd(checkout)
        Sys.setenv(GRAFT_EXPERIMENT_HOME = prepared)
        tryCatch(
          {
            source(file.path("tools/experiments", runner, "run.R"))
            "unexpected success"
          },
          error = conditionMessage
        )
      },
      args = list(experiment_checkout, runner, prepared),
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
