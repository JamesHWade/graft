# Managed Open Knowledge Format working trees

okf_normalize_path <- function(path) {
  path <- validate_scalar_text(path, "path")
  path <- path.expand(path)
  if (!okf_is_absolute_path(path)) {
    path <- file.path(getwd(), path)
  }
  parent <- dirname(path)
  if (dir.exists(parent)) {
    parent <- normalizePath(parent, winslash = "/", mustWork = TRUE)
  } else {
    parent <- normalizePath(parent, winslash = "/", mustWork = FALSE)
  }
  file.path(parent, basename(path))
}

okf_resolve_path <- function(store, path = NULL) {
  validate_store_backend(store)
  if (!is.null(path)) {
    return(okf_normalize_path(path))
  }
  if (
    identical(store$okf_mode, "managed") &&
      !is.null(store$okf_path)
  ) {
    return(store$okf_path)
  }
  abort_validation_error(
    paste(
      "This store does not have a managed OKF directory.",
      "Supply `path` or connect a file-backed store with `okf = \"managed\"`."
    ),
    field = "path",
    rule = "managed_okf_path",
    observed_value = path
  )
}

okf_current_boundary <- function(store) {
  row <- with_duckdb_error(
    "okf_current_boundary",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT batch_id, commit_order, committed_at FROM ",
        quote_identifier(store$connection, "_graft_batches"),
        " WHERE status = 'committed' ",
        "ORDER BY commit_order DESC, batch_id ASC LIMIT 1"
      )
    )
  )
  if (nrow(row) == 0L) {
    return(list(
      commit_order = NULL,
      batch_id = NULL,
      committed_at = NULL
    ))
  }
  list(
    commit_order = as.numeric(row$commit_order[[1L]]),
    batch_id = row$batch_id[[1L]],
    committed_at = row$committed_at[[1L]]
  )
}

#' Synchronize the managed open-knowledge working tree
#'
#' `graft_sync()` replaces the configured OKF working tree with a deterministic
#' projection of current accepted knowledge. It returns an ordinary summary
#' list and never changes accepted records.
#'
#' @param store An initialized `GraftStore`.
#' @param path Optional destination directory. The default uses the managed
#'   path configured by [graft_open()].
#' @param limit Maximum number of concepts to synchronize.
#'
#' @return An ordinary list summarizing the synchronized bundle.
#' @export
graft_sync <- function(store, path = NULL, limit = 5000L) {
  store <- as_graft_store_internal(store, "store")
  sync_okf_tree(store, path = path, limit = limit)
}

#' Inspect the managed open-knowledge working tree
#'
#' `graft_status()` reports whether the configured OKF working tree is current,
#' modified, stale, missing, unconfigured, or incompatible. Inspection never
#' changes the store or filesystem.
#'
#' @param store An initialized `GraftStore`.
#' @param path Optional OKF directory. The default uses the managed path.
#' @param deep Whether to verify the working tree's content digest.
#'
#' @return An ordinary status list.
#' @export
graft_status <- function(store, path = NULL, deep = TRUE) {
  store <- as_graft_store_internal(store, "store")
  okf_status(store, path = path, deep = deep)
}

sync_okf_tree <- function(store, path = NULL, limit = 5000L) {
  validate_retrieval_store(store)
  if (!is.null(path)) {
    path <- okf_normalize_path(path)
  } else {
    path <- okf_resolve_path(store)
  }
  bundle <- export_okf_bundle(
    store,
    path = path,
    limit = limit,
    overwrite = dir.exists(path)
  )
  store$okf_mode <- "managed"
  store$okf_path <- path
  store$okf_expected <- list(
    batch_id = scalar_character(bundle$as_of_batch_id, ""),
    schema_build_digest = bundle$schema_build_digest,
    bundle_digest = bundle$bundle_digest
  )
  bundle
}

