#' Create or reopen a local artifact store
#'
#' Create or reopen a local artifact store, save opaque bytes, and resolve an
#' exact revision. Saving grants no approval, access, or execution authority.
#'
#' @param path Directory for a Graft artifact store, distinct from a native
#'   graph store. Creation requires a missing or empty directory. Filesystem
#'   paths follow platform limits, independently of artifact identity byte limits.
#' @param create Whether to create a new store. Defaults to `FALSE`, which
#'   reopens an existing store.
#' @param max_bytes Maximum payload bytes per artifact to save or read in this
#'   handle. Dependency traversal also applies this limit to aggregate payloads.
#' @param max_revision_bytes Maximum encoded metadata bytes per revision to save
#'   or read through this handle, a positive whole number. Defaults to 1 MiB
#'   (`1024^2`), independently of payload and dependency-count bounds. Increase
#'   it for large dependency lists, including when reopening the store.
#' @param lock_timeout Seconds to wait while another process records a
#'   decision in the same stream. Defaults to 10. When the wait runs out, the
#'   call fails with a `graft_store_busy_error` and records nothing.
#' @details
#' Identity, media type, and reference strings are normalized to plain UTF-8
#' character values without R attributes.
#'
#' Local stores hold trusted files. Several R processes can write to one
#' store: content and revisions are saved under their SHA-256 digests, so
#' concurrent saves of the same bytes agree, and decisions in a stream are
#' serialized by a file lock, as PostgreSQL scopes are by an advisory lock. The
#' lock is an operating-system advisory lock (via the filelock package) on a
#' file under `locks/` in the store, so it only works where the file system
#' honours such locks; some network file systems do not. SHA-256 digests
#' identify content and metadata. Repeating an identical save returns the same
#' reference, while corrections retain earlier revisions. There is no mutable
#' latest pointer.
#'
#' Payloads are published before immutable revision metadata, using staged files
#' in the destination directory. A failed save can leave unreferenced bytes;
#' retries reuse verified content. Orphans are retained rather than deleted
#' automatically; a replacement planned with nothing to forget
#' ([graft_plan_replacement()]) copies everything but them. Every write also
#' holds the store's lock shared; see [graft_with_store_lock()]. Successful reads verify metadata, payload size, and digest.
#' Interrupted writes cannot produce a successful incomplete reference. The
#' interface does not promise power-loss durability, authorization, erasure, or
#' backup recovery. Applications control access and
#' policy.
#' Local handles have no open connections, so callers do not need to close them.
#' For transaction-scoped database persistence, use
#' [graft_store_postgres()] with the same artifact APIs.
#'
#' @returns
#' `graft_store()` returns a [LocalArtifactStore].
#'
#' @examples
#' path <- tempfile("artifacts-")
#' store <- graft_store(path, create = TRUE)
#' ref <- graft_save(store, "A retained report", "report:daily")
#' reopened <- graft_store(path)
#' graft_read(reopened, ref)@data
#' unlink(path, recursive = TRUE)
#' @export
graft_store <- function(
  path,
  create = FALSE,
  max_bytes = 64 * 1024^2,
  max_revision_bytes = 1024^2,
  lock_timeout = 10
) {
  artifact_check_path(path)
  if (!rlang::is_bool(create)) {
    artifact_abort("`create` must be TRUE or FALSE.")
  }
  artifact_check_limit(max_bytes, "max_bytes")
  artifact_check_limit(max_revision_bytes, "max_revision_bytes")
  if (
    !is.numeric(lock_timeout) ||
      length(lock_timeout) != 1L ||
      is.na(lock_timeout) ||
      !is.finite(lock_timeout) ||
      lock_timeout < 0
  ) {
    artifact_abort("`lock_timeout` must be one non-negative number of seconds.")
  }
  marker <- charToRaw('{"format":"graft-artifacts","version":1}')
  if (create) {
    if (file.exists(path) && !dir.exists(path)) {
      artifact_abort("`path` must be a missing or empty directory.")
    }
    if (dir.exists(path) && file.access(path, 4L) != 0L) {
      artifact_abort(
        "Cannot verify that the artifact directory is empty: directory is unreadable."
      )
    }
    if (
      dir.exists(path) &&
        length(list.files(path, all.files = TRUE, no.. = TRUE))
    ) {
      artifact_abort(
        "Creation requires an empty directory; use `create = FALSE` to reopen."
      )
    }
    if (!dir.exists(path) && !dir.create(path, recursive = TRUE)) {
      artifact_abort("Could not create the artifact directory.")
    }
    artifact_put(marker, file.path(path, "store.json"), 1024)
  }
  if (!identical(artifact_bytes(file.path(path, "store.json"), 1024), marker)) {
    artifact_abort("Unsupported artifact store marker.")
  }
  LocalArtifactStore(
    path = normalizePath(path, winslash = "/"),
    max_bytes = max_bytes,
    max_revision_bytes = max_revision_bytes,
    lock_timeout = lock_timeout
  )
}

