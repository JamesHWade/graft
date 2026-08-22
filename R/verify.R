#' Verify recorded Graft evidence for assistant answers
#'
#' `graft_verify()` inspects the turns already recorded by an [ellmer::Chat]
#' and classifies each completed, text-bearing assistant answer. Verification
#' is deterministic and offline: it does not call a model, reopen a Graft
#' store, or authenticate receipt identifiers.
#'
#' In this release, successful governed-measure-only evidence is `"verified"`.
#' Generic Graft reads remain `"untrusted"` with an `"unmatched_citation"`
#' reason until citation matching is applied. Unknown, errored, malformed, and
#' unsupported evidence paths fail closed as `"untrusted"`.
#'
#' @param chat An [ellmer::Chat] whose recorded turns should be verified.
#'
#' @return A `graft_verification` data frame with one row per completed answer.
#'   Scalar columns contain `answer_index`, `turn_index`, `answer_text`, and
#'   `label`. List columns contain `reason_codes`, `receipts`, `citations`,
#'   `tool_calls`, and `diagnostics`. A chat without completed answers returns
#'   the same columns with zero rows.
#' @export
graft_verify <- function(chat) {
  if (!inherits(chat, "Chat")) {
    abort_validation_error(
      "`chat` must be an ellmer Chat object.",
      argument = "chat"
    )
  }
  turns <- tryCatch(
    chat$get_turns(),
    error = function(error) {
      abort_validation_error(
        "`chat$get_turns()` failed while reading recorded turns.",
        argument = "chat",
        parent = error
      )
    }
  )
  if (!is.list(turns)) {
    abort_validation_error(
      "`chat$get_turns()` must return a list of turns.",
      argument = "chat"
    )
  }
  answer_turns <- which(vapply(
    turns,
    is_graft_verification_answer,
    logical(1)
  ))
  if (length(answer_turns) == 0L) {
    return(new_graft_verification())
  }
  window_starts <- c(1L, utils::head(answer_turns, -1L) + 1L)
  windows <- Map(
    \(start, end) graft_verification_window(turns[start:end]),
    window_starts,
    answer_turns
  )
  classifications <- lapply(windows, graft_verification_classify)
  result <- data.frame(
    answer_index = seq_along(answer_turns),
    turn_index = as.integer(answer_turns),
    answer_text = vapply(
      turns[answer_turns],
      \(turn) turn@text,
      character(1)
    ),
    label = vapply(classifications, `[[`, character(1), "label")
  )
  result$reason_codes <- lapply(classifications, `[[`, "reason_codes")
  result$receipts <- lapply(windows, `[[`, "receipts")
  result$citations <- rep(list(list()), nrow(result))
  result$tool_calls <- lapply(windows, `[[`, "tool_calls")
  result$diagnostics <- lapply(classifications, `[[`, "diagnostics")
  new_graft_verification(result)
}

is_graft_verification_answer <- function(turn) {
  inherits(turn, "ellmer::AssistantTurn") &&
    !inherits(turn, "ellmer::AssistantPartialTurn") &&
    is_nonempty_string(turn@text) &&
    nzchar(trimws(turn@text))
}

