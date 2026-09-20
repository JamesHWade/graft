#' Inventory a complete artifact store
#'
#' Enumerate and verify every committed artifact object in a local or
#' transaction-scoped PostgreSQL store. The returned manifest is a deterministic
#' digest of the stored object keys, sizes and bytes. The marker identifying the
#' store format is checked but is not included in the manifest object list.
#'
#' @param store A handle returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param max_objects Maximum number of committed artifact objects to inspect.
#'   The store marker is not counted.
#' @param max_total_bytes Maximum total bytes across committed artifact objects.
#'   The store marker is not counted.
#' @param max_metadata_bytes Maximum bytes for one selection or decision object
#'   and the aggregate bytes of one decision stream. Revision reads use the
#'   store handle's max_revision_bytes bound.
#'
#' @details
#' This is a strict, bounded inspection of a closed candidate. Unknown object
#' kinds, unexpected paths, staging files, symbolic links, nonregular files,
#' malformed metadata, missing dependencies, corrupt bytes and incomplete
#' decision streams are rejected. Valid content objects that are not referenced
#' by a revision are retained in the inventory so a replacement planner can
#' omit them explicitly.
#'
#' The operation does not quiesce writers, remove source objects, authorize
#' access, interpret a host Forget decision, or admit a generation for service.
#' Hosts must quiesce the source and perform their own publication and restore
#' checks around this point-in-time inspection.
#'
#' @returns A list with format, id and ordered objects. Each object has
#' kind, key, size and the SHA-256 digest of its exact stored bytes.
#'
#' @export
graft_manifest <- function(
  store,
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2
) {
  snapshot <- artifact_recovery_snapshot(
    store,
    max_objects,
    max_total_bytes,
    max_metadata_bytes
  )
  snapshot$manifest
}

artifact_recovery_snapshot <- function(
  store,
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2
) {
  artifact_recovery_preflight_store(store)
  artifact_check_store(store)
  artifact_check_limit(max_objects, "max_objects")
  artifact_check_limit(max_total_bytes, "max_total_bytes")
  artifact_check_limit(max_metadata_bytes, "max_metadata_bytes")

  entries <- artifact_recovery_enumerate(
    store,
    max_objects,
    max_total_bytes,
    max_metadata_bytes
  )
  artifacts <- artifact_recovery_read_revisions(
    store,
    entries$revisions,
    max_metadata_bytes
  )
  artifact_recovery_check_dependencies(artifacts)

  selections <- artifact_recovery_read_selections(
    store,
    entries$selections,
    artifacts,
    max_objects,
    max_metadata_bytes
  )
  streams <- artifact_recovery_read_streams(
    store,
    entries$decisions,
    selections,
    max_objects,
    max_metadata_bytes
  )

  artifact_recovery_verify_unchanged(
    store,
    entries$objects,
    max_objects,
    max_total_bytes,
    max_metadata_bytes
  )
  manifest <- artifact_recovery_manifest(entries$objects)
  list(
    manifest = manifest,
    artifacts = artifacts,
    selections = selections,
    streams = streams
  )
}

artifact_recovery_preflight_store <- function(store) {
  if (S7::S7_inherits(store, LocalArtifactStore)) {
    marker <- file.path(store@path, "store.json")
    if (
      file.exists(marker) ||
        dir.exists(marker) ||
        artifact_recovery_is_symlink(marker)
    ) {
      if (!artifact_recovery_regular_file(marker)) {
        artifact_abort("Artifact store marker is not a regular file.")
      }
    }
  }
  invisible(NULL)
}

artifact_recovery_manifest <- function(objects) {
  if (
    !is.list(objects) ||
      is.object(objects) ||
      !is.null(names(objects))
  ) {
    artifact_abort("Artifact manifest objects must be an unnamed list.")
  }
  if (length(objects)) {
    objects <- lapply(objects, artifact_recovery_manifest_entry)
    keys <- vapply(
      objects,
      \(entry) paste(entry$kind, entry$key, sep = "\n"),
      character(1)
    )
    objects <- objects[order(keys, method = "radix")]
  }
  bytes <- artifact_encode(list(
    format = "graft-artifact-manifest/1",
    objects = objects
  ))
  list(
    format = "graft-artifact-manifest/1",
    id = artifact_sha(bytes),
    objects = unname(objects)
  )
}