#' Hold a store's lock while an application changes it
#'
#' Run code while holding the store's lock, so an application can make a
#' change that spans several Graft calls without another process writing in
#' between. Every write to a local store holds this lock shared, and
#' [graft_manifest()], [graft_plan_replacement()], [graft_replace()],
#' [graft_backup()], and [graft_restore()] hold it exclusively.
#'
#' A host that forgets an artifact by building a replacement store holds the
#' old store's lock exclusively while it plans, copies, and switches to the
#' replacement, and wraps each of its writes in a shared hold that first checks
#' the store is still current. A write that was waiting on the lock then sees
#' the switch and goes to the new store instead of the retired one.
#'
#' Graft calls inside `code` run under the lock already held. An exclusive
#' hold cannot be taken inside a shared one. PostgreSQL stores run `code`
#' directly: the host's transaction and scope lock already serialize it.
#'
#' @param store A handle returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param code Code to run while the lock is held.
#' @param exclusive `TRUE` to keep every other process out of the store,
#'   `FALSE` to share the lock with other writers.
#'
#' @returns The value of `code`. If the lock is not free within the store's
#'   `lock_timeout`, an error of class `graft_store_busy_error` is signalled
#'   and `code` is not run.
#'
#' @examples
#' path <- tempfile("artifacts-")
#' store <- graft_store(path, create = TRUE)
#' ref <- graft_with_store_lock(store, graft_save(store, "Evidence", "report"))
#' graft_read(store, ref)@data
#' unlink(path, recursive = TRUE)
#' @export
graft_with_store_lock <- function(store, code, exclusive = TRUE) {
  artifact_check_store(store)
  if (!rlang::is_bool(exclusive)) {
    artifact_abort("`exclusive` must be TRUE or FALSE.")
  }
  artifact_with_store_lock(store, exclusive, function() code)
}

artifact_save <- function(
  store,
  id,
  bytes,
  media_type,
  dependencies = list(),
  max_artifacts = 1000L
) {
  artifact_check_store(store)
  id <- artifact_check_text(id, "id")
  media_type <- artifact_check_text(media_type, "media_type")
  if (!is.raw(bytes)) {
    artifact_abort("`bytes` must be a raw vector.")
  }
  attributes(bytes) <- NULL
  if (length(bytes) > store@max_bytes) {
    artifact_abort("`bytes` exceeds the store byte bound.")
  }
  artifact_check_limit(max_artifacts, "max_artifacts")
  dependencies <- artifact_refs(dependencies, max_artifacts)
  artifact_dependency_closure(store, dependencies, max_artifacts)
  metadata <- artifact_metadata(id, bytes, media_type, dependencies)
  manifest <- artifact_encode(metadata)
  ref <- list(id = metadata$id, revision = artifact_sha(manifest))
  artifact_storage_put(
    store,
    "content",
    metadata$payload,
    bytes,
    store@max_bytes
  )
  artifact_storage_put(
    store,
    "revisions",
    ref$revision,
    manifest,
    store@max_revision_bytes
  )
  artifact_read(store, ref)
  ref
}

