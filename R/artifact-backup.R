#' Create a closed artifact-store backup
#'
#' Copy a complete, verified artifact store into a versioned local backup
#' bundle. The bundle contains a canonical descriptor and an exact image of
#' the local artifact store. The receipt is small enough for an application to
#' retain separately from the bundle.
#'
#' @param store A handle returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param path An absent local directory path for the backup bundle. Existing
#'   paths, including dangling symbolic links, are rejected. The parent directory
#'   must already exist; paths must not contain `..` components.
#' @param scope An opaque, nonempty identifier that the host application
#'   associates with this scope.
#' @param generation An opaque, nonempty identifier that the host application
#'   associates with this generation.
#' @param max_objects Maximum number of stored artifact objects to inspect.
#' @param max_total_bytes Maximum total bytes across stored artifact objects.
#' @param max_metadata_bytes Maximum bytes for one selection or decision object
#'   and the aggregate bytes of one decision stream.
#' @param max_bundle_metadata_bytes Maximum bytes for the `bundle.json`
#'   descriptor.
#'
#' @returns A receipt containing the backup format, descriptor digest, scope,
#'   generation, and complete manifest digest.
#'
#' @details
#' The source's objects are never changed; a writable source may gain the
#' lock file under `locks/` that every write uses, which is not part of its
#' manifest. A backup includes valid orphan content and all
#' historical decision records. Local source stores require a trusted
#' directory; the backup holds the store's lock exclusively (see
#' [graft_with_store_lock()]), so writers from other processes wait until it
#' finishes. PostgreSQL callers retain transaction and commit ownership; a
#' successful receipt does not prove that a transaction has committed. The
#' destination is built in a sibling staging directory and is renamed only
#' after the complete image is verified. On an
#' ordinary failure, the operation removes its staging directory. An
#' interrupted process can leave staging behind for host inventory and
#' disposal.
#' The destination's parent must already be a readable directory, and paths
#' cannot contain parent traversal components.
#'
#' Scope and generation associate the image with host records. They do not
#' authenticate a caller, grant access, or establish registry freshness.
#'
#' @export
graft_backup <- function(
  store,
  path,
  scope,
  generation,
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2,
  max_bundle_metadata_bytes = 4 * 1024^2
) {
  artifact_backup_check_source_store(store)
  artifact_with_store_lock(store, TRUE, function() {
    artifact_backup_create(
      store,
      path,
      scope,
      generation,
      max_objects,
      max_total_bytes,
      max_metadata_bytes,
      max_bundle_metadata_bytes
    )
  })
}

