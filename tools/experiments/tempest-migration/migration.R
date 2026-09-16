# Bounded read-only migration adapter. Native acceptance identities are retained
# as data, never substituted with an artifact digest or a fabricated Graft view.
migration_one <- function(values, predicate, what) {
  found <- Filter(predicate, values)
  if (length(found) != 1L) {
    artifact_error(paste("Missing or ambiguous", what))
  }
  found[[1L]]
}

migration_revision <- function(export, revision_id) {
  migration_one(
    export$history,
    \(row) identical(row$revision_id, revision_id),
    "native revision."
  )
}

migration_at <- function(export, record_id, order) {
  rows <- Filter(
    \(row) identical(row$record_id, record_id) && row$commit_order <= order,
    export$history
  )
  if (!length(rows)) {
    artifact_error("Record is absent at the selected boundary.")
  }
  rows[[which.max(vapply(rows, \(row) row$revision_number, numeric(1)))]]
}

migration_validate <- function(export) {
  if (
    !identical(export$format, 1L) ||
      !isTRUE(export$final_snapshot$history_complete)
  ) {
    artifact_error("Unsupported export format or incomplete source history.")
  }
  if (length(export$history) > 40L || !length(export$history)) {
    artifact_error("Native history exceeds the bounded migration profile.")
  }
  required <- list(
    receipts = c("initial", "unchanged", "correction"),
    checkpoints = c("initial", "correction"),
    promotion_bundles = c("initial", "correction")
  )
  for (field in names(required)) {
    values <- export[[field]]
    if (
      !is.list(values) ||
        anyDuplicated(names(values)) ||
        !setequal(names(values), required[[field]]) ||
        any(vapply(values, \(value) !length(value), logical(1)))
    ) {
      artifact_error(paste("Missing or ambiguous required", field))
    }
  }
  ids <- vapply(export$history, \(row) row$revision_id, character(1))
  if (anyDuplicated(ids)) {
    artifact_error("Duplicate native revision identity.")
  }
  keys <- lapply(export$history, \(row) {
    row[c("record_id", "class", "revision_number")]
  })
  if (anyDuplicated(keys)) {
    artifact_error("Duplicate native revision-number key.")
  }
  final <- export$final_snapshot
  if (
    !identical(
      final$schema_build_digest,
      "sha256:0ef4a9c9143e6aaff3def45c996855773dd3c5ce341293bc15032c0924ed4296"
    ) ||
      !identical(final$store_format_version, "3.1.0")
  ) {
    artifact_error(
      "This migration profile supports only the pinned Tempest schema and store format."
    )
  }
  if (
    !identical(
      export$schema$fingerprints$build_digest,
      final$schema_build_digest
    ) ||
      !identical(
        artifact_hash(charToRaw(export$schema_file_text)),
        export$schema_file_sha256
      )
  ) {
    artifact_error(
      "Retained runtime schema or original schema bytes do not match."
    )
  }
  snapshot_check <- function(snapshot) {
    if (
      !identical(snapshot$store_id, final$store_id) ||
        !identical(snapshot$schema_build_digest, final$schema_build_digest) ||
        !identical(snapshot$store_format_version, final$store_format_version) ||
        !isTRUE(snapshot$history_complete) ||
        snapshot$commit_order > final$commit_order
    ) {
      artifact_error(
        "Snapshot belongs to another store, schema or history boundary."
      )
    }
  }
  for (row in export$history) {
    if (!row$operation %in% c("insert", "update")) {
      artifact_error(
        "Tombstone or other native operation is unsupported by this migration profile."
      )
    }
    expected <- if (isTRUE(row$revision_number == 1L)) "insert" else "update"
    if (
      !is.numeric(row$revision_number) ||
        length(row$revision_number) != 1L ||
        !is.finite(row$revision_number) ||
        row$revision_number < 1L ||
        row$revision_number != floor(row$revision_number) ||
        !identical(row$operation, expected)
    ) {
      artifact_error("Native operation does not match its revision number.")
    }
    if (
      !identical(row$schema_build_digest, final$schema_build_digest) ||
        row$commit_order > final$commit_order
    ) {
      artifact_error("Revision lies outside the exported schema or boundary.")
    }
    if (row$revision_number == 1L) {
      if (!is.null(row$prior_revision_id)) {
        artifact_error("Initial revision has a predecessor.")
      }
    } else {
      prior <- migration_revision(export, row$prior_revision_id)
      if (
        !identical(prior$record_id, row$record_id) ||
          !identical(prior$class, row$class) ||
          prior$revision_number != row$revision_number - 1L ||
          prior$commit_order >= row$commit_order
      ) {
        artifact_error("Native predecessor chain is incomplete or reordered.")
      }
    }
  }
  receipt_rows <- unlist(
    lapply(export$receipts, \(receipt) receipt$record_revisions),
    recursive = FALSE
  )
  for (receipt in export$receipts) {
    if (
      !is.list(receipt$record_revisions) || !length(receipt$record_revisions)
    ) {
      artifact_error("Each required receipt must cover native revisions.")
    }
    bundle <- migration_one(
      export$promotion_bundles,
      \(bundle) identical(bundle$bundle_id, receipt$bundle_id),
      "source promotion bundle."
    )
    if (
      !identical(
        jsonlite::fromJSON(
          bundle$bundle_json,
          simplifyVector = FALSE
        )$bundle_id,
        receipt$bundle_id
      )
    ) {
      artifact_error("Promotion bundle does not match its retained receipt.")
    }
    manifest <- jsonlite::fromJSON(bundle$manifest_json, simplifyVector = FALSE)
    if (
      !identical(manifest$bundle_id, receipt$bundle_id) ||
        !identical(
          manifest$checksums[["bundle.json"]],
          artifact_hash(charToRaw(bundle$bundle_json))
        )
    ) {
      artifact_error(
        "Promotion bundle bytes do not match their source manifest."
      )
    }
    snapshot_check(receipt$snapshot)
    if (
      !identical(receipt$store_id, final$store_id) ||
        !identical(receipt$batch_id, receipt$snapshot$batch_id) ||
        !identical(receipt$schema_build_digest, final$schema_build_digest)
    ) {
      artifact_error("Receipt identity does not match its source snapshot.")
    }
    for (ref in receipt$record_revisions) {
      row <- migration_revision(export, ref$revision_id)
      fields <- c(
        "record_id",
        "class",
        "revision_number",
        "batch_id",
        "schema_build_digest"
      )
      if (
        !identical(row[fields], ref[fields]) ||
          row$commit_order > receipt$snapshot$commit_order
      ) {
        artifact_error("Receipt does not cover the retained native revision.")
      }
    }
  }
  for (checkpoint in export$checkpoints) {
    snapshot_check(checkpoint$snapshot)
    selected <- unlist(checkpoint$selections, recursive = FALSE)
    selected <- selected[order(
      vapply(selected, \(ref) ref$record_id, character(1)),
      method = "radix"
    )]
    selected_ids <- vapply(selected, \(ref) ref$record_id, character(1))
    if (
      anyDuplicated(selected_ids) ||
        !identical(as.list(selected_ids), checkpoint$record_ids) ||
        !identical(
          lapply(selected, \(ref) ref$revision_id),
          checkpoint$revision_ids
        ) ||
        length(checkpoint$resources) != length(selected)
    ) {
      artifact_error("Checkpoint does not retain its complete selection.")
    }
    rows <- lapply(selected, function(ref) {
      if (
        !any(vapply(
          receipt_rows,
          \(covered) identical(covered, ref),
          logical(1)
        ))
      ) {
        artifact_error(
          "Checkpoint revision is not covered by a retained receipt."
        )
      }
      row <- migration_at(
        export,
        ref$record_id,
        checkpoint$snapshot$commit_order
      )
      if (!identical(row$revision_id, ref$revision_id)) {
        artifact_error(
          "Checkpoint selects a different revision at its boundary."
        )
      }
      row
    })
    for (i in seq_along(rows)) {
      resource <- checkpoint$resources[[i]]
      if (
        !identical(resource$metadata$graft_record_id, rows[[i]]$record_id) ||
          !identical(
            resource$metadata$graft_revision_id,
            rows[[i]]$revision_id
          ) ||
          !identical(resource$metadata$graft_record_class, rows[[i]]$class)
      ) {
        artifact_error(
          "Materialized evidence has a different accepted identity."
        )
      }
      # The supported Tempest fixture's declared evidence links must remain in
      # the selection. This is domain-specific validation, not a schema compiler.
      fields <- switch(
        rows[[i]]$class,
        ClaimSupport = c("statement_id", "source_id", "evidence_span_id"),
        EvidenceSpan = "source_id",
        character()
      )
      dependencies <- unlist(rows[[i]]$record[fields], use.names = FALSE)
      if (!all(dependencies %in% selected_ids)) {
        artifact_error("Checkpoint is missing a required evidence dependency.")
      }
    }
  }
  invisible(export)
}

