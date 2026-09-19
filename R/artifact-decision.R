#' Record host decisions about exact artifact selections
#'
#' Retain acceptance and withdrawal decisions in a bounded, append-only journal.
#' Applications make the decisions and enforce access policy; Graft records
#' them and checks the mechanical conditions for current consultation.
#'
#' @param store A handle returned by [graft_artifact_store()] or
#'   [graft_artifact_store_postgres()].
#' @param stream Host-chosen identity for one independently reviewed subject.
#' @param key Host-chosen idempotency key, unique within the stream. A new review
#'   requires a new key, even when the selection is unchanged.
#' @param expected Exact predecessor decision digest, or explicit `NULL` for an
#'   empty stream. It is never inferred from current state.
#' @param selection Exact digest returned by [graft_artifact_select()].
#' @param action Explicit host decision: `"accept"` or `"withdraw"`.
#' @param actor Host-supplied actor identity. This is a claim, not authentication.
#' @param reason Host-supplied review or withdrawal reason.
#' @param purpose One explicit consultation purpose. Withdrawal must retain the
#'   purpose of the acceptance it withdraws.
#' @param max_decisions Maximum number of committed records in the stream.
#' @param max_metadata_bytes Maximum aggregate encoded journal bytes to read or
#'   publish. Staging files are not committed records and are excluded.
#' @param max_artifacts Maximum number of distinct artifacts in the selection.
#' @param max_selection_bytes Maximum encoded selection metadata bytes.
#' @param decision Exact decision digest, or `NULL` to inspect the current head.
#' @param eligible Explicit current host consultation decision, a single logical
#'   value. `graft_artifact_reuse()` requires `TRUE`; it does not derive policy.
#'
#' @details
#' Stream, key, actor, reason and purpose are nonempty, unpadded strings of at
#' most 1024 UTF-8 bytes without control characters. R attributes are discarded.
#' Each acceptance verifies the complete exact selection before publication.
#' A withdrawal must name the current acceptance's selection and purpose. It
#' remains possible when payloads are missing or corrupt.
#'
#' Committed keys bind all normalized request fields, including `expected`.
#' Repeating an identical committed request returns its original historical
#' record, even after correction or withdrawal. It never advances the head or
#' restores eligibility. Changed retries fail. An uncommitted interrupted request
#' has no recorded decision; retries must still satisfy the predecessor guard.
#'
#' Inspection verifies the journal and returns decision metadata, without
#' resolving payloads or granting consultation. Current reuse requires explicit
#' host eligibility, the current accepted decision, an exact purpose match and
#' successful verification of every selected payload. It returns the decision
#' and verified selection; callers resolve individual bytes with
#' [graft_artifact_read()]. This is a point-in-time check, not a lasting permit.
#' Applications must enforce access on every path, including low-level artifact
#' reads and historical inspection.
#'
#' A complete immutable numbered record is the commit point. Reopening derives
#' the head from contiguous, digest-verified records. Interrupted staging is
#' ignored and never promoted automatically; a lost response after publication
#' is recoverable by an identical retry. History scanning is bounded by count
#' and total encoded bytes, and the same or larger limits are needed on reopen.
#' Local stores support trusted files and one writer. Predecessor checks reject
#' stale sequential decisions; they do not provide concurrent compare-and-swap,
#' authentication, power-loss durability, backup recovery or permanent erasure.
#'
#' @returns
#' Recording and inspection return a list with `id`, `sequence`, `stream`, `key`,
#' `previous`, `action`, `selection`, `actor`, `reason` and `purpose`.
#' Inspection of an empty stream with `decision = NULL` returns `NULL`.
#' Reuse returns `decision` and `selection`, the latter having the shape returned
#' by [graft_artifact_read_selection()]. No return value asserts factual truth.
#'
#' @examples
#' path <- tempfile("decisions-")
#' store <- graft_artifact_store(path, create = TRUE)
#' ref <- graft_artifact_save(store, "report", charToRaw("Evidence"), "text/plain")
#' selection <- graft_artifact_select(store, list(ref))
#' accepted <- graft_artifact_decide(
#'   store, "research:topic", "review-1", expected = NULL,
#'   selection = selection, action = "accept", actor = "reviewer",
#'   reason = "Evidence reviewed", purpose = "research"
#' )
#' graft_artifact_reuse(
#'   store, "research:topic", accepted$id, "research", eligible = TRUE
#' )$selection$artifacts
#' graft_artifact_decide(
#'   store, "research:topic", "withdraw-1", expected = accepted$id,
#'   selection = selection, action = "withdraw", actor = "reviewer",
#'   reason = "Evidence needs correction", purpose = "research"
#' )
#' graft_artifact_read_decision(store, "research:topic", accepted$id)
#' unlink(path, recursive = TRUE)
#' @export
graft_artifact_decide <- function(
  store,
  stream,
  key,
  expected,
  selection,
  action,
  actor,
  reason,
  purpose,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2,
  max_artifacts = 1000L,
  max_selection_bytes = 1024^2
) {
  artifact_check_store(store)
  request <- artifact_decision_request(
    stream,
    key,
    expected,
    selection,
    action,
    actor,
    reason,
    purpose
  )
  artifact_check_limit(max_artifacts, "max_artifacts")
  artifact_check_limit(max_selection_bytes, "max_selection_bytes")
  records <- artifact_decisions(
    store,
    request$stream,
    max_decisions,
    max_metadata_bytes
  )
  matched <- which(vapply(
    records,
    \(x) identical(x$key, request$key),
    logical(1)
  ))
  if (length(matched)) {
    previous <- records[[matched]]
    if (!identical(previous[names(request)], request)) {
      artifact_abort(
        "Decision key was already committed for a different request."
      )
    }
    return(previous)
  }
  head <- artifact_decision_head(records)
  artifact_decision_transition(request, head)
  if (length(records) >= max_decisions) {
    artifact_abort("Decision journal exceeds the record-count bound.")
  }
  if (request$action == "accept") {
    graft_artifact_read_selection(
      store,
      request$selection,
      max_artifacts,
      max_selection_bytes
    )
  }
  value <- list(format = 1L, sequence = length(records) + 1L, request = request)
  bytes <- artifact_encode(value)
  retained <- sum(vapply(records, artifact_decision_size, numeric(1)))
  if (retained + length(bytes) > max_metadata_bytes) {
    artifact_abort(
      "Decision journal exceeds the aggregate metadata byte bound."
    )
  }
  current <- artifact_decisions(
    store,
    request$stream,
    max_decisions,
    max_metadata_bytes
  )
  if (!identical(artifact_decision_head(current), head)) {
    artifact_abort("Decision head changed before publication; review it again.")
  }
  id <- artifact_sha(bytes)
  key <- paste0(
    artifact_sha(charToRaw(request$stream)),
    "/",
    sprintf("%010d-%s.json", value$sequence, id)
  )
  artifact_storage_put(store, "decisions", key, bytes, max_metadata_bytes)
  graft_artifact_read_decision(
    store,
    request$stream,
    id,
    max_decisions,
    max_metadata_bytes
  )
}

