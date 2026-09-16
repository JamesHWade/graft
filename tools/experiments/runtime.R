# Shared preflight for the suite and every standalone experiment entry point.
experiment_check_versions <- function(expected, actual) {
  mismatches <- names(expected)[vapply(
    names(expected),
    function(package) {
      !identical(
        actual[[package]],
        as.character(package_version(expected[[package]]))
      )
    },
    logical(1)
  )]
  if (length(mismatches)) {
    stop(
      "Experiment dependency snapshot mismatch: ",
      paste(mismatches, collapse = ", "),
      ". Run setup.R; update the snapshot deliberately when changing dependencies.",
      call. = FALSE
    )
  }
}

experiment_snapshot <- function() {
  snapshot <- jsonlite::read_json("tools/experiments/dependency-snapshot.json")
  if (!identical(as.character(getRversion()), snapshot$R_version)) {
    stop(
      "Use R ",
      snapshot$R_version,
      " for the recorded experiment snapshot.",
      call. = FALSE
    )
  }
  actual <- lapply(names(snapshot$packages), function(package) {
    tryCatch(as.character(utils::packageVersion(package)), error = function(e) {
      NULL
    })
  })
  names(actual) <- names(snapshot$packages)
  experiment_check_versions(snapshot$packages, actual)
  snapshot
}

experiment_fts <- function(expected_version) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  fts <- DBI::dbGetQuery(
    con,
    "SELECT installed, extension_version FROM duckdb_extensions() WHERE extension_name = 'fts'"
  )
  if (
    nrow(fts) != 1L ||
      !isTRUE(fts$installed) ||
      !identical(fts$extension_version, expected_version)
  ) {
    stop(
      "Run setup.R to provision the recorded DuckDB FTS extension first.",
      call. = FALSE
    )
  }
}

experiment_prepare <- function(fts = FALSE) {
  experiment_home <- Sys.getenv("GRAFT_EXPERIMENT_HOME")
  if (nzchar(experiment_home)) {
    source(file.path(experiment_home, "environment.R"))
  }
  snapshot <- experiment_snapshot()
  if (fts) {
    experiment_fts(snapshot$fts_version)
  }
  invisible(snapshot)
}