artifact_read <- function(store, ref) {
  artifact_check_store(store)
  ref <- artifact_check_ref(ref)
  manifest <- artifact_storage_read(
    store,
    "revisions",
    ref$revision,
    store@max_revision_bytes
  )
  if (!identical(artifact_sha(manifest), ref$revision)) {
    artifact_abort("Artifact revision digest mismatch.")
  }
  metadata <- artifact_decode(manifest)
  artifact_check_metadata(metadata)
  if (!identical(metadata$id, ref$id)) {
    artifact_abort("Artifact identity does not match the reference.")
  }
  bytes <- artifact_storage_read(
    store,
    "content",
    metadata$payload,
    store@max_bytes
  )
  if (
    length(bytes) != metadata$size ||
      !identical(artifact_sha(bytes), metadata$payload)
  ) {
    artifact_abort("Artifact payload digest or size mismatch.")
  }
  list(ref = ref, metadata = metadata, bytes = bytes)
}

artifact_abort <- function(message) {
  graft_abort("graft_artifact_error", message)
}

artifact_check_path <- function(path) {
  if (
    !rlang::is_string(path) ||
      !validUTF8(enc2utf8(path)) ||
      !nzchar(path)
  ) {
    artifact_abort("`path` must be a nonempty UTF-8 string.")
  }
}

artifact_check_text <- function(x, arg) {
  if (rlang::is_string(x)) {
    attributes(x) <- NULL
    x <- enc2utf8(x)
  }
  if (
    !rlang::is_string(x) ||
      !validUTF8(enc2utf8(x)) ||
      !nzchar(x) ||
      !identical(trimws(x), x) ||
      nchar(enc2utf8(x), type = "bytes") > 1024 ||
      grepl("[[:cntrl:]]", x)
  ) {
    artifact_abort(paste0(
      "`",
      arg,
      "` must be a nonempty, unpadded string of at most 1024 UTF-8 bytes without control characters."
    ))
  }
  x
}

artifact_check_limit <- function(x, arg) {
  if (
    !is.numeric(x) ||
      length(x) != 1L ||
      is.na(x) ||
      !is.finite(x) ||
      x < 1 ||
      x > .Machine$integer.max ||
      x != floor(x)
  ) {
    artifact_abort(paste0(
      "`",
      arg,
      "` must be a positive whole number no greater than the R integer limit."
    ))
  }
}

artifact_check_store <- function(store) {
  if (!S7::S7_inherits(store, ArtifactStore)) {
    artifact_abort("`store` must be a Graft artifact store handle.")
  }
  tryCatch(S7::validate(store), error = function(...) {
    artifact_abort("`store` must be a valid Graft artifact store handle.")
  })
  if (S7::S7_inherits(store, PostgresArtifactStore)) {
    graft_store_postgres(
      store@connection,
      store@scope,
      max_bytes = store@max_bytes,
      max_revision_bytes = store@max_revision_bytes
    )
    return(invisible(NULL))
  }
  if (!S7::S7_inherits(store, LocalArtifactStore)) {
    artifact_abort("`store` must be a Graft artifact store handle.")
  }
  graft_store(
    store@path,
    max_bytes = store@max_bytes,
    max_revision_bytes = store@max_revision_bytes
  )
  invisible(NULL)
}

artifact_check_digest <- function(x) {
  if (rlang::is_string(x)) {
    attributes(x) <- NULL
  }
  if (!rlang::is_string(x) || !grepl("^[0-9a-f]{64}$", x)) {
    artifact_abort(
      "An artifact digest must contain 64 lowercase hexadecimal characters."
    )
  }
  x
}

artifact_check_ref <- function(ref) {
  if (S7::S7_inherits(ref, ArtifactRef)) {
    ref <- artifact_ref_record(ref)
  }
  if (!is.list(ref) || !identical(names(ref), c("id", "revision"))) {
    artifact_abort(
      "An artifact reference must contain exactly `id` and `revision`."
    )
  }
  list(
    id = artifact_check_text(ref$id, "ref$id"),
    revision = artifact_check_digest(ref$revision)
  )
}