#' @rdname graft_artifact_decide
#' @export
graft_artifact_read_decision <- function(
  store,
  stream,
  decision = NULL,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2
) {
  artifact_check_store(store)
  stream <- artifact_check_text(stream, "stream")
  if (!is.null(decision)) {
    decision <- artifact_check_digest(decision)
  }
  records <- artifact_decisions(
    store,
    stream,
    max_decisions,
    max_metadata_bytes
  )
  if (is.null(decision)) {
    return(artifact_decision_head(records))
  }
  matched <- which(vapply(records, \(x) identical(x$id, decision), logical(1)))
  if (!length(matched)) {
    artifact_abort("No committed decision has that identity in this stream.")
  }
  records[[matched]]
}

#' @rdname graft_artifact_decide
#' @export
graft_artifact_reuse <- function(
  store,
  stream,
  decision,
  purpose,
  eligible,
  max_decisions = 1000L,
  max_metadata_bytes = 1024^2,
  max_artifacts = 1000L,
  max_selection_bytes = 1024^2
) {
  stream <- artifact_check_text(stream, "stream")
  decision <- artifact_check_digest(decision)
  purpose <- artifact_check_text(purpose, "purpose")
  if (!rlang::is_bool(eligible) || !eligible) {
    artifact_abort(
      "Current consultation requires an explicit TRUE host eligibility decision."
    )
  }
  artifact_check_limit(max_artifacts, "max_artifacts")
  artifact_check_limit(max_selection_bytes, "max_selection_bytes")
  head <- graft_artifact_read_decision(
    store,
    stream,
    max_decisions = max_decisions,
    max_metadata_bytes = max_metadata_bytes
  )
  if (
    is.null(head) ||
      !identical(head$id, decision) ||
      head$action != "accept" ||
      !identical(head$purpose, purpose)
  ) {
    artifact_abort("Decision is not the current acceptance for this purpose.")
  }
  selection <- graft_artifact_read_selection(
    store,
    head$selection,
    max_artifacts,
    max_selection_bytes
  )
  current <- graft_artifact_read_decision(
    store,
    stream,
    max_decisions = max_decisions,
    max_metadata_bytes = max_metadata_bytes
  )
  if (!identical(current, head)) {
    artifact_abort(
      "Decision head changed during consultation; review it again."
    )
  }
  list(decision = head, selection = selection)
}

