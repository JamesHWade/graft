# EXPERIMENT ONLY: local, trusted, single-writer files; no production storage API.
artifact_error <- function(message) {
  rlang::abort(message, class = "artifact_experiment_error")
}

artifact_json <- function(value) {
  as.character(jsonlite::toJSON(
    value,
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  ))
}

artifact_hash <- function(bytes) {
  digest::digest(bytes, algo = "sha256", serialize = FALSE)
}

artifact_read_bytes <- function(path, max_bytes = 1024^2) {
  size <- file.info(path)$size
  if (is.na(size) || size > max_bytes) {
    artifact_error("Content missing or exceeds experiment byte bound.")
  }
  readBin(path, "raw", n = size)
}

artifact_read_json <- function(path) {
  jsonlite::fromJSON(
    rawToChar(artifact_read_bytes(path)),
    simplifyVector = FALSE
  )
}

artifact_rename <- function(from, to) file.rename(from, to)

artifact_write <- function(bytes, path, replace = FALSE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path) && !replace) {
    if (!identical(artifact_read_bytes(path), bytes)) {
      artifact_error("Immutable path contains different bytes.")
    }
    return(invisible(path))
  }
  staging <- tempfile("staged-", tmpdir = dirname(path))
  on.exit(unlink(staging))
  writeBin(bytes, staging)
  backup <- NULL
  if (file.exists(path)) {
    backup <- tempfile("backup-", tmpdir = dirname(path))
    if (!artifact_rename(path, backup)) {
      artifact_error("Could not stage existing content for replacement.")
    }
  }
  if (!artifact_rename(staging, path)) {
    restored <- is.null(backup) || artifact_rename(backup, path)
    artifact_error(
      if (restored) {
        "Publication failed; previous content restored; no success receipt issued."
      } else {
        paste(
          "Publication and restore failed; previous content retained at",
          backup
        )
      }
    )
  }
  if (!is.null(backup)) {
    unlink(backup)
  }
  invisible(path)
}

artifact_digest_path <- function(root, kind, digest) {
  if (
    !is.character(digest) ||
      length(digest) != 1L ||
      is.na(digest) ||
      !grepl("^[0-9a-f]{64}$", digest)
  ) {
    artifact_error("Invalid content digest.")
  }
  file.path(root, kind, digest)
}

artifact_verify <- function(store, metadata) {
  bytes <- artifact_read_bytes(artifact_digest_path(
    store$root,
    "content",
    metadata$payload
  ))
  if (
    length(bytes) != metadata$size ||
      !identical(artifact_hash(bytes), metadata$payload)
  ) {
    artifact_error("Content digest or size mismatch.")
  }
  bytes
}

artifact_save <- function(
  store,
  id,
  path,
  media_type,
  dependencies = list(),
  meaning = list(),
  producer = "synthetic-host:v1",
  expected = artifact_current(store, id),
  fail_after_bytes = FALSE,
  fail_after_publish = FALSE
) {
  if (!grepl("^artifact:[a-z][a-z0-9:-]*$", id) || length(id) != 1L) {
    artifact_error("Invalid artifact identity.")
  }
  allowed <- c(
    "text/markdown",
    "application/vnd.apache.parquet",
    "image/png",
    "application/json",
    "application/yaml"
  )
  if (!media_type %in% allowed) {
    artifact_error("Unsupported media type.")
  }
  # Verify every exact dependency before publishing the new revision.
  artifact_closure(store, dependencies)
  current <- artifact_all_current(store)
  if (is.null(current[[id]]) && length(current) >= store$capacity) {
    artifact_error("Current index exceeds experiment bound.")
  }
  bytes <- artifact_read_bytes(path)
  payload <- artifact_hash(bytes)
  metadata <- list(
    format = 1L,
    id = id,
    payload = payload,
    size = length(bytes),
    media_type = media_type,
    dependencies = unname(dependencies),
    meaning = meaning,
    producer = producer
  )
  revision <- artifact_hash(charToRaw(artifact_json(metadata)))
  ref <- list(id = id, revision = revision)
  if (identical(artifact_current(store, id), ref)) {
    artifact_resolve(store, ref)
    return(ref)
  }
  if (!identical(artifact_current(store, id), expected)) {
    artifact_error("Stale expected revision; review the intervening change.")
  }
  artifact_write(bytes, artifact_digest_path(store$root, "content", payload))
  if (fail_after_bytes) {
    artifact_error("Injected interruption after bytes, before metadata.")
  }
  artifact_publish(store, metadata, ref)
  if (fail_after_publish) {
    artifact_error("Injected lost acknowledgment after publication.")
  }
  artifact_resolve(store, ref)
  ref
}