artifact_backup_create <- function(
  store,
  path,
  scope,
  generation,
  max_objects,
  max_total_bytes,
  max_metadata_bytes,
  max_bundle_metadata_bytes
) {
  path <- artifact_backup_clean_path(path)
  scope <- artifact_check_text(scope, "scope")
  generation <- artifact_check_text(generation, "generation")
  artifact_backup_check_source_store(store)
  limits <- artifact_backup_limits(
    max_objects,
    max_total_bytes,
    max_metadata_bytes,
    max_bundle_metadata_bytes,
    max_bytes = store@max_bytes,
    max_revision_bytes = store@max_revision_bytes
  )
  artifact_backup_check_destination(path, store)

  snapshot <- artifact_recovery_snapshot(
    store,
    max_objects = limits$max_objects,
    max_total_bytes = limits$max_total_bytes,
    max_metadata_bytes = limits$max_metadata_bytes
  )
  descriptor <- list(
    format = "graft-artifact-backup/1",
    scope = scope,
    generation = generation,
    manifest = snapshot$manifest
  )
  descriptor_bytes <- artifact_encode(descriptor)
  if (length(descriptor_bytes) > limits$max_bundle_metadata_bytes) {
    artifact_abort("Backup descriptor exceeds the bundle metadata bound.")
  }
  receipt <- artifact_backup_receipt(descriptor, descriptor_bytes)

  parent <- dirname(path)
  staging <- tempfile("graft-backup-", tmpdir = parent)
  if (!dir.create(staging, showWarnings = FALSE)) {
    artifact_abort("Could not create the backup staging directory.")
  }
  completed <- FALSE
  on.exit(
    if (!completed && artifact_backup_path_exists(staging)) {
      unlink(staging, recursive = TRUE, force = TRUE)
    },
    add = TRUE
  )

  staging_store <- graft_store(
    file.path(staging, "objects"),
    create = TRUE,
    max_bytes = store@max_bytes,
    max_revision_bytes = store@max_revision_bytes
  )
  artifact_without_store_lock(staging_store, function() {
    artifact_backup_copy_objects(
      store,
      staging_store,
      snapshot$manifest$objects,
      limits$max_metadata_bytes
    )
  })
  artifact_put(
    descriptor_bytes,
    file.path(staging, "bundle.json"),
    limits$max_bundle_metadata_bytes
  )

  source_after <- artifact_recovery_snapshot(
    store,
    max_objects = limits$max_objects,
    max_total_bytes = limits$max_total_bytes,
    max_metadata_bytes = limits$max_metadata_bytes
  )
  if (!identical(source_after$manifest, snapshot$manifest)) {
    artifact_abort("Artifact source changed during backup.")
  }
  artifact_backup_verify_bundle(
    staging,
    receipt,
    limits
  )

  if (artifact_backup_path_exists(path)) {
    artifact_abort("Backup destination already exists.")
  }
  if (!artifact_rename_file(staging, path)) {
    artifact_abort("Backup publication failed; no receipt issued.")
  }
  completed <- TRUE
  receipt
}

#' Verify a closed artifact-store backup
#'
#' Validate a complete backup bundle against a receipt retained outside the
#' bundle. Verification checks canonical descriptor bytes, exact object bytes,
#' complete artifact histories, and all caller-supplied bounds.
#'
#' @param path A local backup bundle path without `..` components.
#' @param expected The independently retained receipt expected for this bundle.
#' @param max_objects Maximum number of stored artifact objects to inspect.
#' @param max_total_bytes Maximum total bytes across stored artifact objects.
#' @param max_metadata_bytes Maximum bytes for one selection or decision object
#'   and the aggregate bytes of one decision stream.
#' @param max_bundle_metadata_bytes Maximum bytes for the `bundle.json`
#'   descriptor.
#' @param max_bytes Maximum payload bytes allowed for content objects.
#' @param max_revision_bytes Maximum bytes allowed for one revision object.
#'
#' @returns The canonical verified receipt.
#'
#' @details
#' The receipt is required from an independent application registry; it is not
#' read from the bundle. Matching scope and generation values identify the
#' expected image but do not authenticate it or establish current restore
#' eligibility. Verification never changes the bundle.
#'
#' @export
graft_verify_backup <- function(
  path,
  expected,
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2,
  max_bundle_metadata_bytes = 4 * 1024^2,
  max_bytes = 64 * 1024^2,
  max_revision_bytes = 1024^2
) {
  path <- artifact_backup_clean_path(path)
  limits <- artifact_backup_limits(
    max_objects,
    max_total_bytes,
    max_metadata_bytes,
    max_bundle_metadata_bytes,
    max_bytes = max_bytes,
    max_revision_bytes = max_revision_bytes
  )
  artifact_backup_verify_bundle(path, expected, limits)$receipt
}