artifact_decision_request <- function(
  stream,
  key,
  expected,
  selection,
  action,
  actor,
  reason,
  purpose
) {
  stream <- artifact_check_text(stream, "stream")
  key <- artifact_check_text(key, "key")
  if (!is.null(expected)) {
    expected <- artifact_check_digest(expected)
  }
  selection <- artifact_check_digest(selection)
  action <- artifact_check_text(action, "action")
  if (!action %in% c("accept", "withdraw")) {
    artifact_abort("`action` must be either \"accept\" or \"withdraw\".")
  }
  list(
    stream = stream,
    key = key,
    previous = expected,
    action = action,
    selection = selection,
    actor = artifact_check_text(actor, "actor"),
    reason = artifact_check_text(reason, "reason"),
    purpose = artifact_check_text(purpose, "purpose")
  )
}

artifact_decision_transition <- function(request, head) {
  if (!identical(request$previous, if (is.null(head)) NULL else head$id)) {
    artifact_abort("Decision predecessor differs from the current head.")
  }
  if (
    request$action == "withdraw" &&
      (is.null(head) ||
        head$action != "accept" ||
        !identical(request$selection, head$selection) ||
        !identical(request$purpose, head$purpose))
  ) {
    artifact_abort(
      "Withdrawal must name the current acceptance's selection and purpose."
    )
  }
}

artifact_decision_path <- function(store, stream) {
  artifact_path(store, "decisions", artifact_sha(charToRaw(stream)))
}

artifact_decision_head <- function(records) {
  if (length(records)) records[[length(records)]] else NULL
}

artifact_decision_size <- function(record) {
  length(artifact_encode(list(
    format = 1L,
    sequence = record$sequence,
    request = record[setdiff(names(record), c("id", "sequence"))]
  )))
}

artifact_decisions <- function(
  store,
  stream,
  max_decisions,
  max_metadata_bytes
) {
  artifact_check_limit(max_decisions, "max_decisions")
  artifact_check_limit(max_metadata_bytes, "max_metadata_bytes")
  entries <- artifact_decision_entries(store, stream, max_decisions)
  files <- entries$name
  if (
    length(files) > max_decisions ||
      !all(grepl("^[0-9]{10}-[0-9a-f]{64}\\.json$", files))
  ) {
    artifact_abort(
      "Decision journal has invalid entries or exceeds its record bound."
    )
  }
  sizes <- entries$size
  if (anyNA(sizes) || sum(sizes) > max_metadata_bytes) {
    artifact_abort(
      "Decision journal exceeds its metadata bound or has invalid entries."
    )
  }
  records <- list()
  keys <- character()
  for (i in seq_along(files)) {
    key <- paste0(artifact_sha(charToRaw(stream)), "/", files[[i]])
    bytes <- artifact_storage_read(store, "decisions", key, max_metadata_bytes)
    id <- substr(files[[i]], 12L, 75L)
    if (
      !startsWith(files[[i]], sprintf("%010d-", i)) ||
        !identical(artifact_sha(bytes), id)
    ) {
      artifact_abort(
        "Decision journal has a sequence gap, fork or digest mismatch."
      )
    }
    value <- artifact_decode(bytes)
    if (
      !is.list(value) ||
        !identical(names(value), c("format", "sequence", "request")) ||
        !identical(value$format, 1L) ||
        !identical(value$sequence, i) ||
        !is.list(value$request) ||
        !identical(
          names(value$request),
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
      artifact_abort("Unsupported decision record metadata.")
    }
    args <- value$request
    names(args)[names(args) == "previous"] <- "expected"
    request <- do.call(artifact_decision_request, args)
    if (
      !identical(request$stream, stream) ||
        request$key %in% keys ||
        !identical(request, value$request) ||
        !identical(artifact_encode(value), bytes)
    ) {
      artifact_abort(
        "Decision record has inconsistent identity, key or encoding."
      )
    }
    artifact_decision_transition(request, artifact_decision_head(records))
    records[[i]] <- c(list(id = id, sequence = i), request)
    keys <- c(keys, request$key)
  }
  records
}
