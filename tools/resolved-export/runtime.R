# Infrastructure for this source-only fixture, not a Graft package API.
resolved_runtime_abort <- function(message) {
  rlang::abort(message, class = "graft_resolved_runtime_error")
}

resolved_runtime_digest <- function(path) {
  if (!file.exists(path) || dir.exists(path)) {
    resolved_runtime_abort(paste("Missing fixture file:", path))
  }
  digest::digest(file = path, algo = "sha256")
}

resolved_runtime_archive <- function(cache, pin) {
  path <- file.path(cache, pin$archive)
  if (!identical(resolved_runtime_digest(path), pin$sha256)) {
    resolved_runtime_abort(paste(
      "Source archive differs from its pin:",
      pin$repository
    ))
  }
  normalizePath(path, mustWork = TRUE)
}

resolved_runtime_unpack <- function(archive, destination) {
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  utils::untar(archive, exdir = destination)
  roots <- list.dirs(destination, recursive = FALSE, full.names = TRUE)
  if (length(roots) != 1L) {
    resolved_runtime_abort(
      "Expected exactly one root in the verified source archive."
    )
  }
  normalizePath(roots[[1L]], mustWork = TRUE)
}

resolved_runtime_cli <- function(cache, pins) {
  record_path <- file.path(cache, "cli.json")
  if (!file.exists(record_path)) {
    resolved_runtime_abort("CLI build record is missing; run prepare.R first.")
  }
  record <- jsonlite::read_json(record_path, simplifyVector = FALSE)
  expected <- list(
    format = 1L,
    source_commit = pins$sources$datadict$commit,
    source_archive_sha256 = pins$sources$datadict$sha256,
    cli_version = pins$cli_version,
    rust = pins$rust
  )
  for (field in names(expected)) {
    if (!identical(record[[field]], expected[[field]])) {
      resolved_runtime_abort(paste(
        "CLI build record differs from the pin:",
        field
      ))
    }
  }
  binary <- file.path(cache, "bin", "data-dict")
  if (!identical(resolved_runtime_digest(binary), record$binary_sha256)) {
    resolved_runtime_abort("CLI bytes differ from the local build record.")
  }
  result <- processx::run(
    binary,
    "--version",
    error_on_status = FALSE,
    timeout = 10000
  )
  if (
    result$status != 0L || !identical(trimws(result$stdout), pins$cli_version)
  ) {
    resolved_runtime_abort("Prepared CLI does not report the pinned version.")
  }
  list(path = normalizePath(binary, mustWork = TRUE), record = record)
}

resolved_runtime_versions <- function(pins) {
  for (package in c("ellmer", "duckdb")) {
    version <- as.character(utils::packageVersion(package))
    if (!identical(version, pins[[package]])) {
      resolved_runtime_abort(paste(
        package,
        "must be",
        pins[[package]],
        "for this fixture; found",
        version
      ))
    }
  }
  packages <- c(
    "R",
    "commons",
    "datadict",
    "ellmer",
    "duckdb",
    "DBI",
    "jsonlite",
    "testthat"
  )
  versions <- vapply(
    packages,
    function(package) {
      if (package == "R") {
        as.character(getRversion())
      } else {
        as.character(utils::packageVersion(package))
      }
    },
    character(1)
  )
  as.list(versions)
}
