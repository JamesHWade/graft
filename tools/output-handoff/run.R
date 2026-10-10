# Source-only, credential-free conformance runner. No package installation.
run_handoff_fixture <- function(args) {
  script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  fixture <- dirname(normalizePath(script))
  graft_source <- normalizePath(file.path(fixture, "../.."))
  core_only <- identical(args, "--core-only")
  if (!core_only && (length(args) != 2L || args[[1L]] != "--sources")) {
    stop(paste(
      "Usage: Rscript tools/output-handoff/run.R --sources CACHE_DIRECTORY",
      "or: Rscript tools/output-handoff/run.R --core-only",
      sep = "\n"
    ))
  }
  pins <- jsonlite::fromJSON(
    file.path(fixture, "pins.json"),
    simplifyVector = FALSE
  )
  fixture_env <- new.env(parent = globalenv())
  fixture_env$graft_source <- graft_source
  if (!core_only) {
    extraction <- tempfile("graft-handoff-sources-")
    dir.create(extraction)
    on.exit(unlink(extraction, recursive = TRUE), add = TRUE)
    for (name in names(pins$sources)) {
      pin <- pins$sources[[name]]
      archive <- normalizePath(
        file.path(args[[2L]], pin$archive),
        mustWork = TRUE
      )
      if (
        !identical(digest::digest(file = archive, algo = "sha256"), pin$sha256)
      ) {
        stop("Source archive digest differs from the pin: ", name)
      }
      destination <- file.path(extraction, name)
      dir.create(destination)
      utils::untar(archive, exdir = destination)
      roots <- list.dirs(destination, recursive = FALSE, full.names = TRUE)
      if (length(roots) != 1L) {
        stop("Expected one source root in archive: ", name)
      }
      source <- normalizePath(file.path(roots[[1L]], pin$package_path))
      fixture_env[[paste0(name, "_source")]] <- source
      pkgload::load_all(source, quiet = TRUE)
      cat(name, pin$commit, "loaded from verified archive\n")
    }
    cat("ellmer", as.character(utils::packageVersion("ellmer")), "\n")
  }
  pkgload::load_all(graft_source, quiet = TRUE)
  sys.source(file.path(fixture, "handoff.R"), fixture_env)
  if (!core_only) {
    sys.source(file.path(fixture, "producers.R"), fixture_env)
  }
  testthat::local_edition(3L)
  withr::local_envvar(c(TESTTHAT_PARALLEL = "FALSE"))
  testthat::test_dir(
    file.path(fixture, "tests"),
    filter = if (core_only) "^handoff$" else NULL,
    env = fixture_env,
    reporter = "summary",
    stop_on_failure = TRUE,
    stop_on_warning = TRUE
  )
}

run_handoff_fixture(commandArgs(trailingOnly = TRUE))