artifact_check_metadata <- function(metadata) {
  if (
    !is.list(metadata) ||
      !identical(
        names(metadata),
        c("format", "id", "payload", "size", "media_type", "dependencies")
      ) ||
      !identical(metadata$format, 1L)
  ) {
    artifact_abort("Unsupported artifact metadata.")
  }
  artifact_check_text(metadata$id, "metadata$id")
  artifact_check_text(metadata$media_type, "metadata$media_type")
  artifact_check_digest(metadata$payload)
  size <- metadata$size
  if (
    !is.numeric(size) ||
      length(size) != 1L ||
      is.na(size) ||
      !is.finite(size) ||
      size < 0 ||
      size > .Machine$integer.max ||
      size != floor(size)
  ) {
    artifact_abort("Invalid artifact payload size.")
  }
  dependencies <- artifact_refs(metadata$dependencies, .Machine$integer.max)
  if (!identical(dependencies, metadata$dependencies)) {
    artifact_abort("Artifact dependencies must be distinct unnamed references.")
  }
}

artifact_metadata <- function(id, bytes, media_type, dependencies) {
  list(
    format = 1L,
    id = enc2utf8(id),
    payload = artifact_sha(bytes),
    size = length(bytes),
    media_type = enc2utf8(media_type),
    dependencies = dependencies
  )
}

artifact_sha <- function(bytes) {
  digest::digest(bytes, algo = "sha256", serialize = FALSE)
}

artifact_encode <- function(value) {
  charToRaw(enc2utf8(as.character(jsonlite::toJSON(
    value,
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  ))))
}

artifact_decode <- function(bytes) {
  tryCatch(
    jsonlite::fromJSON(rawToChar(bytes), simplifyVector = FALSE),
    error = function(e) artifact_abort("Invalid artifact JSON metadata.")
  )
}

artifact_path <- function(store, kind, digest) {
  file.path(store@path, kind, digest)
}

S7::method(artifact_storage_read, LocalArtifactStore) <- function(
  store,
  kind,
  key,
  limit
) {
  path <- artifact_path(store, kind, key)
  # On Windows another writer's same-byte rename replaces an existing object,
  # which can leave it briefly unreadable, or briefly absent, to any reader.
  # A present object is retried for up to about a second. An absent one is
  # retried for about 0.2 seconds: a replacement's absent moment is far
  # shorter than that, and a missing object should still fail quickly.
  if (artifact_object_exists(path)) {
    return(artifact_settled_bytes(path, limit))
  }
  artifact_settled_bytes(path, limit, attempts = 5L)
}

artifact_object_exists <- function(path) file.exists(path)

S7::method(artifact_storage_put, LocalArtifactStore) <- function(
  store,
  kind,
  key,
  bytes,
  limit
) {
  artifact_with_store_lock(store, FALSE, function() {
    artifact_put(bytes, artifact_path(store, kind, key), limit)
  })
}

# A decision reads the stream's head and publishes the next sequence number,
# so two processes deciding at once could both publish the same number and
# fork the journal. Local stores hold an exclusive lock per stream for that
# read-then-write; PostgreSQL scopes already hold an advisory lock.
S7::method(artifact_with_stream_lock, LocalArtifactStore) <- function(
  store,
  stream,
  code
) {
  path <- artifact_lock_path(
    store,
    paste0(artifact_sha(charToRaw(stream)), ".lock")
  )
  lock <- artifact_lock(path, store@lock_timeout)
  if (is.null(lock)) {
    graft_abort(
      c("graft_store_busy_error", "graft_artifact_error"),
      paste0(
        "Another process is recording a decision in this stream; waited ",
        format(store@lock_timeout),
        " seconds. Retry with the same `key`."
      )
    )
  }
  on.exit(filelock::unlock(lock), add = TRUE)
  code()
}

# Every write holds the store's lock shared, and operations on the whole
# store (manifests, replacement plans and copies, backups, restores) hold it
# exclusively, so they never see a write half done and no write lands while
# they run. A process that already holds the lock runs nested work under it
# rather than locking again: filelock would lock the same file twice, and on
# POSIX releasing either lock releases both.
artifact_store_locks <- new.env(parent = emptyenv())

