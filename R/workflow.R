# Public workflow API --------------------------------------------------------

graft_workflow_abort <- function(.subclass, message) {
  graft_abort(.subclass, message)
}

artifact_expected_id <- function(expected) {
  if (is.null(expected)) {
    return(NULL)
  }
  if (S7::S7_inherits(expected, Decision)) {
    return(tryCatch(
      artifact_check_digest(expected@id),
      graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
    ))
  }
  if (is.character(expected)) {
    return(tryCatch(
      artifact_check_digest(expected),
      graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
    ))
  }
  graft_value_abort("`expected` must be NULL, a Decision, or an exact digest.")
}

artifact_retry_head <- function(store, stream, expected_record, limits) {
  current <- artifact_read_decision(
    store,
    stream,
    max_decisions = limits$max_decisions,
    max_metadata_bytes = limits$max_metadata_bytes
  )
  if (is.null(current) || !identical(current, expected_record)) {
    graft_workflow_abort(
      "graft_stale_review_error",
      "The decision request refers to a historical event, not the current head."
    )
  }
  current
}

artifact_selection_id <- function(
  store,
  x,
  max_artifacts,
  max_metadata_bytes
) {
  if (S7::S7_inherits(x, ArtifactSelection)) {
    supplied <- artifact_selection_record(x)
    stored <- artifact_read_selection(
      store,
      supplied$id,
      max_artifacts,
      max_metadata_bytes
    )
    if (!identical(stored, supplied)) {
      graft_workflow_abort(
        "graft_selection_error",
        "The supplied ArtifactSelection does not match its retained selection."
      )
    }
    return(supplied$id)
  }
  refs <- tryCatch(
    artifact_refs_records(x),
    graft_value_error = function(e) {
      graft_workflow_abort(
        "graft_input_error",
        conditionMessage(e)
      )
    }
  )
  if (!length(refs)) {
    graft_workflow_abort(
      "graft_input_error",
      "`x` must contain at least one ArtifactRef or an ArtifactSelection."
    )
  }
  artifact_select(
    store,
    refs,
    max_artifacts,
    max_metadata_bytes
  )
}

artifact_materialize <- function(store, refs) {
  lapply(refs, function(ref) artifact_value(artifact_read(store, ref)))
}

#' Save text or raw bytes as an immutable artifact
#'
#' Scalar nonmissing character input is encoded as UTF-8 and defaults to
#' `text/plain`. Raw input is retained exactly and defaults to
#' `application/octet-stream`. Strings are always content; use
#' [graft_save_file()] for explicit file ingestion.
#'
#' @param store A store returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param x One scalar character value or a raw vector.
#' @param id Stable artifact identity.
#' @param media_type Media type, or `NULL` for the input-dependent default.
#' @param dependencies One [ArtifactRef] or a list of them.
#' @param max_artifacts Maximum dependency references to verify.
#' @returns An [ArtifactRef].
#' @export
graft_save <- function(
  store,
  x,
  id,
  media_type = NULL,
  dependencies = list(),
  max_artifacts = 1000L
) {
  if (is.raw(x)) {
    bytes <- x
    default_media_type <- "application/octet-stream"
  } else if (
    is.character(x) &&
      length(x) == 1L &&
      !is.na(x) &&
      validUTF8(enc2utf8(x))
  ) {
    bytes <- charToRaw(enc2utf8(x))
    default_media_type <- "text/plain"
  } else {
    graft_workflow_abort(
      "graft_input_error",
      "`x` must be one nonmissing UTF-8 string or a raw vector."
    )
  }
  if (is.null(media_type)) {
    media_type <- default_media_type
  }
  media_type <- tryCatch(
    artifact_check_text(media_type, "media_type"),
    graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
  )
  records <- tryCatch(
    artifact_refs_records(dependencies),
    graft_value_error = function(e) {
      graft_workflow_abort(
        "graft_input_error",
        conditionMessage(e)
      )
    }
  )
  ref <- artifact_save(
    store,
    id = id,
    bytes = bytes,
    media_type = media_type,
    dependencies = records,
    max_artifacts = max_artifacts
  )
  artifact_ref_value(ref)
}