#' Restore a verified backup into an empty artifact store
#'
#' Verify a closed backup, then copy its exact objects into an empty local or
#' transaction-scoped PostgreSQL artifact store. Verify the target again before
#' returning its manifest.
#'
#' @param path A local backup bundle path without `..` components.
#' @param target An empty handle returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param expected The independently retained receipt expected for this bundle.
#' @param max_objects Maximum number of stored artifact objects to inspect.
#' @param max_total_bytes Maximum total bytes across stored artifact objects.
#' @param max_metadata_bytes Maximum bytes for one selection or decision object
#'   and the aggregate bytes of one decision stream.
#' @param max_bundle_metadata_bytes Maximum bytes for the `bundle.json`
#'   descriptor.
#'
#' @returns The complete manifest of the verified restored target.
#'
#' @details
#' The bundle is verified before any target object is written, then verified
#' again after copying. The target must be empty and outside the bundle. A
#' failed copy can leave a partial target. Quarantine it and retry in a fresh
#' empty target. The source bundle is never changed. PostgreSQL callers own the
#' surrounding transaction and commit.
#'
#' @export
graft_restore <- function(
  path,
  target,
  expected,
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2,
  max_bundle_metadata_bytes = 4 * 1024^2
) {
  # The target's lock file is created only once the target is known not to
  # overlap the bundle, which must never change.
  path <- artifact_backup_clean_path(path)
  artifact_backup_check_target_store(target)
  artifact_backup_preflight_bundle_root(path)
  if (!S7::S7_inherits(target, PostgresArtifactStore)) {
    artifact_backup_assert_disjoint_paths(
      path,
      target@path,
      "Backup bundle and restore target must be separate paths."
    )
  }
  artifact_with_store_lock(target, TRUE, function() {
    artifact_backup_restore(
      path,
      target,
      expected,
      max_objects,
      max_total_bytes,
      max_metadata_bytes,
      max_bundle_metadata_bytes
    )
  })
}

artifact_backup_restore <- function(
  path,
  target,
  expected,
  max_objects,
  max_total_bytes,
  max_metadata_bytes,
  max_bundle_metadata_bytes
) {
  limits <- artifact_backup_limits(
    max_objects,
    max_total_bytes,
    max_metadata_bytes,
    max_bundle_metadata_bytes,
    max_bytes = target@max_bytes,
    max_revision_bytes = target@max_revision_bytes
  )
  checked <- artifact_backup_verify_bundle(path, expected, limits)

  target_snapshot <- artifact_recovery_snapshot(
    target,
    max_objects = limits$max_objects,
    max_total_bytes = limits$max_total_bytes,
    max_metadata_bytes = limits$max_metadata_bytes
  )
  if (length(target_snapshot$manifest$objects)) {
    artifact_abort("Artifact restore target must be empty.")
  }

  artifact_backup_copy_objects(
    checked$store,
    target,
    checked$manifest$objects,
    limits$max_metadata_bytes
  )

  source_after <- artifact_backup_verify_bundle(path, expected, limits)
  if (!identical(source_after$manifest, checked$manifest)) {
    artifact_abort("Backup bundle changed during restore.")
  }
  target_after <- artifact_recovery_snapshot(
    target,
    max_objects = limits$max_objects,
    max_total_bytes = limits$max_total_bytes,
    max_metadata_bytes = limits$max_metadata_bytes
  )
  if (!identical(target_after$manifest, checked$manifest)) {
    artifact_abort("Restored artifact store manifest did not verify.")
  }
  target_after$manifest
}

artifact_backup_check_source_store <- function(store) {
  if (S7::S7_inherits(store, LocalArtifactStore)) {
    artifact_backup_preflight_local_root(store@path, "Artifact source store")
  }
  artifact_recovery_preflight_store(store)
  artifact_check_store(store)
  invisible(NULL)
}

artifact_backup_check_target_store <- function(store) {
  if (S7::S7_inherits(store, LocalArtifactStore)) {
    artifact_backup_preflight_local_root(store@path, "Artifact restore target")
  }
  artifact_recovery_preflight_store(store)
  artifact_check_store(store)
  invisible(NULL)
}

artifact_backup_preflight_local_root <- function(path, label) {
  path <- artifact_backup_clean_path(path)
  artifact_check_path(path)
  if (!artifact_recovery_directory(path)) {
    artifact_abort(paste0(label, " must be a regular readable directory."))
  }
  invisible(NULL)
}

