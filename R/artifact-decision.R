artifact_decide <- function(
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
  artifact_with_stream_lock(store, request$stream, function() {
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
      artifact_read_selection(
        store,
        request$selection,
        max_artifacts,
        max_selection_bytes
      )
    }
    value <- list(
      format = 1L,
      sequence = length(records) + 1L,
      request = request
    )
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
      artifact_abort(
        "Decision head changed before publication; review it again."
      )
    }
    id <- artifact_sha(bytes)
    key <- paste0(
      artifact_sha(charToRaw(request$stream)),
      "/",
      sprintf("%010d-%s.json", value$sequence, id)
    )
    artifact_storage_put(store, "decisions", key, bytes, max_metadata_bytes)
    artifact_read_decision(
      store,
      request$stream,
      id,
      max_decisions,
      max_metadata_bytes
    )
  })
}

artifact_read_decision <- function(
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

artifact_reuse <- function(
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
  head <- artifact_read_decision(
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
  selection <- artifact_read_selection(
    store,
    head$selection,
    max_artifacts,
    max_selection_bytes
  )
  current <- artifact_read_decision(
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
  entries <- artifact_decision_entries(
    store,
    artifact_sha(charToRaw(stream)),
    max_decisions
  )
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

artifact_decision_stream_name <- function(store, hash, max_metadata_bytes) {
  entries <- artifact_decision_entries(store, hash, 1L)
  if (!nrow(entries)) {
    return(NULL)
  }
  first <- entries$name[[1L]]
  if (!grepl("^0000000001-[0-9a-f]{64}\\.json$", first)) {
    artifact_abort("Decision journal has a sequence gap or invalid entries.")
  }
  bytes <- artifact_storage_read(
    store,
    "decisions",
    paste0(hash, "/", first),
    max_metadata_bytes
  )
  value <- artifact_decode(bytes)
  stream <- if (is.list(value) && is.list(value$request)) {
    value$request$stream
  }
  stream <- artifact_check_text(stream, "stream")
  if (!identical(artifact_sha(charToRaw(stream)), hash)) {
    artifact_abort("Decision journal is filed under a different stream.")
  }
  stream
}