#' Save a bounded regular file as an immutable artifact
#'
#' File ingestion is explicit. The path must identify a regular file no larger
#' than the store byte bound, and file bytes are never deserialized or executed.
#'
#' @param store A store returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param path Path to a regular file.
#' @param id Stable artifact identity; defaults to [basename()] of `path`.
#' @param media_type Media type recorded for the bytes.
#' @param dependencies One [ArtifactRef] or a list of them.
#' @param max_artifacts Maximum dependency references to verify.
#' @returns An [ArtifactRef].
#' @export
graft_save_file <- function(
  store,
  path,
  id = basename(path),
  media_type = "application/octet-stream",
  dependencies = list(),
  max_artifacts = 1000L
) {
  if (
    !is.character(path) ||
      length(path) != 1L ||
      is.na(path) ||
      !nzchar(path)
  ) {
    graft_workflow_abort(
      "graft_input_error",
      "`path` must be one nonempty filesystem path string."
    )
  }
  artifact_check_store(store)
  limit <- store@max_bytes
  artifact_check_limit(limit, "store@max_bytes")
  info <- fs::file_info(path, fail = FALSE, follow = FALSE)
  size <- as.numeric(info$size)
  if (
    !identical(as.character(info$type), "file") ||
      is.na(size) ||
      size > limit
  ) {
    graft_workflow_abort(
      "graft_input_error",
      "`path` must identify a readable regular file within the store byte bound."
    )
  }
  bytes <- tryCatch(
    readBin(path, "raw", n = size),
    error = function(e) {
      graft_workflow_abort(
        "graft_input_error",
        "The regular file could not be read."
      )
    }
  )
  if (length(bytes) != size) {
    graft_workflow_abort(
      "graft_input_error",
      "The regular file changed while it was being read."
    )
  }
  graft_save(
    store,
    bytes,
    id = id,
    media_type = media_type,
    dependencies = dependencies,
    max_artifacts = max_artifacts
  )
}

#' Read one exact immutable artifact
#'
#' @param store A store returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param ref An exact [ArtifactRef].
#' @returns A materialized [Artifact].
#' @export
graft_read <- function(store, ref) {
  record <- artifact_ref_record(ref)
  artifact_value(artifact_read(store, record))
}

#' Capture and verify an exact dependency selection
#'
#' @param store A store returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param roots One [ArtifactRef] or a list of them.
#' @param max_artifacts Maximum dependency references to verify.
#' @param max_metadata_bytes Maximum encoded selection metadata bytes.
#' @returns A verified [ArtifactSelection].
#' @export
graft_select <- function(
  store,
  roots,
  max_artifacts = 1000L,
  max_metadata_bytes = 1024^2
) {
  records <- tryCatch(
    artifact_refs_records(roots),
    graft_value_error = function(e) {
      graft_workflow_abort(
        "graft_input_error",
        conditionMessage(e)
      )
    }
  )
  if (!length(records)) {
    graft_workflow_abort(
      "graft_input_error",
      "`roots` must contain at least one ArtifactRef."
    )
  }
  id <- artifact_select(
    store,
    records,
    max_artifacts,
    max_metadata_bytes
  )
  artifact_selection_value(artifact_read_selection(
    store,
    id,
    max_artifacts,
    max_metadata_bytes
  ))
}

#' Read one exact retained dependency selection
#'
#' @param store A store returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param id Exact selection digest.
#' @param max_artifacts Maximum dependency references to verify.
#' @param max_metadata_bytes Maximum encoded selection metadata bytes.
#' @returns A verified [ArtifactSelection].
#' @export
graft_read_selection <- function(
  store,
  id,
  max_artifacts = 1000L,
  max_metadata_bytes = 1024^2
) {
  id <- tryCatch(
    artifact_check_digest(id),
    graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
  )
  artifact_selection_value(artifact_read_selection(
    store,
    id,
    max_artifacts,
    max_metadata_bytes
  ))
}

#' Record an acceptance of exact retained evidence
#'
#' @param store A store returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param x One [ArtifactRef], a list of them, or an [ArtifactSelection].
#' @param stream Host-chosen decision stream.
#' @param expected Required predecessor: `NULL`, a [Decision], or an exact
#'   external decision digest.
#' @param key Required stable host request key.
#' @param actor Host-supplied actor identity.
#' @param reason Host-supplied review reason.
#' @param purpose Host-supplied consultation purpose.
#' @param max_decisions Maximum decision records to inspect.
#' @param max_metadata_bytes Maximum aggregate decision metadata bytes.
#' @param max_artifacts Maximum artifacts in the selected closure.
#' @param max_selection_bytes Maximum encoded selection metadata bytes.
#' @returns A recorded [Decision]. The host transaction governs durability.
#' @export
graft_accept <- function(
  store,
  x,
  stream,
  expected,
  key,
  actor,
  reason,
  purpose,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2,
  max_artifacts = 1000L,
  max_selection_bytes = 1024^2
) {
  selection <- artifact_selection_id(
    store,
    x,
    max_artifacts,
    max_selection_bytes
  )
  expected <- artifact_expected_id(expected)
  record <- artifact_decide(
    store,
    stream = stream,
    key = key,
    expected = expected,
    selection = selection,
    action = "accept",
    actor = actor,
    reason = reason,
    purpose = purpose,
    max_decisions = max_decisions,
    max_metadata_bytes = max_metadata_bytes,
    max_artifacts = max_artifacts,
    max_selection_bytes = max_selection_bytes
  )
  current <- artifact_retry_head(
    store,
    stream,
    record,
    list(
      max_decisions = max_decisions,
      max_metadata_bytes = max_metadata_bytes
    )
  )
  artifact_decision_value(current)
}

