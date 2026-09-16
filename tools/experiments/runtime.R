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

experiment_check_sources <- function(pins, actual) {
  mismatches <- vapply(
    pins,
    function(pin) {
      description <- actual[[pin$package]]
      if (!is.list(description) || !identical(description$RemoteSha, pin$sha)) {
        pin$package
      } else {
        NA_character_
      }
    },
    character(1)
  )
  mismatches <- mismatches[!is.na(mismatches)]
  if (length(mismatches)) {
    stop(
      "Experiment source pin mismatch or missing RemoteSha: ",
      paste(mismatches, collapse = ", "),
      ". Install the pinned sources with setup.R before running experiments.",
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
  pins <- jsonlite::read_json("tools/experiments/pins.json")$packages
  descriptions <- lapply(pins, \(pin) utils::packageDescription(pin$package))
  names(descriptions) <- vapply(pins, \(pin) pin$package, character(1))
  experiment_check_sources(pins, descriptions)
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

experiment_check_cli <- function(attestation, pins, binary) {
  if (
    !identical(attestation$source_pins, pins) ||
      !identical(
        attestation$cli,
        paste("data-dict", pins$data_dict_cli_version)
      ) ||
      !is.character(attestation$cli_sha256) ||
      length(attestation$cli_sha256) != 1L ||
      !file.exists(binary) ||
      !identical(unname(cli::hash_file_sha256(binary)), attestation$cli_sha256)
  ) {
    stop(
      "data-dict CLI does not match the setup attestation. Run setup.R again.",
      call. = FALSE
    )
  }
}

experiment_prepare <- function(fts = FALSE) {
  experiment_home <- Sys.getenv("GRAFT_EXPERIMENT_HOME")
  attestation_path <- file.path(experiment_home, "versions.json")
  if (!nzchar(experiment_home) || !file.exists(attestation_path)) {
    stop(
      "Set GRAFT_EXPERIMENT_HOME to an environment attested by setup.R.",
      call. = FALSE
    )
  }
  source(file.path(experiment_home, "environment.R"))
  snapshot <- experiment_snapshot()
  experiment_check_cli(
    jsonlite::read_json(attestation_path),
    jsonlite::read_json("tools/experiments/pins.json"),
    datadict::dd_path()
  )
  if (fts) {
    experiment_fts(snapshot$fts_version)
  }
  invisible(snapshot)
}