okf_status <- function(store, path = NULL, deep = TRUE) {
  validate_retrieval_store(store)
  deep <- validate_history_flag(deep, "deep")
  configured <- !is.null(path) ||
    (identical(store$okf_mode, "managed") &&
      !is.null(store$okf_path))
  if (!configured) {
    return(new_okf_status(
      status = "unconfigured",
      reason = "No managed OKF directory is configured.",
      path = NULL,
      configured = FALSE
    ))
  }
  path <- if (is.null(path)) {
    store$okf_path
  } else {
    okf_normalize_path(path)
  }
  if (!file.exists(path) && !dir.exists(path)) {
    return(new_okf_status(
      status = "missing",
      reason = "The managed OKF bundle has not been synchronized.",
      path = path
    ))
  }
  if (!dir.exists(path)) {
    return(new_okf_status(
      status = "incompatible",
      reason = "The managed OKF path is not a directory.",
      path = path
    ))
  }

  index <- tryCatch(
    okf_parse_frontmatter(file.path(path, "index.md")),
    error = identity
  )
  if (inherits(index, "error")) {
    return(new_okf_status(
      status = "incompatible",
      reason = conditionMessage(index),
      path = path
    ))
  }
  graft <- index$graft
  if (!is.list(graft) || is.null(names(graft))) {
    return(new_okf_status(
      status = "incompatible",
      reason = "The directory is not a supported Graft OKF bundle.",
      path = path
    ))
  }
  profile <- okf_default(graft$profile, NULL)
  profile_version <- as.character(
    okf_default(graft$profile_version, NA_character_)
  )
  expected_build <- scalar_character(
    store$schema$manifest$fingerprints$build_digest
  )
  expected_structural <- store_schema_digest(store)
  observed_build <- scalar_character(
    graft$schema_build_digest,
    NA_character_
  )
  observed_structural <- scalar_character(
    graft$structural_digest,
    NA_character_
  )
  base_digest <- scalar_character(
    graft$bundle_digest,
    NA_character_
  )
  latest <- okf_current_boundary(store)
  expected_batch <- scalar_character(latest$batch_id, NA_character_)
  observed_batch <- scalar_character(
    graft$as_of_batch_id,
    NA_character_
  )
  common <- list(
    path = path,
    profile_version = profile_version,
    bundle_digest = base_digest,
    expected_batch_id = expected_batch,
    observed_batch_id = observed_batch,
    expected_schema_build_digest = expected_build,
    observed_schema_build_digest = observed_build
  )

  if (
    !identical(profile, "graft-okf") ||
      !identical(profile_version, graft_okf_profile_version)
  ) {
    return(do.call(
      new_okf_status,
      c(
        list(
          status = "incompatible",
          reason = "The directory is not a supported Graft OKF bundle."
        ),
        common
      )
    ))
  }
  if (
    !identical(observed_build, expected_build) ||
      !identical(observed_structural, expected_structural)
  ) {
    return(do.call(
      new_okf_status,
      c(
        list(
          status = "incompatible",
          reason = "The bundle was produced from a different active schema."
        ),
        common
      )
    ))
  }
  if (is.na(base_digest)) {
    return(do.call(
      new_okf_status,
      c(
        list(
          status = "incompatible",
          reason = "The bundle predates managed content digests; resynchronize it."
        ),
        common
      )
    ))
  }
  observed_digest <- if (deep) {
    tryCatch(okf_bundle_digest(path), error = identity)
  } else {
    NA_character_
  }
  if (inherits(observed_digest, "error")) {
    return(do.call(
      new_okf_status,
      c(
        list(
          status = "incompatible",
          reason = conditionMessage(observed_digest)
        ),
        common
      )
    ))
  }
  common$observed_bundle_digest <- observed_digest
  if (deep && !identical(observed_digest, base_digest)) {
    return(do.call(
      new_okf_status,
      c(
        list(
          status = "modified",
          reason = "The OKF working tree differs from its accepted projection."
        ),
        common
      )
    ))
  }
  if (!identical(observed_batch, expected_batch)) {
    return(do.call(
      new_okf_status,
      c(
        list(
          status = "stale",
          reason = "The store has accepted changes since the last synchronization."
        ),
        common
      )
    ))
  }
  if (
    deep &&
      !identical(base_digest, okf_expected_bundle_digest(store, latest))
  ) {
    return(do.call(
      new_okf_status,
      c(
        list(
          status = "modified",
          reason = "The OKF working tree differs from its accepted projection."
        ),
        common
      )
    ))
  }
  do.call(
    new_okf_status,
    c(
      list(
        status = "current",
        reason = "The OKF working tree matches current accepted Graft state."
      ),
      common
    )
  )
}