artifact_resolve <- function(store, ref) {
  metadata <- artifact_metadata(store, ref)
  if (
    !identical(metadata$id, ref$id) ||
      !identical(
        artifact_hash(charToRaw(artifact_json(metadata))),
        ref$revision
      )
  ) {
    artifact_error("Manifest identity or revision digest mismatch.")
  }
  list(ref = ref, metadata = metadata, bytes = artifact_verify(store, metadata))
}

artifact_preview <- function(store, ref, limit = 120L) {
  item <- artifact_resolve(store, ref)
  if (item$metadata$media_type == "text/markdown") {
    return(substr(rawToChar(item$bytes), 1L, limit))
  }
  if (item$metadata$media_type == "application/vnd.apache.parquet") {
    conn <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(conn, shutdown = TRUE))
    path <- artifact_digest_path(store$root, "content", item$metadata$payload)
    query <- paste0(
      "SELECT * FROM read_parquet(",
      DBI::dbQuoteString(conn, path),
      ") LIMIT 2"
    )
    return(DBI::dbGetQuery(conn, query))
  }
  # Images are explicit verified references; the caller chooses a renderer.
  item$metadata[c("media_type", "size", "payload")]
}

artifact_closure <- function(store, roots) {
  result <- list()
  pending <- roots
  while (length(pending)) {
    ref <- pending[[1L]]
    pending <- pending[-1L]
    key <- paste(ref$id, ref$revision, sep = "@")
    if (key %in% names(result)) {
      next
    }
    if (length(result) >= 50L) {
      artifact_error("Selection exceeds experiment bound.")
    }
    item <- artifact_resolve(store, ref)
    result[[key]] <- ref
    pending <- c(pending, item$metadata$dependencies)
  }
  unname(result)
}

artifact_approve <- function(store, roots, purpose) {
  if (!is.character(purpose) || length(purpose) != 1L || !nzchar(purpose)) {
    artifact_error("An explicit reuse purpose is required.")
  }
  basis <- list(
    format = 1L,
    purpose = purpose,
    roots = roots,
    selection = artifact_closure(store, roots)
  )
  bytes <- charToRaw(artifact_json(basis))
  id <- artifact_hash(bytes)
  artifact_write(bytes, artifact_digest_path(store$root, "selections", id))
  # This explicit fixture host action is approval, never inferred from saving.
  artifact_write(
    charToRaw(artifact_json(list(selection = id, eligible = TRUE))),
    artifact_digest_path(store$root, "policy", id),
    replace = TRUE
  )
  id
}

artifact_read_basis <- function(store, id, purpose = NULL, consult = TRUE) {
  bytes <- artifact_read_bytes(artifact_digest_path(
    store$root,
    "selections",
    id
  ))
  if (!identical(artifact_hash(bytes), id)) {
    artifact_error("Selection digest mismatch.")
  }
  basis <- jsonlite::fromJSON(rawToChar(bytes), simplifyVector = FALSE)
  if (consult) {
    policy_path <- artifact_digest_path(store$root, "policy", id)
    if (!file.exists(policy_path)) {
      artifact_error("No host approval for consultation.")
    }
    policy <- artifact_read_json(policy_path)
    if (
      !isTRUE(policy$eligible) ||
        !identical(policy$selection, id) ||
        !identical(basis$purpose, purpose)
    ) {
      artifact_error("Selection is not eligible for this use.")
    }
  }
  if (!identical(artifact_closure(store, basis$roots), basis$selection)) {
    artifact_error("Incomplete or altered dependency selection.")
  }
  lapply(basis$selection, function(ref) artifact_resolve(store, ref))
}

artifact_review <- function(store, id) {
  items <- artifact_read_basis(store, id, consult = FALSE)
  changed <- vapply(
    items,
    function(item) {
      !identical(artifact_current(store, item$ref$id), item$ref)
    },
    logical(1)
  )
  vapply(items[changed], function(item) item$ref$id, character(1))
}

artifact_revoke <- function(store, id) {
  # Verify the retained selection; revoking one basis cannot affect another.
  artifact_read_basis(store, id, consult = FALSE)
  artifact_write(
    charToRaw(artifact_json(list(selection = id, eligible = FALSE))),
    artifact_digest_path(store$root, "policy", id),
    replace = TRUE
  )
}

artifact_index <- function(store) {
  # Derived search input only: discard and recreate without losing history.
  refs <- artifact_all_current(store)
  lapply(refs, function(ref) {
    item <- artifact_resolve(store, ref)
    list(
      id = ref$id,
      revision = ref$revision,
      preview = artifact_preview(store, ref)
    )
  })
}
