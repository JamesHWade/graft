#' Preserve immutable artifact content
#'
#' Create or reopen a local artifact store, save opaque bytes, and resolve an
#' exact revision. Saving grants no approval, access or execution authority.
#'
#' @param path Directory for a Graft artifact store, distinct from a native
#'   graph store. Creation requires a missing or empty directory.
#' @param create Create a new store? Defaults to `FALSE` for safe reopening.
#' @param max_bytes Maximum payload bytes per artifact to save or read in this
#'   handle. Dependency traversal also applies this limit to aggregate payloads.
#' @param max_revision_bytes Maximum encoded metadata bytes per revision to save
#'   or
#'   read through this handle, a positive whole number. Defaults to 1 MiB
#'   (`1024^2`), independently of payload and dependency-count bounds. Increase
#'   it for large dependency lists, including when reopening the store.
#' @param store A handle returned by `graft_artifact_store()`.
#' @param id Stable, nonempty artifact identity chosen by the caller, at most
#'   1024 UTF-8 bytes, without padding or control characters.
#' @param bytes Raw vector containing the complete payload. Content is never
#'   deserialized or executed by these functions.
#' @param media_type Nonempty media type describing the opaque payload, at most
#'   1024 UTF-8 bytes, without padding or control characters.
#' @param dependencies List of exact dependency references. The complete closure
#'   is verified before saving. No relationships are inferred from payloads.
#' @param max_artifacts Maximum distinct dependency references traversed before
#'   saving. Their total payload size is also limited by `max_bytes`.
#' @param ref Exact reference: a list with `id` and `revision` strings, as
#'   returned by `graft_artifact_save()`.
#'
#' @details
#' This interface supports trusted local files with one writer. SHA-256 digests
#' identify content and metadata. Identical saves return the same reference;
#' corrections retain earlier revisions. There is no mutable latest pointer.
#'
#' Payloads are published before immutable revision metadata, using staged files
#' in the destination directory. A failed save can leave unreferenced bytes;
#' retries reuse verified content. Orphans are retained rather than deleted
#' automatically. Successful reads verify metadata, payload size and digest.
#' Interrupted writes cannot yield a successful incomplete reference, but this
#' interface does not promise power-loss durability, concurrent publication,
#' authorization, erasure or backup recovery. Applications own access and
#' policy.
#' Handles contain no open connections and need no closing.
#'
#' @returns
#' `graft_artifact_store()` returns a local store handle.
#' `graft_artifact_save()` returns a list containing `id` and `revision`.
#' `graft_artifact_read()` returns `ref`, `metadata` and verified raw `bytes`.
#'
#' @examples
#' path <- tempfile("artifacts-")
#' store <- graft_artifact_store(path, create = TRUE)
#' ref <- graft_artifact_save(
#'   store, "report:daily", charToRaw("A retained report"), "text/plain"
#' )
#' reopened <- graft_artifact_store(path)
#' rawToChar(graft_artifact_read(reopened, ref)$bytes)
#' unlink(path, recursive = TRUE)
#' @export
graft_artifact_store <- function(
  path,
  create = FALSE,
  max_bytes = 64 * 1024^2,
  max_revision_bytes = 1024^2
) {
  artifact_check_text(path, "path")
  if (!rlang::is_bool(create)) {
    artifact_abort("`create` must be TRUE or FALSE.")
  }
  artifact_check_limit(max_bytes, "max_bytes")
  artifact_check_limit(max_revision_bytes, "max_revision_bytes")
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
  structure(
    list(
      path = normalizePath(path, winslash = "/"),
      max_bytes = max_bytes,
      max_revision_bytes = max_revision_bytes
    ),
    class = "graft_artifact_store"
  )
}