artifact_recovery_manifest_entry <- function(entry) {
  if (
    !is.list(entry) ||
      !identical(names(entry), c("kind", "key", "size", "digest"))
  ) {
    artifact_abort("Artifact manifest entries have an unsupported shape.")
  }
  kind <- entry$kind
  key <- entry$key
  if (
    !rlang::is_string(kind) ||
      !rlang::is_string(key) ||
      !validUTF8(kind) ||
      !validUTF8(key)
  ) {
    artifact_abort("Artifact manifest entries require text kind and key.")
  }
  if (
    !identical(kind, enc2utf8(kind)) ||
      !identical(key, enc2utf8(key))
  ) {
    artifact_abort("Artifact manifest entries require UTF-8 kind and key.")
  }
  if (
    !kind %in% artifact_recovery_kinds() ||
      !artifact_recovery_valid_key(kind, key)
  ) {
    artifact_abort("Artifact manifest contains an unknown object key.")
  }
  size <- entry$size
  if (
    !is.numeric(size) ||
      length(size) != 1L ||
      is.na(size) ||
      !is.finite(size) ||
      size < 0 ||
      size != floor(size)
  ) {
    artifact_abort("Artifact manifest entries require a nonnegative size.")
  }
  digest <- artifact_check_digest(entry$digest)
  if (!identical(digest, artifact_recovery_key_digest(kind, key))) {
    artifact_abort("Artifact manifest entry digest does not match its key.")
  }
  list(
    kind = enc2utf8(kind),
    key = enc2utf8(key),
    size = as.numeric(size),
    digest = digest
  )
}

artifact_recovery_kinds <- function() {
  c("content", "decisions", "revisions", "selections")
}

artifact_recovery_valid_key <- function(kind, key) {
  if (
    !rlang::is_string(kind) ||
      !rlang::is_string(key) ||
      is.na(kind) ||
      is.na(key) ||
      !validUTF8(kind) ||
      !validUTF8(key)
  ) {
    return(FALSE)
  }
  if (kind %in% c("content", "revisions", "selections")) {
    return(grepl("^[0-9a-f]{64}$", key))
  }
  if (kind != "decisions") {
    return(FALSE)
  }
  grepl(
    "^[0-9a-f]{64}/[0-9]{10}-[0-9a-f]{64}[.]json$",
    key
  )
}

artifact_recovery_enumerate <- function(
  store,
  max_objects,
  max_total_bytes,
  max_metadata_bytes
) {
  if (S7::S7_inherits(store, PostgresArtifactStore)) {
    entries <- artifact_recovery_enumerate_postgres(store, max_objects)
  } else {
    entries <- artifact_recovery_enumerate_local(store)
  }
  artifact_recovery_check_entry_bounds(
    entries,
    max_objects,
    max_total_bytes,
    max_metadata_bytes
  )
  objects <- lapply(entries, artifact_recovery_object_entry)
  objects <- unname(objects)
  list(
    objects = objects,
    content = Filter(\(entry) entry$kind == "content", objects),
    revisions = Filter(\(entry) entry$kind == "revisions", objects),
    selections = Filter(\(entry) entry$kind == "selections", objects),
    decisions = Filter(\(entry) entry$kind == "decisions", objects)
  )
}