migration_save_json <- function(store, id, value, dependencies = list()) {
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeBin(charToRaw(artifact_json(value)), path)
  artifact_save(
    store,
    id,
    path,
    "application/json",
    dependencies,
    producer = "tempest-migration:fixture-v1"
  )
}

migration_import <- function(export_path, expected_sha256, target) {
  bytes <- artifact_read_bytes(export_path)
  if (!identical(artifact_hash(bytes), expected_sha256)) {
    artifact_error("Export bytes differ from the trusted handoff digest.")
  }
  export <- jsonlite::fromJSON(rawToChar(bytes), simplifyVector = FALSE)
  migration_validate(export)
  if (
    dir.exists(target) &&
      length(list.files(target, all.files = TRUE, no.. = TRUE))
  ) {
    artifact_error(
      "Migration target must be empty; existing policy must not be overwritten."
    )
  }
  store <- artifact_store(target, "manifest", "unused")
  rows <- lapply(export$history, function(row) {
    migration_save_json(
      store,
      paste0("artifact:native-", artifact_hash(charToRaw(row$revision_id))),
      row
    )
  })
  map <- stats::setNames(
    rows,
    vapply(export$history, \(row) row$revision_id, character(1))
  )
  retained <- export
  retained$history <- NULL
  retained$source_export_sha256 <- expected_sha256
  retained$identity_map <- map
  root <- migration_save_json(
    store,
    "artifact:tempest-migration",
    retained,
    rows
  )
  basis <- artifact_approve(store, list(root), "historical inspection")
  list(root = root, basis = basis, source_export_sha256 = expected_sha256)
}