#' @rdname graft_artifact_store
#' @export
graft_artifact_save <- function(
  store,
  id,
  bytes,
  media_type,
  dependencies = list(),
  max_artifacts = 1000L
) {
  artifact_check_store(store)
  artifact_check_text(id, "id")
  artifact_check_text(media_type, "media_type")
  if (!is.raw(bytes) || length(bytes) > store$max_bytes) {
    artifact_abort("`bytes` must be a raw vector within the store byte bound.")
  }
  artifact_check_limit(max_artifacts, "max_artifacts")
  dependencies <- artifact_refs(dependencies, max_artifacts)
  artifact_dependency_closure(store, dependencies, max_artifacts)
  metadata <- list(
    format = 1L,
    id = enc2utf8(id),
    payload = artifact_sha(bytes),
    size = length(bytes),
    media_type = enc2utf8(media_type),
    dependencies = dependencies
  )
  manifest <- artifact_encode(metadata)
  ref <- list(id = metadata$id, revision = artifact_sha(manifest))
  artifact_put(
    bytes,
    artifact_path(store, "content", metadata$payload),
    store$max_bytes
  )
  artifact_put(
    manifest,
    artifact_path(store, "revisions", ref$revision),
    store$max_revision_bytes
  )
  graft_artifact_read(store, ref)
  ref
}

#' @rdname graft_artifact_store
#' @export
graft_artifact_read <- function(store, ref) {
  artifact_check_store(store)
  artifact_check_ref(ref)
  manifest <- artifact_bytes(
    artifact_path(store, "revisions", ref$revision),
    store$max_revision_bytes
  )
  if (!identical(artifact_sha(manifest), ref$revision)) {
    artifact_abort("Artifact revision digest mismatch.")
  }
  metadata <- artifact_decode(manifest)
  artifact_check_metadata(metadata)
  if (!identical(metadata$id, ref$id)) {
    artifact_abort("Artifact identity does not match the reference.")
  }
  bytes <- artifact_bytes(
    artifact_path(store, "content", metadata$payload),
    store$max_bytes
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
  rlang::abort(message, class = "graft_artifact_error")
}

artifact_check_text <- function(x, arg) {
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
  if (
    !inherits(store, "graft_artifact_store") ||
      !identical(names(store), c("path", "max_bytes", "max_revision_bytes"))
  ) {
    artifact_abort("`store` must be a Graft artifact store handle.")
  }
  graft_artifact_store(
    store$path,
    max_bytes = store$max_bytes,
    max_revision_bytes = store$max_revision_bytes
  )
  invisible(NULL)
}

artifact_check_digest <- function(x) {
  if (!rlang::is_string(x) || !grepl("^[0-9a-f]{64}$", x)) {
    artifact_abort(
      "An artifact digest must contain 64 lowercase hexadecimal characters."
    )
  }
}

artifact_check_ref <- function(ref) {
  if (!is.list(ref) || !identical(names(ref), c("id", "revision"))) {
    artifact_abort(
      "An artifact reference must contain exactly `id` and `revision`."
    )
  }
  artifact_check_text(ref$id, "ref$id")
  artifact_check_digest(ref$revision)
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
  file.path(store$path, kind, digest)
}

artifact_bytes <- function(path, limit) {
  size <- file.info(path)$size
  if (is.na(size) || dir.exists(path) || size > limit) {
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

artifact_put <- function(bytes, path, limit) {
  if (length(bytes) > limit) {
    artifact_abort("Artifact exceeds the byte bound.")
  }
  if (file.exists(path)) {
    if (!identical(artifact_bytes(path, limit), bytes)) {
      artifact_abort("Immutable artifact path contains different bytes.")
    }
    return(invisible(NULL))
  }
  if (
    !dir.exists(dirname(path)) && !dir.create(dirname(path), recursive = TRUE)
  ) {
    artifact_abort("Could not create artifact publication directory.")
  }
  staging <- tempfile("staged-", tmpdir = dirname(path))
  on.exit(unlink(staging), add = TRUE)
  tryCatch(writeBin(bytes, staging), error = function(e) {
    artifact_abort("Could not stage artifact bytes.")
  })
  if (!artifact_rename_file(staging, path)) {
    artifact_abort(
      "Artifact publication failed; no successful reference issued."
    )
  }
  if (!identical(artifact_bytes(path, limit), bytes)) {
    artifact_abort("Published artifact verification failed.")
  }
  invisible(NULL)
}