graft_verification_window <- function(turns) {
  requests <- list()
  results <- list()
  unsupported <- FALSE
  for (turn in turns) {
    contents <- tryCatch(turn@contents, error = \(error) NULL)
    if (!is.list(contents)) {
      unsupported <- TRUE
      next
    }
    for (content in contents) {
      if (inherits(content, "ellmer::ContentText")) {
        next
      } else if (inherits(content, "ellmer::ContentToolRequest")) {
        if (!inherits(turn, "ellmer::AssistantTurn")) {
          unsupported <- TRUE
        }
        requests[[length(requests) + 1L]] <- content
      } else if (inherits(content, "ellmer::ContentToolResult")) {
        if (!inherits(turn, "ellmer::UserTurn")) {
          unsupported <- TRUE
        }
        results[[length(results) + 1L]] <- content
      } else {
        unsupported <- TRUE
      }
    }
  }
  calls <- lapply(
    requests,
    \(request) list(request = request, result = NULL)
  )
  ids <- vapply(
    requests,
    \(request) {
      if (is_nonempty_string(request@id)) request@id else NA_character_
    },
    character(1)
  )
  request_names <- vapply(
    requests,
    \(request) {
      if (is_nonempty_string(request@name)) request@name else NA_character_
    },
    character(1)
  )
  if (
    anyNA(ids) ||
      anyNA(request_names) ||
      anyDuplicated(ids[!is.na(ids)])
  ) {
    unsupported <- TRUE
  }
  seen_result_ids <- character()
  for (result in results) {
    linked <- result@request
    linked_valid <- !is.null(linked) &&
      inherits(linked, "ellmer::ContentToolRequest") &&
      is_nonempty_string(linked@id) &&
      is_nonempty_string(linked@name)
    if (!linked_valid) {
      unsupported <- TRUE
      calls[[length(calls) + 1L]] <- list(request = NULL, result = result)
      next
    }
    if (linked@id %in% seen_result_ids) {
      unsupported <- TRUE
    }
    seen_result_ids <- c(seen_result_ids, linked@id)
    matching <- which(ids == linked@id & request_names == linked@name)
    if (length(matching) == 1L && is.null(calls[[matching]]$result)) {
      calls[[matching]]$result <- result
      next
    }
    if (
      length(matching) > 0L ||
        any(ids == linked@id, na.rm = TRUE)
    ) {
      unsupported <- TRUE
    }
    calls[[length(calls) + 1L]] <- list(request = linked, result = result)
  }
  if (
    length(calls) > 0L &&
      any(vapply(calls, \(call) is.null(call$result), logical(1)))
  ) {
    unsupported <- TRUE
  }
  list(
    tool_calls = calls,
    receipts = lapply(calls, function(call) {
      value <- if (is.null(call$result)) NULL else call$result@value
      if (is.list(value)) value[["receipt", exact = TRUE]] else NULL
    }),
    unsupported = unsupported
  )
}

graft_verification_classify <- function(window) {
  if (length(window$tool_calls) == 0L && !window$unsupported) {
    return(list(
      label = "untrusted",
      reason_codes = "no_evidence",
      diagnostics = character()
    ))
  }
  reason_order <- c(
    "governed_measure_only",
    "matched_citations",
    "no_evidence",
    "non_graft_tool",
    "tool_error",
    "invalid_receipt",
    "unmatched_citation",
    "unsupported_trace"
  )
  reasons <- stats::setNames(rep(FALSE, length(reason_order)), reason_order)
  reasons[["unsupported_trace"]] <- window$unsupported
  measure_count <- 0L
  truncated <- FALSE
  boundary_keys <- character()
  supported <- c(
    "graft_find",
    "graft_get",
    "graft_query",
    "graft_history",
    "graft_measure"
  )
  for (call in window$tool_calls) {
    request <- call$request
    result <- call$result
    if (!is.null(result) && !is.null(result@error)) {
      reasons[["tool_error"]] <- TRUE
    }
    if (is.null(request)) {
      next
    }
    name <- request@name
    if (!name %in% supported) {
      reasons[["non_graft_tool"]] <- TRUE
      next
    }
    if (is.null(result)) {
      next
    }
    if (!is.null(result@error)) {
      next
    }
    if (!graft_verification_receipt_valid(name, result@value)) {
      reasons[["invalid_receipt"]] <- TRUE
      next
    }
    truncated <- truncated || result@value$truncated
    receipt <- result@value$receipt
    boundary_keys <- c(
      boundary_keys,
      canonical_json(list(
        store_id = receipt$store$id,
        batch_id = receipt$boundary$batch_id,
        commit_order = receipt$boundary$commit_order
      ))
    )
    if (identical(name, "graft_measure")) {
      measure_count <- measure_count + 1L
    } else {
      reasons[["unmatched_citation"]] <- TRUE
    }
  }
  observed <- names(reasons)[reasons]
  diagnostics <- character()
  if (truncated) {
    diagnostics <- c(diagnostics, "truncated_result")
  }
  if (length(unique(boundary_keys)) > 1L) {
    diagnostics <- c(diagnostics, "mixed_boundaries")
  }
  if (length(observed) == 0L && measure_count > 0L) {
    return(list(
      label = "verified",
      reason_codes = "governed_measure_only",
      diagnostics = diagnostics
    ))
  }
  list(
    label = "untrusted",
    reason_codes = observed,
    diagnostics = diagnostics
  )
}