artifact_recovery_enumerate_local <- function(store) {
  root <- store@path
  marker <- charToRaw('{"format":"graft-artifacts","version":1}')
  root_entries <- list.files(
    root,
    all.files = TRUE,
    no.. = TRUE,
    recursive = FALSE,
    include.dirs = TRUE
  )
  if (!"store.json" %in% root_entries) {
    artifact_abort("Artifact store marker is missing.")
  }
  if (
    !artifact_recovery_regular_file(file.path(root, "store.json")) ||
      !identical(
        artifact_bytes(file.path(root, "store.json"), 1024),
        marker
      )
  ) {
    artifact_abort("Unsupported artifact store marker.")
  }
  expected <- c("store.json", artifact_recovery_kinds())
  unknown <- setdiff(root_entries, expected)
  if (length(unknown)) {
    artifact_abort("Artifact store contains unknown root entries.")
  }
  for (kind in artifact_recovery_kinds()) {
    path <- file.path(root, kind)
    if (kind %in% root_entries) {
      if (!artifact_recovery_directory(path)) {
        artifact_abort("Artifact store contains a non-directory object path.")
      }
    }
  }

  entries <- list()
  for (kind in c("content", "revisions", "selections")) {
    path <- file.path(root, kind)
    if (!dir.exists(path)) {
      next
    }
    names <- list.files(
      path,
      all.files = TRUE,
      no.. = TRUE,
      recursive = FALSE,
      include.dirs = TRUE
    )
    for (name in names) {
      object_path <- file.path(path, name)
      if (
        !artifact_recovery_valid_key(kind, name) ||
          !artifact_recovery_regular_file(object_path)
      ) {
        artifact_abort("Artifact store contains an unknown object path.")
      }
      entries[[length(entries) + 1L]] <- list(
        kind = kind,
        key = name,
        size = artifact_recovery_file_size(object_path)
      )
    }
  }

  decisions <- file.path(root, "decisions")
  if (dir.exists(decisions)) {
    stream_names <- list.files(
      decisions,
      all.files = TRUE,
      no.. = TRUE,
      recursive = FALSE,
      include.dirs = TRUE
    )
    for (stream in stream_names) {
      stream_path <- file.path(decisions, stream)
      if (
        !grepl("^[0-9a-f]{64}$", stream) ||
          !artifact_recovery_directory(stream_path)
      ) {
        artifact_abort("Artifact decision journal has an unknown path.")
      }
      names <- list.files(
        stream_path,
        all.files = TRUE,
        no.. = TRUE,
        recursive = FALSE,
        include.dirs = TRUE
      )
      if (!length(names)) {
        artifact_abort("Artifact decision journal contains an empty stream.")
      }
      for (name in names) {
        object_path <- file.path(stream_path, name)
        key <- paste(stream, name, sep = "/")
        if (
          !artifact_recovery_valid_key("decisions", key) ||
            !artifact_recovery_regular_file(object_path)
        ) {
          artifact_abort("Artifact decision journal has an unknown entry.")
        }
        entries[[length(entries) + 1L]] <- list(
          kind = "decisions",
          key = key,
          size = artifact_recovery_file_size(object_path)
        )
      }
    }
  }
  entries
}

artifact_recovery_enumerate_postgres <- function(store, max_objects) {
  count <- artifact_postgres_query(
    store@connection,
    paste(
      "SELECT count(*) AS count FROM graft_artifact_objects",
      "WHERE scope = $1"
    ),
    params = list(store@scope)
  )$count[[1L]]
  count <- suppressWarnings(as.numeric(count))
  if (
    is.na(count) ||
      !is.finite(count) ||
      count < 1 ||
      count != floor(count)
  ) {
    artifact_abort("Artifact object count is invalid.")
  }
  if (count > as.numeric(.Machine$integer.max)) {
    artifact_abort("Artifact object count exceeds the R limit.")
  }
  if (count > as.numeric(max_objects) + 1) {
    artifact_abort("Artifact store exceeds the object-count bound.")
  }
  rows <- artifact_postgres_query(
    store@connection,
    paste(
      "SELECT kind, object_key, octet_length(payload) AS size",
      "FROM graft_artifact_objects WHERE scope = $1",
      "ORDER BY kind, object_key LIMIT $2"
    ),
    params = list(store@scope, as.numeric(max_objects) + 1)
  )
  if (nrow(rows) != count) {
    artifact_abort("Artifact object listing changed during inspection.")
  }
  if (anyNA(rows$kind) || anyNA(rows$object_key) || anyNA(rows$size)) {
    artifact_abort("Artifact object listing contains missing fields.")
  }
  marker <- rows$kind == "store" & rows$object_key == "format"
  if (sum(marker) != 1L) {
    artifact_abort("Artifact store marker rows are invalid.")
  }
  if (any(rows$kind == "store" & !marker)) {
    artifact_abort("Artifact store contains an unknown store object.")
  }
  entries <- list()
  for (i in which(!marker)) {
    kind <- rows$kind[[i]]
    key <- rows$object_key[[i]]
    if (
      !rlang::is_string(kind) ||
        !rlang::is_string(key) ||
        !kind %in% artifact_recovery_kinds() ||
        !artifact_recovery_valid_key(kind, key)
    ) {
      artifact_abort("Artifact store contains an unknown object key.")
    }
    entries[[length(entries) + 1L]] <- list(
      kind = kind,
      key = key,
      size = artifact_recovery_scalar_size(rows$size[[i]])
    )
  }
  entries
}