artifact_backup_preflight_bundle_root <- function(path) {
  path <- artifact_backup_clean_path(path)
  artifact_check_path(path)
  if (!artifact_recovery_directory(path)) {
    artifact_abort("Backup bundle must be a regular readable directory.")
  }
  entries <- tryCatch(
    list.files(
      path,
      all.files = TRUE,
      no.. = TRUE,
      recursive = FALSE,
      include.dirs = TRUE
    ),
    error = function(...) artifact_abort("Could not enumerate backup bundle.")
  )
  if (
    !identical(sort(entries, method = "radix"), c("bundle.json", "objects"))
  ) {
    artifact_abort("Backup bundle contains unexpected root entries.")
  }
  if (!artifact_recovery_regular_file(file.path(path, "bundle.json"))) {
    artifact_abort("Backup descriptor is not a regular file.")
  }
  if (!artifact_recovery_directory(file.path(path, "objects"))) {
    artifact_abort("Backup object image is not a regular directory.")
  }
  invisible(NULL)
}

artifact_backup_check_destination <- function(path, source) {
  path <- artifact_backup_clean_path(path)
  artifact_check_path(path)
  parent <- dirname(path)
  parent <- tryCatch(
    normalizePath(parent, winslash = "/", mustWork = TRUE),
    error = function(...) NULL
  )
  if (is.null(parent) || !artifact_recovery_directory(parent)) {
    artifact_abort(
      "Backup destination parent must already be a readable directory."
    )
  }
  if (artifact_backup_path_exists(path)) {
    artifact_abort("Backup destination already exists.")
  }
  if (!S7::S7_inherits(source, PostgresArtifactStore)) {
    artifact_backup_assert_disjoint_paths(
      source@path,
      path,
      "Backup destination must be outside the source store."
    )
  }
  invisible(NULL)
}

artifact_backup_assert_disjoint_paths <- function(first, second, message) {
  first <- artifact_backup_normalize_path(first)
  second <- artifact_backup_normalize_path(second)
  if (
    artifact_backup_path_contains(first, second) ||
      artifact_backup_path_contains(second, first)
  ) {
    artifact_abort(message)
  }
  invisible(NULL)
}

artifact_backup_path_contains <- function(root, path) {
  prefix <- if (endsWith(root, "/")) root else paste0(root, "/")
  identical(root, path) || startsWith(path, prefix)
}

artifact_backup_normalize_path <- function(path) {
  path <- artifact_backup_clean_path(path)
  if (!artifact_backup_path_exists(path)) {
    parent <- dirname(path)
    parent <- tryCatch(
      normalizePath(parent, winslash = "/", mustWork = TRUE),
      error = function(...) artifact_abort("Could not resolve artifact path.")
    )
    if (!artifact_recovery_directory(parent)) {
      artifact_abort("Could not resolve artifact path.")
    }
    return(file.path(parent, basename(path)))
  }
  tryCatch(
    normalizePath(path, winslash = "/", mustWork = FALSE),
    error = function(...) artifact_abort("Could not resolve artifact path.")
  )
}

artifact_backup_path_exists <- function(path) {
  path <- artifact_backup_clean_path(path)
  if (
    file.exists(path) ||
      dir.exists(path) ||
      artifact_recovery_is_symlink(path)
  ) {
    return(TRUE)
  }
  info <- tryCatch(
    fs::file_info(path, fail = FALSE, follow = FALSE),
    error = function(...) NULL
  )
  if (is.null(info) || nrow(info) != 1L) {
    return(FALSE)
  }
  type <- as.character(info$type)
  if (is.na(type) || type %in% c("missing", "unknown")) {
    return(FALSE)
  }
  TRUE
}

artifact_backup_clean_path <- function(path) {
  artifact_check_path(path)
  if (grepl("(^|[/\\\\])\\.\\.([/\\\\]|$)", path, perl = TRUE)) {
    artifact_abort("Artifact paths cannot contain parent traversal.")
  }
  path <- tryCatch(
    as.character(fs::path_norm(path)),
    error = function(...) artifact_abort("Could not resolve artifact path.")
  )
  artifact_check_path(path)
  path
}

