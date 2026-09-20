#' Plan and build a bounded artifact-store replacement
#'
#' Compute an operational replacement plan after forgetting exact artifact
#' revisions and/or complete decision streams. The plan preserves every
#' revision which is not a forgotten revision or a transitive reverse
#' dependent, then retains only content referenced by those revisions. A
#' selection is removed when any of its exact references is removed. A whole
#' decision stream is removed when any historical record names a removed
#' selection, or when the stream is explicitly requested.
#'
#' @param store A handle returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param forget A list of exact artifact references returned by
#'   [graft_save()]. It may be empty when `forget_streams` is
#'   nonempty.
#' @param forget_streams Character vector of complete decision stream names to
#'   remove. The names must already exist in the source inventory.
#' @param max_objects Maximum number of inventoried objects.
#' @param max_total_bytes Maximum total bytes inventoried across objects.
#' @param max_metadata_bytes Maximum aggregate encoded bytes allowed while
#'   reading selection metadata and complete decision journals. Revision
#'   metadata uses the source and target store `max_revision_bytes` limits.
#' @param source A source artifact-store handle for a replacement operation.
#' @param target An empty artifact-store handle to receive the replacement.
#' @param plan A plan returned by
#'   [graft_plan_replacement()]. The plan is operational data; it is
#'   not an authorization or approval record.
#'
#' @details
#' The inventory is bounded and must enumerate every artifact revision,
#' selection, decision record, and content object in the source store. Opaque
#' payload bytes are never scanned for identifiers, private fields, reasons, or
#' other erasure roots. The host must supply all additional roots and streams
#' required by its Forget policy, including copies outside this artifact store.
#'
#' Planning does not authorize Forget and does not delete anything. Replacement
#' copies verified objects into a new empty store. The source is never changed.
#' A copy or verification failure can leave a partial target; the host must
#' quarantine and discard that target and rebuild a new empty target. Local
#' stores require quiesced single-writer access. PostgreSQL callers must hold
#' the host transaction and scope lock for the operation.
#'
#' @returns
#' `graft_plan_replacement()` returns a list with format
#' `graft-artifact-replacement/1`, source and target manifests, canonical
#' Forget roots and streams, limits, and removed artifact, selection, and
#' stream identities. `graft_replace()` returns the verified target
#' manifest only after the source and target have been checked again.
#'
#' @examples
#' path <- tempfile("artifacts-")
#' replacement_path <- tempfile("replacement-")
#' store <- graft_store(path, create = TRUE)
#' target <- graft_store(replacement_path, create = TRUE)
#' ref <- graft_save(store, "Evidence", "report")
#' plan <- graft_plan_replacement(store, list(ref))
#' graft_replace(store, target, plan)
#' unlink(path, recursive = TRUE)
#' unlink(replacement_path, recursive = TRUE)
#' @export
graft_plan_replacement <- function(
  store,
  forget,
  forget_streams = character(),
  max_objects = 10000L,
  max_total_bytes = 64 * 1024^2,
  max_metadata_bytes = 1024^2
) {
  artifact_recovery_preflight_store(store)
  artifact_check_store(store)
  limits <- artifact_replacement_limits(
    max_objects,
    max_total_bytes,
    max_metadata_bytes
  )
  if (
    S7::S7_inherits(forget, ArtifactRef) ||
      (is.list(forget) &&
        length(forget) &&
        all(vapply(forget, S7::S7_inherits, logical(1), class = ArtifactRef)))
  ) {
    forget <- artifact_refs_records(forget)
  }
  forget <- artifact_refs(forget, limits$max_objects)
  forget_streams <- artifact_replacement_stream_names(forget_streams)
  if (!length(forget) && !length(forget_streams)) {
    artifact_abort(
      "At least one artifact reference or decision stream is required."
    )
  }
  snapshot <- artifact_recovery_snapshot(
    store,
    max_objects = limits$max_objects,
    max_total_bytes = limits$max_total_bytes,
    max_metadata_bytes = limits$max_metadata_bytes
  )
  artifact_replacement_plan_from_snapshot(
    snapshot,
    forget,
    forget_streams,
    limits
  )
}

