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

experiment_tree_digest <- function(root, paths = ".") {
  root <- normalizePath(root, winslash = "/")
  candidates <- file.path(root, paths)
  files <- unlist(
    lapply(candidates[file.exists(candidates)], function(path) {
      if (dir.exists(path)) {
        list.files(
          path,
          recursive = TRUE,
          full.names = TRUE,
          all.files = TRUE,
          no.. = TRUE
        )
      } else {
        path
      }
    }),
    use.names = FALSE
  )
  # callr children may use a different collation locale from the setup process.
  files <- sort(unique(files), method = "radix")
  hashes <- lapply(files, \(file) unname(cli::hash_file_sha256(file)))
  names(hashes) <- substring(files, nchar(root) + 2L)
  digest::digest(
    jsonlite::toJSON(hashes, auto_unbox = TRUE),
    algo = "sha256",
    serialize = FALSE
  )
}

experiment_graft_sources <- function(checkout = ".") {
  experiment_tree_digest(
    checkout,
    c(
      "DESCRIPTION",
      "NAMESPACE",
      ".Rbuildignore",
      ".Rinstignore",
      "R",
      "src",
      "inst",
      "data",
      "exec",
      "configure",
      "configure.win",
      "cleanup",
      "cleanup.win"
    )
  )
}

experiment_package_digests <- function(pins, locate = find.package) {
  packages <- vapply(pins, \(pin) pin$package, character(1))
  stats::setNames(
    lapply(packages, \(package) experiment_tree_digest(locate(package))),
    packages
  )
}

experiment_check_packages <- function(
  attestation,
  pins,
  locate = find.package
) {
  actual <- experiment_package_digests(pins, locate)
  mismatches <- names(actual)[vapply(
    names(actual),
    \(package) {
      !identical(
        attestation$package_sha256[[package]],
        actual[[package]]
      )
    },
    logical(1)
  )]
  if (length(mismatches)) {
    stop(
      "Installed pinned package changed or has no digest: ",
      paste(mismatches, collapse = ", "),
      ". Run setup.R again.",
      call. = FALSE
    )
  }
}

experiment_check_graft <- function(
  attestation,
  checkout = ".",
  installed = find.package("graft")
) {
  if (
    !identical(
      attestation$graft$source_sha256,
      experiment_graft_sources(checkout)
    ) ||
      !identical(
        attestation$graft$installed_sha256,
        experiment_tree_digest(installed)
      )
  ) {
    stop(
      "Graft checkout or installed build changed. Run setup.R again.",
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
  attestation <- jsonlite::read_json(attestation_path)
  pins <- jsonlite::read_json("tools/experiments/pins.json")
  experiment_check_packages(attestation, pins$packages)
  experiment_check_graft(attestation)
  experiment_check_cli(
    attestation,
    pins,
    datadict::dd_path()
  )
  if (fts) {
    experiment_fts(snapshot$fts_version)
  }
  invisible(snapshot)
}