artifact_backup_limits <- function(
  max_objects,
  max_total_bytes,
  max_metadata_bytes,
  max_bundle_metadata_bytes,
  max_bytes,
  max_revision_bytes
) {
  artifact_check_limit(max_objects, "max_objects")
  artifact_check_limit(max_total_bytes, "max_total_bytes")
  artifact_check_limit(max_metadata_bytes, "max_metadata_bytes")
  artifact_check_limit(
    max_bundle_metadata_bytes,
    "max_bundle_metadata_bytes"
  )
  artifact_check_limit(max_bytes, "max_bytes")
  artifact_check_limit(max_revision_bytes, "max_revision_bytes")
  list(
    max_objects = as.numeric(max_objects),
    max_total_bytes = as.numeric(max_total_bytes),
    max_metadata_bytes = as.numeric(max_metadata_bytes),
    max_bundle_metadata_bytes = as.numeric(max_bundle_metadata_bytes),
    max_bytes = as.numeric(max_bytes),
    max_revision_bytes = as.numeric(max_revision_bytes)
  )
}

artifact_backup_object_limit <- function(
  backend_or_limits,
  kind,
  max_metadata_bytes
) {
  if (identical(kind, "content")) {
    return(
      if (S7::S7_inherits(backend_or_limits, ArtifactStore)) {
        backend_or_limits@max_bytes
      } else {
        backend_or_limits$max_bytes
      }
    )
  }
  if (identical(kind, "revisions")) {
    return(
      if (S7::S7_inherits(backend_or_limits, ArtifactStore)) {
        backend_or_limits@max_revision_bytes
      } else {
        backend_or_limits$max_revision_bytes
      }
    )
  }
  if (identical(kind, "selections") || identical(kind, "decisions")) {
    return(max_metadata_bytes)
  }
  artifact_abort("Artifact backup contains an unsupported object kind.")
}

artifact_backup_copy_objects <- function(
  source,
  target,
  objects,
  max_metadata_bytes
) {
  for (object in objects) {
    source_limit <- artifact_backup_object_limit(
      source,
      object$kind,
      max_metadata_bytes
    )
    target_limit <- artifact_backup_object_limit(
      target,
      object$kind,
      max_metadata_bytes
    )
    bytes <- artifact_storage_read(
      source,
      object$kind,
      object$key,
      source_limit
    )
    if (
      length(bytes) != object$size ||
        !identical(artifact_sha(bytes), object$digest)
    ) {
      artifact_abort(
        paste0(
          "Artifact object `",
          object$kind,
          "/",
          object$key,
          "` changed during backup or restore."
        )
      )
    }
    artifact_storage_put(
      target,
      object$kind,
      object$key,
      bytes,
      target_limit
    )
  }
  invisible(NULL)
}

artifact_backup_verify_bundle <- function(path, expected, limits) {
  expected <- artifact_backup_check_receipt(expected)
  artifact_backup_preflight_bundle_root(path)
  descriptor_path <- file.path(path, "bundle.json")
  descriptor_bytes <- artifact_bytes(
    descriptor_path,
    limits$max_bundle_metadata_bytes
  )
  descriptor <- artifact_backup_check_descriptor(
    artifact_decode(descriptor_bytes),
    descriptor_bytes,
    limits
  )
  receipt <- artifact_backup_receipt(descriptor, descriptor_bytes)
  if (!identical(receipt, expected)) {
    artifact_abort("Backup receipt does not match the bundle descriptor.")
  }

  objects_path <- file.path(path, "objects")
  artifact_backup_preflight_local_root(objects_path, "Backup object image")
  store <- graft_store(
    objects_path,
    max_bytes = limits$max_bytes,
    max_revision_bytes = limits$max_revision_bytes
  )
  snapshot <- artifact_without_store_lock(store, function() {
    artifact_recovery_snapshot(
      store,
      max_objects = limits$max_objects,
      max_total_bytes = limits$max_total_bytes,
      max_metadata_bytes = limits$max_metadata_bytes
    )
  })
  if (!identical(snapshot$manifest, descriptor$manifest)) {
    artifact_abort("Backup object image does not match its descriptor.")
  }
  list(
    receipt = receipt,
    descriptor = descriptor,
    manifest = descriptor$manifest,
    store = store
  )
}

