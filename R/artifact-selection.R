#' Preserve an exact artifact selection
#'
#' Retain explicit roots and their complete dependency closure as an immutable
#' selection. Selection records content, not approval, permission or factual
#' truth.
#'
#' @param store A handle returned by [graft_artifact_store()] or
#'   [graft_artifact_store_postgres()].
#' @param roots Nonempty list of exact artifact references returned by
#'   [graft_artifact_save()]. Duplicate roots are removed, retaining first
#'   order.
#' @param max_artifacts Maximum number of distinct references traversed. Each
#'   traversal also limits the sum of payload sizes to the store's `max_bytes`.
#' @param max_metadata_bytes Maximum encoded selection metadata bytes to save or
#'   read, a positive whole number. Defaults to 1 MiB (`1024^2`), independently
#'   of
#'   artifact count and payload bounds. Increase it for many long references and
#'   supply the same or a larger limit when reading that selection.
#' @param selection Selection digest returned by `graft_artifact_select()`.
#'
#' @details
#' Save dependencies with `graft_artifact_save(dependencies = list(ref, ...))`.
#' Dependencies are exact references, not latest pointers or inferred relations.
#' Dictionary and vocabulary releases may be stored as opaque artifacts and
#' pinned alongside evidence. Graft does not evaluate their expressions or infer
#' ontology relationships. Direct dependency and root order are significant;
#' duplicates retain their first occurrence. Closure order is breadth-first.
#'
#' Both selection functions verify every selected payload. Reads independently
#' recompute the dependency closure and reject altered or incomplete selections.
#' The returned references can be resolved with [graft_artifact_read()].
#' Corrections do not change an earlier selection. Applications separately
#' decide
#' whether a selection may be consulted for a purpose, and enforce access.
#' Storage limits and publication guarantees are those of
#' [graft_artifact_store()].
#'
#' @returns
#' `graft_artifact_select()` returns an immutable SHA-256 selection digest.
#' `graft_artifact_read_selection()` returns `id`, `roots` and `artifacts`,
#' where
#' `artifacts` contains the complete ordered list of exact dependency
#' references.
#'
#' @examples
#' path <- tempfile("artifacts-")
#' store <- graft_artifact_store(path, create = TRUE)
#' source <- graft_artifact_save(store, "source", charToRaw("Evidence"),
#' "text/plain")
#' report <- graft_artifact_save(
#'   store, "report", charToRaw("Interpretation"), "text/plain",
#'   dependencies = list(source)
#' )
#' selection <- graft_artifact_select(store, list(report))
#' graft_artifact_read_selection(store, selection)$artifacts
#' unlink(path, recursive = TRUE)
#' @export
graft_artifact_select <- function(
  store,
  roots,
  max_artifacts = 1000L,
  max_metadata_bytes = 1024^2
) {
  artifact_check_store(store)
  artifact_check_limit(max_artifacts, "max_artifacts")
  artifact_check_limit(max_metadata_bytes, "max_metadata_bytes")
  roots <- artifact_refs(roots, max_artifacts)
  if (!length(roots)) {
    artifact_abort("`roots` must contain at least one artifact reference.")
  }
  artifacts <- artifact_dependency_closure(store, roots, max_artifacts)
  bytes <- artifact_encode(list(
    format = 1L,
    roots = roots,
    artifacts = artifacts
  ))
  selection <- artifact_sha(bytes)
  artifact_storage_put(
    store,
    "selections",
    selection,
    bytes,
    max_metadata_bytes
  )
  graft_artifact_read_selection(
    store,
    selection,
    max_artifacts,
    max_metadata_bytes
  )
  selection
}

#' @rdname graft_artifact_select
#' @export
graft_artifact_read_selection <- function(
  store,
  selection,
  max_artifacts = 1000L,
  max_metadata_bytes = 1024^2
) {
  artifact_check_store(store)
  selection <- artifact_check_digest(selection)
  artifact_check_limit(max_artifacts, "max_artifacts")
  artifact_check_limit(max_metadata_bytes, "max_metadata_bytes")
  bytes <- artifact_storage_read(
    store,
    "selections",
    selection,
    max_metadata_bytes
  )
  if (!identical(artifact_sha(bytes), selection)) {
    artifact_abort("Artifact selection digest mismatch.")
  }
  value <- artifact_decode(bytes)
  if (
    !is.list(value) ||
      !identical(names(value), c("format", "roots", "artifacts")) ||
      !identical(value$format, 1L)
  ) {
    artifact_abort("Unsupported artifact selection metadata.")
  }
  roots <- artifact_refs(value$roots, max_artifacts)
  artifacts <- artifact_refs(value$artifacts, max_artifacts)
  if (
    !length(roots) ||
      !identical(roots, value$roots) ||
      !identical(artifacts, value$artifacts) ||
      !identical(
        artifact_dependency_closure(store, roots, max_artifacts),
        artifacts
      )
  ) {
    artifact_abort("Artifact selection is incomplete or altered.")
  }
  list(id = selection, roots = roots, artifacts = artifacts)
}

artifact_refs <- function(refs, limit) {
  if (!is.list(refs) || is.object(refs)) {
    artifact_abort(
      "Artifact references must be a list within the artifact bound."
    )
  }
  refs <- lapply(refs, artifact_check_ref)
  refs <- unname(refs)
  refs <- refs[!duplicated(vapply(refs, artifact_ref_key, character(1)))]
  if (length(refs) > limit) {
    artifact_abort(
      "Artifact references must be a list within the artifact bound."
    )
  }
  refs
}

artifact_ref_key <- function(ref) paste(ref$id, ref$revision, sep = "\n")

artifact_dependency_closure <- function(store, roots, max_artifacts) {
  pending <- roots
  keys <- vapply(roots, artifact_ref_key, character(1))
  result <- list()
  size <- 0
  cursor <- 1L
  while (cursor <= length(pending)) {
    ref <- pending[[cursor]]
    item <- graft_artifact_read(store, ref)
    size <- size + length(item$bytes)
    if (size > store$max_bytes) {
      artifact_abort(
        "Artifact dependency closure exceeds the total byte bound."
      )
    }
    result[[cursor]] <- ref
    for (dependency in item$metadata$dependencies) {
      key <- artifact_ref_key(dependency)
      if (!key %in% keys) {
        if (length(pending) >= max_artifacts) {
          artifact_abort(
            "Artifact dependency closure exceeds the artifact bound."
          )
        }
        pending[[length(pending) + 1L]] <- dependency
        keys <- c(keys, key)
      }
    }
    cursor <- cursor + 1L
  }
  result
}
