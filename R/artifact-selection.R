artifact_select <- function(
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
  artifact_read_selection(
    store,
    selection,
    max_artifacts,
    max_metadata_bytes
  )
  selection
}

artifact_read_selection <- function(
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
    item <- artifact_read(store, ref)
    size <- size + length(item$bytes)
    if (size > store@max_bytes) {
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