#' @rdname graft_plan_replacement
#' @export
graft_replace <- function(source, target, plan) {
  artifact_recovery_preflight_store(source)
  artifact_recovery_preflight_store(target)
  artifact_check_store(source)
  artifact_check_store(target)
  checked <- artifact_replacement_check_plan(plan)
  recomputed <- graft_plan_replacement(
    source,
    checked$forget,
    checked$forget_streams,
    max_objects = checked$limits$max_objects,
    max_total_bytes = checked$limits$max_total_bytes,
    max_metadata_bytes = checked$limits$max_metadata_bytes
  )
  if (!identical(recomputed, checked)) {
    artifact_abort(
      "Artifact replacement plan does not match the current source inventory."
    )
  }

  target_snapshot <- artifact_recovery_snapshot(
    target,
    max_objects = checked$limits$max_objects,
    max_total_bytes = checked$limits$max_total_bytes,
    max_metadata_bytes = checked$limits$max_metadata_bytes
  )
  if (length(target_snapshot$manifest$objects)) {
    artifact_abort(
      "Artifact replacement target must be an empty object store."
    )
  }

  for (object in checked$target$objects) {
    source_limit <- artifact_replacement_object_limit(
      source,
      object$kind,
      checked$limits$max_metadata_bytes
    )
    target_limit <- artifact_replacement_object_limit(
      target,
      object$kind,
      checked$limits$max_metadata_bytes
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
          "Source object `",
          object$kind,
          "/",
          object$key,
          "` changed during replacement."
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

  source_after <- artifact_recovery_snapshot(
    source,
    max_objects = checked$limits$max_objects,
    max_total_bytes = checked$limits$max_total_bytes,
    max_metadata_bytes = checked$limits$max_metadata_bytes
  )
  if (!identical(source_after$manifest, checked$source)) {
    artifact_abort("Source manifest changed during replacement.")
  }
  target_after <- artifact_recovery_snapshot(
    target,
    max_objects = checked$limits$max_objects,
    max_total_bytes = checked$limits$max_total_bytes,
    max_metadata_bytes = checked$limits$max_metadata_bytes
  )
  if (!identical(target_after$manifest, checked$target)) {
    artifact_abort("Replacement target manifest did not verify.")
  }
  target_after$manifest
}

artifact_replacement_limits <- function(
  max_objects,
  max_total_bytes,
  max_metadata_bytes
) {
  artifact_check_limit(max_objects, "max_objects")
  artifact_check_limit(max_total_bytes, "max_total_bytes")
  artifact_check_limit(max_metadata_bytes, "max_metadata_bytes")
  list(
    max_objects = as.integer(max_objects),
    max_total_bytes = as.integer(max_total_bytes),
    max_metadata_bytes = as.integer(max_metadata_bytes)
  )
}

artifact_replacement_stream_names <- function(streams) {
  if (!is.character(streams)) {
    artifact_abort("`forget_streams` must be a character vector.")
  }
  streams <- unname(vapply(
    streams,
    artifact_check_text,
    character(1),
    arg = "forget_streams"
  ))
  unname(sort(unique(streams), method = "radix"))
}

artifact_replacement_snapshot_streams <- function(streams) {
  if (!is.list(streams)) {
    artifact_abort("Artifact recovery streams must be a list.")
  }
  records <- unname(streams)
  names <- names(streams)
  if (is.null(names)) {
    names <- character()
  }
  if (!is.character(names) || length(records) != length(names)) {
    artifact_abort("Artifact recovery streams have an invalid shape.")
  }
  names <- unname(vapply(
    names,
    artifact_check_text,
    character(1),
    arg = "stream"
  ))
  if (anyDuplicated(names)) {
    artifact_abort("Artifact recovery streams must have distinct names.")
  }
  list(records = records, names = names)
}

artifact_replacement_plan_from_snapshot <- function(
  snapshot,
  forget,
  forget_streams,
  limits
) {
  if (
    !is.list(snapshot) ||
      !identical(
        names(snapshot),
        c("manifest", "artifacts", "selections", "streams")
      )
  ) {
    artifact_abort("Artifact recovery snapshot has an invalid shape.")
  }
  source <- snapshot$manifest
  artifacts <- snapshot$artifacts
  selections <- snapshot$selections
  streams <- artifact_replacement_snapshot_streams(snapshot$streams)
  revision_objects <- source$objects[
    vapply(source$objects, \(x) identical(x$kind, "revisions"), logical(1))
  ]
  revision_keys <- vapply(revision_objects, \(x) x$key, character(1))
  artifact_keys <- vapply(
    artifacts,
    \(item) item$ref$revision,
    character(1)
  )
  if (
    !identical(
      sort(revision_keys, method = "radix"),
      sort(artifact_keys, method = "radix")
    )
  ) {
    artifact_abort(
      "Artifact recovery revisions do not match the source manifest."
    )
  }
  selection_objects <- source$objects[
    vapply(source$objects, \(x) identical(x$kind, "selections"), logical(1))
  ]
  selection_keys <- vapply(selection_objects, \(x) x$key, character(1))
  selection_ids <- vapply(selections, \(x) x$id, character(1))
  if (
    !identical(
      sort(selection_keys, method = "radix"),
      sort(selection_ids, method = "radix")
    )
  ) {
    artifact_abort(
      "Artifact recovery selections do not match the source manifest."
    )
  }

  stream_prefixes <- vapply(
    streams$names,
    \(stream) paste0(artifact_sha(charToRaw(stream)), "/"),
    character(1)
  )
  decision_objects <- source$objects[
    vapply(source$objects, \(x) identical(x$kind, "decisions"), logical(1))
  ]
  if (length(decision_objects)) {
    known_decision <- vapply(
      decision_objects,
      \(object) any(startsWith(object$key, stream_prefixes)),
      logical(1)
    )
    if (!all(known_decision)) {
      artifact_abort(
        "Artifact recovery decisions include an unknown stream."
      )
    }
  }

  artifact_key <- vapply(
    artifacts,
    \(item) artifact_ref_key(item$ref),
    character(1)
  )
  forget_keys <- vapply(forget, artifact_ref_key, character(1))
  missing <- setdiff(forget_keys, artifact_key)
  if (length(missing)) {
    artifact_abort("Every forgotten artifact reference must exist.")
  }
  removed_keys <- forget_keys
  repeat {
    added <- vapply(
      artifacts,
      function(item) {
        key <- artifact_ref_key(item$ref)
        if (key %in% removed_keys) {
          return(FALSE)
        }
        dependencies <- item$metadata$dependencies
        dependency_keys <- vapply(dependencies, artifact_ref_key, character(1))
        if (!all(dependency_keys %in% artifact_key)) {
          artifact_abort(
            "Artifact recovery revision dependencies are incomplete."
          )
        }
        any(dependency_keys %in% removed_keys)
      },
      logical(1)
    )
    additions <- artifact_key[added]
    if (!length(additions)) {
      break
    }
    removed_keys <- unique(c(removed_keys, additions))
  }
  removed_artifacts <- lapply(artifacts, function(item) {
    if (artifact_ref_key(item$ref) %in% removed_keys) item$ref else NULL
  })
  removed_artifacts <- unname(Filter(Negate(is.null), removed_artifacts))
  removed_artifact_keys <- vapply(
    removed_artifacts,
    \(ref) ref$revision,
    character(1)
  )

  removed_selection <- vapply(
    selections,
    function(selection) {
      any(vapply(
        selection$artifacts,
        \(ref) artifact_ref_key(ref) %in% removed_keys,
        logical(1)
      ))
    },
    logical(1)
  )
  removed_selection_ids <- vapply(
    selections[removed_selection],
    \(selection) selection$id,
    character(1)
  )
  removed_selection_ids <- unname(removed_selection_ids)

  missing_streams <- setdiff(forget_streams, streams$names)
  if (length(missing_streams)) {
    artifact_abort("Every forgotten decision stream must exist.")
  }
  removed_stream <- vapply(
    seq_along(streams$names),
    function(index) {
      records <- streams$records[[index]]
      if (!is.list(records)) {
        artifact_abort(
          "Artifact recovery decision records have an invalid shape."
        )
      }
      historical <- vapply(
        records,
        function(record) {
          if (!is.list(record) || is.null(record$selection)) {
            artifact_abort("Artifact recovery decision records are invalid.")
          }
          artifact_check_digest(record$selection) %in% removed_selection_ids
        },
        logical(1)
      )
      streams$names[[index]] %in% forget_streams || any(historical)
    },
    logical(1)
  )
  removed_stream_names <- unname(streams$names[removed_stream])

  retained_artifacts <- artifacts[
    !vapply(
      artifacts,
      \(item) artifact_ref_key(item$ref) %in% removed_keys,
      logical(1)
    )
  ]
  retained_payloads <- unique(vapply(
    retained_artifacts,
    \(item) item$metadata$payload,
    character(1)
  ))
  retained_selection_ids <- setdiff(selection_ids, removed_selection_ids)
  target_objects <- source$objects[vapply(
    source$objects,
    function(object) {
      if (identical(object$kind, "revisions")) {
        return(!object$key %in% removed_artifact_keys)
      }
      if (identical(object$kind, "content")) {
        return(object$key %in% retained_payloads)
      }
      if (identical(object$kind, "selections")) {
        return(object$key %in% retained_selection_ids)
      }
      if (identical(object$kind, "decisions")) {
        stream_index <- which(startsWith(object$key, stream_prefixes))
        if (length(stream_index) != 1L) {
          artifact_abort(
            "Artifact recovery decision stream mapping is ambiguous."
          )
        }
        return(!removed_stream[[stream_index]])
      }
      artifact_abort("Artifact recovery contains an unsupported object kind.")
    },
    logical(1)
  )]
  target <- artifact_recovery_manifest(target_objects)

  list(
    format = "graft-artifact-replacement/1",
    source = source,
    target = target,
    forget = forget,
    forget_streams = forget_streams,
    removed = list(
      artifacts = removed_artifacts,
      selections = removed_selection_ids,
      streams = removed_stream_names
    ),
    limits = limits
  )
}

artifact_replacement_object_limit <- function(
  store,
  kind,
  max_metadata_bytes
) {
  if (identical(kind, "content")) {
    return(store@max_bytes)
  }
  if (
    identical(kind, "selections") ||
      identical(kind, "decisions")
  ) {
    return(max_metadata_bytes)
  }
  store@max_revision_bytes
}

artifact_replacement_check_manifest <- function(manifest) {
  if (
    !is.list(manifest) ||
      !identical(names(manifest), c("format", "id", "objects")) ||
      !identical(manifest$format, "graft-artifact-manifest/1")
  ) {
    artifact_abort("Unsupported artifact recovery manifest.")
  }
  canonical <- artifact_recovery_manifest(manifest$objects)
  if (!identical(manifest, canonical)) {
    artifact_abort("Artifact recovery manifest is not canonical.")
  }
  manifest
}

artifact_replacement_check_plan <- function(plan) {
  if (
    !is.list(plan) ||
      !identical(
        names(plan),
        c(
          "format",
          "source",
          "target",
          "forget",
          "forget_streams",
          "removed",
          "limits"
        )
      ) ||
      !identical(plan$format, "graft-artifact-replacement/1")
  ) {
    artifact_abort("Unsupported artifact replacement plan.")
  }
  limits <- plan$limits
  if (
    !is.list(limits) ||
      !identical(
        names(limits),
        c("max_objects", "max_total_bytes", "max_metadata_bytes")
      )
  ) {
    artifact_abort("Artifact replacement plan has invalid limits.")
  }
  limits <- artifact_replacement_limits(
    limits$max_objects,
    limits$max_total_bytes,
    limits$max_metadata_bytes
  )
  forget <- artifact_refs(plan$forget, limits$max_objects)
  if (!identical(forget, plan$forget)) {
    artifact_abort("Artifact replacement plan has noncanonical Forget roots.")
  }
  forget_streams <- artifact_replacement_stream_names(plan$forget_streams)
  if (!identical(forget_streams, plan$forget_streams)) {
    artifact_abort("Artifact replacement plan has noncanonical Forget streams.")
  }
  if (!length(forget) && !length(forget_streams)) {
    artifact_abort("Artifact replacement plan has no Forget roots or streams.")
  }
  removed <- plan$removed
  if (
    !is.list(removed) ||
      !identical(names(removed), c("artifacts", "selections", "streams"))
  ) {
    artifact_abort("Artifact replacement plan has invalid removals.")
  }
  removed_artifacts <- artifact_refs(removed$artifacts, limits$max_objects)
  if (!identical(removed_artifacts, removed$artifacts)) {
    artifact_abort(
      "Artifact replacement plan has noncanonical removed artifacts."
    )
  }
  removed_selections <- artifact_replacement_digest_vector(
    removed$selections,
    "removed selections"
  )
  removed_streams <- artifact_replacement_text_vector(
    removed$streams,
    "removed streams"
  )
  checked <- list(
    format = plan$format,
    source = artifact_replacement_check_manifest(plan$source),
    target = artifact_replacement_check_manifest(plan$target),
    forget = forget,
    forget_streams = forget_streams,
    removed = list(
      artifacts = removed_artifacts,
      selections = removed_selections,
      streams = removed_streams
    ),
    limits = limits
  )
  if (!identical(checked, plan)) {
    artifact_abort("Artifact replacement plan is not canonical.")
  }
  checked
}

artifact_replacement_digest_vector <- function(x, arg) {
  if (!is.character(x)) {
    artifact_abort(paste0("`", arg, "` must be a character vector."))
  }
  x <- unname(vapply(x, artifact_check_digest, character(1)))
  if (anyDuplicated(x)) {
    artifact_abort(paste0("`", arg, "` must contain distinct digests."))
  }
  x
}

artifact_replacement_text_vector <- function(x, arg) {
  if (!is.character(x)) {
    artifact_abort(paste0("`", arg, "` must be a character vector."))
  }
  x <- unname(vapply(x, artifact_check_text, character(1), arg = arg))
  if (anyDuplicated(x)) {
    artifact_abort(paste0("`", arg, "` must contain distinct strings."))
  }
  x
}