artifact_recovery_check_entry_bounds <- function(
  entries,
  max_objects,
  max_total_bytes,
  max_metadata_bytes
) {
  if (length(entries) > max_objects) {
    artifact_abort("Artifact store exceeds the object-count bound.")
  }
  sizes <- vapply(entries, \(entry) entry$size, numeric(1))
  total <- if (length(sizes)) sum(sizes) else 0
  if (!is.finite(total) || total > max_total_bytes) {
    artifact_abort("Artifact store exceeds the total byte bound.")
  }
  metadata <- vapply(
    entries,
    \(entry) entry$kind %in% c("selections", "decisions"),
    logical(1)
  )
  if (
    any(vapply(
      entries[metadata],
      \(entry) entry$size > max_metadata_bytes,
      logical(1)
    ))
  ) {
    artifact_abort("Artifact metadata exceeds the metadata byte bound.")
  }
  invisible(NULL)
}

artifact_recovery_object_entry <- function(entry) {
  list(
    kind = entry$kind,
    key = entry$key,
    size = entry$size,
    digest = artifact_recovery_key_digest(entry$kind, entry$key)
  )
}

artifact_recovery_key_digest <- function(kind, key) {
  if (kind == "decisions") {
    return(sub("^.*-([0-9a-f]{64})[.]json$", "\\1", key))
  }
  key
}

artifact_recovery_read_object <- function(store, entry, max_metadata_bytes) {
  limit <- if (entry$kind == "content") {
    store@max_bytes
  } else if (entry$kind == "revisions") {
    store@max_revision_bytes
  } else {
    if (entry$size > max_metadata_bytes) {
      artifact_abort("Artifact metadata exceeds the metadata byte bound.")
    }
    max_metadata_bytes
  }
  bytes <- artifact_storage_read(store, entry$kind, entry$key, limit)
  if (length(bytes) != entry$size) {
    artifact_abort("Artifact object changed during recovery inspection.")
  }
  if (!identical(artifact_sha(bytes), entry$digest)) {
    artifact_abort("Artifact object digest mismatch.")
  }
  bytes
}

artifact_recovery_read_revisions <- function(
  store,
  entries,
  max_metadata_bytes
) {
  artifacts <- lapply(entries, function(entry) {
    bytes <- artifact_recovery_read_object(
      store,
      entry,
      max_metadata_bytes
    )
    metadata <- artifact_decode(bytes)
    artifact_check_metadata(metadata)
    artifact_read(
      store,
      list(id = metadata$id, revision = entry$key)
    )
  })
  unname(artifacts)
}

artifact_recovery_check_dependencies <- function(artifacts) {
  if (!length(artifacts)) {
    return(invisible(NULL))
  }
  keys <- vapply(
    artifacts,
    \(item) artifact_ref_key(item$ref),
    character(1)
  )
  if (anyDuplicated(keys)) {
    artifact_abort("Artifact revisions contain duplicate references.")
  }
  for (item in artifacts) {
    for (dependency in item$metadata$dependencies) {
      key <- artifact_ref_key(dependency)
      if (is.na(match(key, keys))) {
        artifact_abort("Artifact dependency is missing from the store.")
      }
    }
  }
  state <- integer(length(keys))
  for (start in seq_along(keys)) {
    if (state[[start]] == 2L) {
      next
    }
    state[[start]] <- 1L
    stack <- list(list(index = start, next_index = 1L))
    while (length(stack)) {
      frame_index <- length(stack)
      frame <- stack[[frame_index]]
      dependencies <- artifacts[[frame$index]]$metadata$dependencies
      if (frame$next_index > length(dependencies)) {
        state[[frame$index]] <- 2L
        stack <- stack[-frame_index]
        next
      }
      dependency <- dependencies[[frame$next_index]]
      frame$next_index <- frame$next_index + 1L
      stack[[frame_index]] <- frame
      dependency_index <- match(artifact_ref_key(dependency), keys)
      if (state[[dependency_index]] == 1L) {
        artifact_abort("Artifact dependency closure contains a cycle.")
      }
      if (state[[dependency_index]] == 0L) {
        state[[dependency_index]] <- 1L
        stack[[length(stack) + 1L]] <- list(
          index = dependency_index,
          next_index = 1L
        )
      }
    }
  }
  invisible(NULL)
}

artifact_recovery_read_selections <- function(
  store,
  entries,
  artifacts,
  max_objects,
  max_metadata_bytes
) {
  selections <- lapply(entries, function(entry) {
    selection <- artifact_read_selection(
      store,
      entry$key,
      max_artifacts = max_objects,
      max_metadata_bytes = max_metadata_bytes
    )
    artifact_recovery_read_object(store, entry, max_metadata_bytes)
    selection
  })
  selections <- unname(selections)
  artifact_keys <- vapply(
    artifacts,
    \(item) artifact_ref_key(item$ref),
    character(1)
  )
  for (selection in selections) {
    for (ref in selection$artifacts) {
      if (is.na(match(artifact_ref_key(ref), artifact_keys))) {
        artifact_abort("Artifact selection references a missing revision.")
      }
    }
  }
  selections
}