graft_verification_receipt_valid <- function(tool_name, value) {
  if (
    !is.list(value) ||
      is.object(value) ||
      !identical(
        names(value),
        c("result", "truncated", "limit", "receipt")
      ) ||
      !is_scalar_flag(value$truncated)
  ) {
    return(FALSE)
  }
  receipt <- value$receipt
  expected <- c("store", "boundary", "schema")
  if (identical(tool_name, "graft_measure")) {
    expected <- c(expected, "definition")
  }
  if (
    !is.list(receipt) ||
      is.object(receipt) ||
      !identical(names(receipt), expected) ||
      !graft_verification_store_valid(receipt$store) ||
      !graft_verification_schema_valid(receipt$schema) ||
      !graft_verification_boundary_valid(receipt$boundary, tool_name)
  ) {
    return(FALSE)
  }
  if (!identical(tool_name, "graft_measure")) {
    return(TRUE)
  }
  definition <- receipt$definition
  is.list(definition) &&
    !is.object(definition) &&
    identical(names(definition), c("id", "revision_id")) &&
    is_nonempty_string(definition$id) &&
    is_nonempty_string(definition$revision_id)
}

graft_verification_store_valid <- function(store) {
  is.list(store) &&
    !is.object(store) &&
    identical(names(store), "id") &&
    is_nonempty_string(store$id)
}

graft_verification_schema_valid <- function(schema) {
  is.list(schema) &&
    !is.object(schema) &&
    identical(names(schema), c("structural_digest", "build_digest")) &&
    is_graft_digest(schema$structural_digest) &&
    is_graft_digest(schema$build_digest)
}

graft_verification_boundary_valid <- function(boundary, tool_name) {
  if (!is.list(boundary) || is.object(boundary)) {
    return(FALSE)
  }
  kind <- boundary$kind
  expected <- if (identical(kind, "snapshot")) {
    c("kind", "batch_id", "commit_order", "snapshot_id")
  } else {
    c("kind", "batch_id", "commit_order")
  }
  if (
    !identical(names(boundary), expected) ||
      !is_nonempty_string(kind) ||
      !kind %in% c("live", "snapshot", "history") ||
      !graft_verification_commit_order_valid(boundary$commit_order)
  ) {
    return(FALSE)
  }
  empty <- identical(as.numeric(boundary$commit_order), 0)
  if (
    (empty && !is.null(boundary$batch_id)) ||
      (!empty && !is_nonempty_string(boundary$batch_id))
  ) {
    return(FALSE)
  }
  if (
    identical(kind, "snapshot") &&
      !is_graft_digest(boundary$snapshot_id)
  ) {
    return(FALSE)
  }
  if (identical(kind, "history")) {
    return(identical(tool_name, "graft_history"))
  }
  TRUE
}

graft_verification_commit_order_valid <- function(value) {
  is.numeric(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    is.finite(value) &&
    value >= 0 &&
    value == floor(value) &&
    value < 2^53
}

new_graft_verification <- function(rows = NULL) {
  if (is.null(rows)) {
    result <- data.frame(
      answer_index = integer(),
      turn_index = integer(),
      answer_text = character(),
      label = character()
    )
    result$reason_codes <- list()
    result$receipts <- list()
    result$citations <- list()
    result$tool_calls <- list()
    result$diagnostics <- list()
  } else {
    result <- rows
  }
  class(result) <- c("graft_verification", "data.frame")
  result
}