#' Withdraw the current acceptance for a decision stream
#'
#' @param store A store returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param stream Host-chosen decision stream.
#' @param expected Required current predecessor: a [Decision] or exact digest.
#' @param key Required stable host request key.
#' @param actor Host-supplied actor identity.
#' @param reason Host-supplied withdrawal reason.
#' @param max_decisions Maximum decision records to inspect.
#' @param max_metadata_bytes Maximum aggregate decision metadata bytes.
#' @returns A recorded withdrawal [Decision]. The host transaction governs
#'   durability.
#' @export
graft_withdraw <- function(
  store,
  stream,
  expected,
  key,
  actor,
  reason,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2
) {
  expected_id <- artifact_expected_id(expected)
  if (is.null(expected_id)) {
    graft_value_abort(
      "`expected` must identify the exact accepted predecessor for withdrawal."
    )
  }
  predecessor <- artifact_read_decision(
    store,
    stream,
    expected_id,
    max_decisions,
    max_metadata_bytes
  )
  record <- artifact_decide(
    store,
    stream = stream,
    key = key,
    expected = expected_id,
    selection = predecessor$selection,
    action = "withdraw",
    actor = actor,
    reason = reason,
    purpose = predecessor$purpose,
    max_decisions = max_decisions,
    max_metadata_bytes = max_metadata_bytes
  )
  current <- artifact_retry_head(
    store,
    stream,
    record,
    list(
      max_decisions = max_decisions,
      max_metadata_bytes = max_metadata_bytes
    )
  )
  artifact_decision_value(current)
}

#' Recall the current accepted evidence for a stream
#'
#' @param store A store returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param stream Host-chosen decision stream.
#' @param purpose Required consultation purpose.
#' @param eligible Fresh explicit host eligibility decision.
#' @param max_decisions Maximum decision records to inspect.
#' @param max_metadata_bytes Maximum aggregate decision metadata bytes.
#' @param max_artifacts Maximum artifacts in the selected closure.
#' @param max_selection_bytes Maximum encoded selection metadata bytes.
#' @returns A point-in-time [Recall].
#' @export
graft_recall <- function(
  store,
  stream,
  purpose,
  eligible,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2,
  max_artifacts = 1000L,
  max_selection_bytes = 1024^2
) {
  stream <- tryCatch(
    artifact_check_text(stream, "stream"),
    graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
  )
  purpose <- tryCatch(
    artifact_check_text(purpose, "purpose"),
    graft_artifact_error = function(e) graft_value_abort(conditionMessage(e))
  )
  if (!rlang::is_bool(eligible) || !isTRUE(eligible)) {
    graft_workflow_abort(
      "graft_ineligible_error",
      "Current consultation requires an explicit TRUE host eligibility decision."
    )
  }
  head <- artifact_read_decision(
    store,
    stream,
    max_decisions = max_decisions,
    max_metadata_bytes = max_metadata_bytes
  )
  if (is.null(head)) {
    return(Recall(
      status = "missing",
      decision = NULL,
      selection = NULL,
      roots = list(),
      artifacts = list()
    ))
  }
  if (!identical(head$purpose, purpose)) {
    graft_workflow_abort(
      "graft_purpose_error",
      "The current decision was recorded for a different purpose."
    )
  }
  decision <- artifact_decision_value(head)
  if (identical(head$action, "withdraw")) {
    return(Recall(
      status = "withdrawn",
      decision = decision,
      selection = NULL,
      roots = list(),
      artifacts = list()
    ))
  }
  if (!identical(head$action, "accept")) {
    graft_workflow_abort(
      "graft_artifact_error",
      "The current decision has an unsupported action."
    )
  }
  selected_record <- artifact_read_selection(
    store,
    head$selection,
    max_artifacts,
    max_selection_bytes
  )
  selection <- artifact_selection_value(selected_record)
  all_artifacts <- artifact_materialize(store, selected_record$artifacts)
  roots <- vector("list", length(selected_record$roots))
  keys <- vapply(
    selected_record$artifacts,
    artifact_ref_key,
    character(1)
  )
  for (i in seq_along(selected_record$roots)) {
    root_key <- artifact_ref_key(selected_record$roots[[i]])
    roots[[i]] <- all_artifacts[[match(root_key, keys)]]
  }
  current <- artifact_read_decision(
    store,
    stream,
    max_decisions = max_decisions,
    max_metadata_bytes = max_metadata_bytes
  )
  if (!identical(current, head)) {
    graft_workflow_abort(
      "graft_stale_review_error",
      "The decision head changed while the accepted evidence was read."
    )
  }
  Recall(
    status = "accepted",
    decision = decision,
    selection = selection,
    roots = roots,
    artifacts = all_artifacts
  )
}

#' Read the chronological decision journal for one stream
#'
#' @param store A store returned by [graft_store()] or
#'   [graft_store_postgres()].
#' @param stream Host-chosen decision stream.
#' @param max_decisions Maximum decision records to inspect.
#' @param max_metadata_bytes Maximum aggregate decision metadata bytes.
#' @returns A chronological list of [Decision] values, oldest first.
#' @export
graft_history <- function(
  store,
  stream,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2
) {
  artifact_check_store(store)
  stream <- artifact_check_text(stream, "stream")
  records <- artifact_decisions(
    store,
    stream,
    max_decisions,
    max_metadata_bytes
  )
  lapply(records, artifact_decision_value)
}
