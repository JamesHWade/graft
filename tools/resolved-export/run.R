# Offline source-only conformance. Package installation is never performed here.
run_resolved_fixture <- function(args) {
  valid <- length(args) %in% c(2L, 4L) && args[[1L]] == "--cache"
  if (!valid || (length(args) == 4L && args[[3L]] != "--output")) {
    stop(
      "Usage: Rscript --vanilla tools/resolved-export/run.R --cache CACHE [--output EMPTY_DIRECTORY]"
    )
  }
  script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  fixture <- dirname(normalizePath(script))
  source(file.path(fixture, "runtime.R"), local = TRUE)
  pins <- jsonlite::read_json(file.path(fixture, "pins.json"))
  cache <- normalizePath(args[[2L]], mustWork = TRUE)
  archives <- lapply(pins$sources, \(pin) resolved_runtime_archive(cache, pin))
  cli <- resolved_runtime_cli(cache, pins)
  extraction <- tempfile("resolved-source-")
  dir.create(extraction)
  on.exit(unlink(extraction, recursive = TRUE), add = TRUE)
  for (name in names(pins$sources)) {
    root <- resolved_runtime_unpack(
      archives[[name]],
      file.path(extraction, name)
    )
    pkgload::load_all(
      file.path(root, pins$sources[[name]]$package_path),
      quiet = TRUE
    )
    cat(name, pins$sources[[name]]$commit, "loaded from verified archive\n")
  }
  versions <- resolved_runtime_versions(pins)
  evidence <- if (length(args) == 4L) {
    args[[4L]]
  } else {
    tempfile("resolved-evidence-")
  }
  if (
    dir.exists(evidence) &&
      length(list.files(evidence, all.files = TRUE, no.. = TRUE))
  ) {
    resolved_runtime_abort("Evidence directory must be empty.")
  }
  dir.create(evidence, recursive = TRUE, showWarnings = FALSE)
  evidence <- normalizePath(evidence, mustWork = TRUE)
  withr::local_envvar(c(
    DATA_DICT = cli$path,
    NOT_CRAN = "true",
    TESTTHAT_PARALLEL = "FALSE"
  ))
  env <- new.env(parent = globalenv())
  env$fixture_dir <- fixture
  env$evidence_dir <- evidence
  env$fixture_cache <- cache
  env$fixture_pins <- pins
  for (file in c("runtime.R", "upstream.R", "contract.R")) {
    sys.source(file.path(fixture, file), env)
  }
  testthat::local_edition(3L)
  results <- testthat::test_dir(
    file.path(fixture, "tests"),
    env = env,
    reporter = "summary",
    stop_on_failure = TRUE,
    stop_on_warning = TRUE
  )
  summary <- as.data.frame(results)
  record <- list(
    status = "passed",
    scope = "pinned public upstream baseline and nonexecuting proposed-interface conformance",
    sources = lapply(pins$sources, \(pin) {
      pin[c("repository", "commit", "sha256")]
    }),
    cli = cli$record,
    versions = versions,
    tests = summary[c(
      "test",
      "passed",
      "failed",
      "error",
      "warning",
      "skipped"
    )],
    proposed_constructor_implemented_upstream = FALSE,
    proposed_selection_executed = FALSE
  )
  jsonlite::write_json(
    record,
    file.path(evidence, "run.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cat("Evidence:", file.path(evidence, "run.json"), "\n")
}

run_resolved_fixture(commandArgs(trailingOnly = TRUE))