artifact_recovery_read_streams <- function(
  store,
  entries,
  selections,
  max_objects,
  max_metadata_bytes
) {
  if (!length(entries)) {
    return(list())
  }
  groups <- split(
    entries,
    sub("/.*$", "", vapply(entries, \(entry) entry$key, character(1)))
  )
  streams <- list()
  for (group in groups) {
    first <- group[[1L]]
    bytes <- artifact_recovery_read_object(store, first, max_metadata_bytes)
    value <- artifact_decode(bytes)
    if (
      !is.list(value) ||
        !identical(names(value), c("format", "sequence", "request")) ||
        !identical(value$format, 1L) ||
        !identical(value$sequence, 1L) ||
        !is.list(value$request)
    ) {
      artifact_abort("Unsupported decision record metadata.")
    }
    args <- value$request
    if (
      !identical(
        names(args),
        c(
          "stream",
          "key",
          "previous",
          "action",
          "selection",
          "actor",
          "reason",
          "purpose"
        )
      )
    ) {
      artifact_abort("Unsupported decision record request.")
    }
    names(args)[names(args) == "previous"] <- "expected"
    request <- do.call(artifact_decision_request, args)
    stream <- request$stream
    prefix <- sub("/.*$", "", first$key)
    if (!identical(artifact_sha(charToRaw(stream)), prefix)) {
      artifact_abort("Decision stream identity does not match its path.")
    }
    records <- artifact_decisions(
      store,
      stream,
      max_decisions = max_objects,
      max_metadata_bytes = max_metadata_bytes
    )
    streams[[stream]] <- records
  }
  streams <- streams[order(names(streams), method = "radix")]
  selection_ids <- stats::setNames(
    selections,
    vapply(selections, \(selection) selection$id, character(1))
  )
  for (records in streams) {
    for (record in records) {
      if (is.null(selection_ids[[record$selection]])) {
        artifact_abort("Decision history references a missing selection.")
      }
    }
  }
  streams
}

artifact_recovery_verify_unchanged <- function(
  store,
  objects,
  max_objects,
  max_total_bytes,
  max_metadata_bytes
) {
  current <- artifact_recovery_enumerate(
    store,
    max_objects,
    max_total_bytes,
    max_metadata_bytes
  )$objects
  expected <- lapply(objects, artifact_recovery_manifest_entry)
  actual <- lapply(current, artifact_recovery_manifest_entry)
  expected_keys <- vapply(
    expected,
    \(entry) paste(entry$kind, entry$key, sep = "\n"),
    character(1)
  )
  actual_keys <- vapply(
    actual,
    \(entry) paste(entry$kind, entry$key, sep = "\n"),
    character(1)
  )
  if (!identical(expected_keys, actual_keys)) {
    artifact_abort("Artifact object listing changed during inspection.")
  }
  for (entry in actual) {
    artifact_recovery_read_object(store, entry, max_metadata_bytes)
  }
  invisible(NULL)
}

artifact_recovery_regular_file <- function(path) {
  if (artifact_recovery_is_symlink(path)) {
    return(FALSE)
  }
  info <- tryCatch(
    fs::file_info(path, follow = FALSE),
    error = function(...) NULL
  )
  if (
    is.null(info) ||
      nrow(info) != 1L ||
      !identical(as.character(info$type), "file")
  ) {
    return(FALSE)
  }
  TRUE
}

artifact_recovery_directory <- function(path) {
  if (artifact_recovery_is_symlink(path)) {
    return(FALSE)
  }
  isTRUE(file.info(path)$isdir) &&
    isTRUE(file.access(path, 4L) == 0L)
}

artifact_recovery_is_symlink <- function(path) {
  link <- Sys.readlink(path)
  isTRUE(length(link) == 1L && !is.na(link) && nzchar(link))
}

artifact_recovery_file_size <- function(path) {
  size <- file.info(path)$size
  artifact_recovery_scalar_size(size)
}

artifact_recovery_scalar_size <- function(size) {
  size <- suppressWarnings(as.numeric(size))
  if (
    length(size) != 1L ||
      is.na(size) ||
      !is.finite(size) ||
      size < 0 ||
      size != floor(size)
  ) {
    artifact_abort("Artifact object size is invalid.")
  }
  size
}