migration_open <- function(target, handle, consult = TRUE) {
  store <- artifact_store(target, "manifest", "unused")
  items <- artifact_read_basis(
    store,
    handle$basis,
    "historical inspection",
    consult = consult
  )
  root <- migration_one(
    items,
    \(item) identical(item$ref, handle$root),
    "migration root."
  )
  export <- jsonlite::fromJSON(rawToChar(root$bytes), simplifyVector = FALSE)
  if (!identical(export$source_export_sha256, handle$source_export_sha256)) {
    artifact_error("Migration root belongs to another handoff.")
  }
  export$history <- lapply(names(export$identity_map), function(id) {
    item <- migration_one(
      items,
      \(item) identical(item$ref, export$identity_map[[id]]),
      "mapped revision."
    )
    row <- jsonlite::fromJSON(rawToChar(item$bytes), simplifyVector = FALSE)
    if (!identical(row$revision_id, id)) {
      artifact_error("Native identity mapping was altered.")
    }
    row
  })
  migration_validate(export)
  export
}

migration_read <- function(target, handle, checkpoint, consult = TRUE) {
  export <- migration_open(target, handle, consult)
  basis <- export$checkpoints[[checkpoint]]
  if (is.null(basis)) {
    artifact_error("Unknown retained checkpoint.")
  }
  basis
}