okf_expected_bundle_digest <- function(store, boundary) {
  batch_id <- scalar_character(boundary$batch_id, "")
  build_digest <- scalar_character(
    store$schema$manifest$fingerprints$build_digest
  )
  cached <- store$okf_expected
  if (
    is.list(cached) &&
      identical(cached$batch_id, batch_id) &&
      identical(cached$schema_build_digest, build_digest) &&
      is.character(cached$bundle_digest) &&
      length(cached$bundle_digest) == 1L &&
      !is.na(cached$bundle_digest)
  ) {
    return(cached$bundle_digest)
  }

  classes <- okf_public_classes(store)
  bundle_schema <- okf_boundary_schema(store, boundary)
  snapshot <- okf_snapshot_records(
    store,
    classes,
    boundary,
    graft_retrieval_limits$okf_concepts
  )
  concepts <- okf_snapshot_concepts(snapshot)
  documents <- okf_bundle_documents(
    bundle_schema,
    concepts,
    boundary,
    classes
  )
  bundle_digest <- okf_documents_digest(documents)
  store$okf_expected <- list(
    batch_id = batch_id,
    schema_build_digest = build_digest,
    bundle_digest = bundle_digest
  )
  bundle_digest
}

new_okf_status <- function(
  status,
  reason,
  path,
  configured = TRUE,
  profile_version = NA_character_,
  bundle_digest = NA_character_,
  observed_bundle_digest = NA_character_,
  expected_batch_id = NA_character_,
  observed_batch_id = NA_character_,
  expected_schema_build_digest = NA_character_,
  observed_schema_build_digest = NA_character_
) {
  list(
    status = status,
    reason = reason,
    path = path,
    configured = configured,
    profile_version = profile_version,
    bundle_digest = bundle_digest,
    observed_bundle_digest = observed_bundle_digest,
    expected_batch_id = expected_batch_id,
    observed_batch_id = observed_batch_id,
    expected_schema_build_digest = expected_schema_build_digest,
    observed_schema_build_digest = observed_schema_build_digest
  )
}

okf_concept_files <- function(path) {
  files <- list.files(
    path,
    pattern = "\\.md$",
    recursive = TRUE,
    full.names = TRUE,
    all.files = TRUE,
    no.. = TRUE
  )
  files[!basename(files) %in% c("index.md", "log.md")]
}

okf_snapshot_bundle <- function(path) {
  source <- normalizePath(path, winslash = "/", mustWork = TRUE)
  entries <- okf_bundle_entries(source, include_directories = TRUE)
  snapshot <- tempfile("graft-okf-snapshot-")
  if (!dir.create(snapshot)) {
    abort_backend_error(
      "Could not create a stable OKF read snapshot.",
      operation = "okf_snapshot_bundle",
      path = snapshot
    )
  }
  complete <- FALSE
  on.exit(
    if (!complete) unlink(snapshot, recursive = TRUE, force = TRUE),
    add = TRUE
  )
  relative <- substring(entries, nchar(source) + 2L)
  info <- file.info(entries)
  directories <- relative[info$isdir]
  directories <- directories[order(
    nchar(directories),
    directories,
    method = "radix"
  )]
  for (directory in directories) {
    destination <- file.path(snapshot, directory)
    if (!dir.create(destination)) {
      abort_backend_error(
        "Could not create a directory in the stable OKF read snapshot.",
        operation = "okf_snapshot_bundle",
        path = destination
      )
    }
  }
  files <- entries[!info$isdir]
  file_relative <- relative[!info$isdir]
  copied <- vapply(
    seq_along(files),
    function(index) {
      file.copy(
        files[[index]],
        file.path(snapshot, file_relative[[index]]),
        overwrite = FALSE,
        copy.mode = FALSE,
        copy.date = FALSE
      )
    },
    logical(1)
  )
  if (!all(copied %in% TRUE)) {
    abort_backend_error(
      "Could not create a complete stable OKF read snapshot.",
      operation = "okf_snapshot_bundle",
      path = files[which(!(copied %in% TRUE))[[1L]]]
    )
  }
  result <- list(
    path = snapshot,
    bundle_digest = okf_bundle_digest(snapshot)
  )
  complete <- TRUE
  result
}