S7::method(artifact_with_store_lock, LocalArtifactStore) <- function(
  store,
  exclusive,
  code
) {
  held <- artifact_store_locks[[store@path]]
  if (!is.null(held)) {
    if (exclusive && !held) {
      artifact_abort(
        "An operation on the whole store cannot run inside a write to it."
      )
    }
    return(code())
  }
  lock <- artifact_lock(
    artifact_lock_path(store, "store.lock"),
    store@lock_timeout,
    exclusive = exclusive
  )
  if (is.null(lock)) {
    graft_abort(
      c("graft_store_busy_error", "graft_artifact_error"),
      paste0(
        "Another process is using this store; waited ",
        format(store@lock_timeout),
        " seconds. Retry later."
      )
    )
  }
  assign(store@path, exclusive, envir = artifact_store_locks)
  on.exit(
    {
      rm(list = store@path, envir = artifact_store_locks)
      filelock::unlock(lock)
    },
    add = TRUE
  )
  code()
}

# A backup's staging image is private to the process building it, and a closed
# backup image must not change, so neither takes a lock file: their work runs
# as if the lock were already held.
artifact_without_store_lock <- function(store, code) {
  if (!is.null(artifact_store_locks[[store@path]])) {
    return(code())
  }
  assign(store@path, TRUE, envir = artifact_store_locks)
  on.exit(rm(list = store@path, envir = artifact_store_locks), add = TRUE)
  code()
}

artifact_lock_path <- function(store, name) {
  dir <- file.path(store@path, "locks")
  if (!dir.exists(dir) && !artifact_create_dir(dir) && !dir.exists(dir)) {
    artifact_abort("Could not create the store's lock directory.")
  }
  file.path(dir, name)
}

artifact_lock <- function(path, timeout, exclusive = TRUE) {
  filelock::lock(path, exclusive = exclusive, timeout = timeout * 1000)
}

artifact_bytes <- function(path, limit) {
  info <- fs::file_info(path, fail = FALSE, follow = FALSE)
  size <- as.numeric(info$size)
  if (
    !identical(as.character(info$type), "file") ||
      is.na(size) ||
      size > limit
  ) {
    artifact_abort("Artifact file is missing or exceeds the byte bound.")
  }
  bytes <- tryCatch(
    readBin(path, "raw", n = size),
    error = function(e) artifact_abort("Could not read artifact bytes.")
  )
  if (length(bytes) != size) {
    artifact_abort("Artifact file changed during read.")
  }
  bytes
}

artifact_rename_file <- function(from, to) file.rename(from, to)

# Read a published file, retrying briefly while another process replaces it
# with the same bytes. A read that still fails after the retries is an error.
artifact_settled_bytes <- function(path, limit, attempts = 20L, wait = 0.05) {
  for (i in seq_len(attempts - 1L)) {
    bytes <- tryCatch(
      artifact_bytes(path, limit),
      graft_artifact_error = function(e) NULL
    )
    if (!is.null(bytes)) {
      return(bytes)
    }
    Sys.sleep(wait)
  }
  artifact_bytes(path, limit)
}
artifact_create_dir <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
}

artifact_put <- function(bytes, path, limit) {
  if (length(bytes) > limit) {
    artifact_abort("Artifact exceeds the byte bound.")
  }
  if (file.exists(path)) {
    if (!identical(artifact_settled_bytes(path, limit), bytes)) {
      artifact_abort("Immutable artifact path contains different bytes.")
    }
    return(invisible(NULL))
  }
  # Another process may create the directory between the check and ours.
  if (!dir.exists(dirname(path)) && !artifact_create_dir(dirname(path))) {
    if (!dir.exists(dirname(path))) {
      artifact_abort("Could not create artifact publication directory.")
    }
  }
  staging <- tempfile("staged-", tmpdir = dirname(path))
  on.exit(unlink(staging), add = TRUE)
  tryCatch(writeBin(bytes, staging), error = function(e) {
    artifact_abort("Could not stage artifact bytes.")
  })
  # Another process may publish the same digest first. Its rename can then
  # fail with a warning, or, on Windows where file.rename() replaces the
  # destination, replace ours while we verify it. Either way the path holds
  # these bytes, so the warning is dropped and the verifying read retries.
  published <- suppressWarnings(artifact_rename_file(staging, path))
  if (!published && !file.exists(path)) {
    artifact_abort(
      "Artifact publication failed; no successful reference issued."
    )
  }
  if (!identical(artifact_settled_bytes(path, limit), bytes)) {
    artifact_abort("Published artifact verification failed.")
  }
  invisible(NULL)
}