artifact_backup_check_descriptor <- function(value, bytes, limits) {
  if (
    !is.list(value) ||
      !identical(
        names(value),
        c("format", "scope", "generation", "manifest")
      ) ||
      !identical(value$format, "graft-artifact-backup/1")
  ) {
    artifact_abort("Unsupported or noncanonical artifact backup descriptor.")
  }
  scope <- artifact_check_text(value$scope, "descriptor$scope")
  generation <- artifact_check_text(
    value$generation,
    "descriptor$generation"
  )
  manifest <- artifact_backup_check_manifest(
    value$manifest,
    limits
  )
  descriptor <- list(
    format = "graft-artifact-backup/1",
    scope = scope,
    generation = generation,
    manifest = manifest
  )
  if (!identical(artifact_encode(descriptor), bytes)) {
    artifact_abort("Backup descriptor is not canonical.")
  }
  descriptor
}

artifact_backup_check_manifest <- function(manifest, limits) {
  if (
    !is.list(manifest) ||
      !identical(names(manifest), c("format", "id", "objects")) ||
      !identical(manifest$format, "graft-artifact-manifest/1")
  ) {
    artifact_abort("Unsupported artifact backup manifest.")
  }
  objects <- manifest$objects
  if (
    !is.list(objects) ||
      is.object(objects) ||
      !is.null(names(objects))
  ) {
    artifact_abort("Artifact backup manifest objects have an invalid shape.")
  }
  if (length(objects) > limits$max_objects) {
    artifact_abort("Backup manifest exceeds the object-count bound.")
  }
  objects <- lapply(objects, artifact_recovery_manifest_entry)
  if (length(objects)) {
    keys <- vapply(
      objects,
      \(object) paste(object$kind, object$key, sep = "\n"),
      character(1)
    )
    if (anyDuplicated(keys)) {
      artifact_abort("Backup manifest contains duplicate object entries.")
    }
  }
  canonical <- artifact_recovery_manifest(objects)
  manifest_id <- artifact_check_digest(manifest$id)
  if (!identical(manifest_id, canonical$id)) {
    artifact_abort("Backup manifest digest is not canonical.")
  }
  sizes <- vapply(objects, \(object) object$size, numeric(1))
  total <- if (length(sizes)) sum(sizes) else 0
  if (!is.finite(total) || total > limits$max_total_bytes) {
    artifact_abort("Backup manifest exceeds the total byte bound.")
  }
  for (object in objects) {
    limit <- artifact_backup_object_limit(
      limits,
      object$kind,
      limits$max_metadata_bytes
    )
    if (object$size > limit) {
      artifact_abort("Backup manifest contains an oversized object.")
    }
  }
  canonical
}

artifact_backup_receipt <- function(descriptor, descriptor_bytes) {
  list(
    format = "graft-artifact-backup/1",
    id = artifact_sha(descriptor_bytes),
    scope = descriptor$scope,
    generation = descriptor$generation,
    manifest = descriptor$manifest$id
  )
}

artifact_backup_check_receipt <- function(expected) {
  if (
    !is.list(expected) ||
      !identical(
        names(expected),
        c("format", "id", "scope", "generation", "manifest")
      ) ||
      !identical(expected$format, "graft-artifact-backup/1")
  ) {
    artifact_abort("Expected backup receipt has an invalid shape.")
  }
  receipt <- list(
    format = "graft-artifact-backup/1",
    id = artifact_check_digest(expected$id),
    scope = artifact_check_text(expected$scope, "expected$scope"),
    generation = artifact_check_text(
      expected$generation,
      "expected$generation"
    ),
    manifest = artifact_check_digest(expected$manifest)
  )
  if (!identical(receipt, expected)) {
    artifact_abort("Expected backup receipt is not canonical.")
  }
  receipt
}
