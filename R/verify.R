#' Verify recorded Graft evidence for assistant answers
#'
#' `graft_verify()` inspects the turns already recorded by an [ellmer::Chat]
#' and classifies each completed, text-bearing assistant answer. Verification
#' is deterministic and offline: it does not call a model, reopen a Graft
#' store, or authenticate receipt identifiers.
#'
#' Successful governed-measure-only evidence is `"verified"`. Successful
#' generic Graft reads are `"cited"` only when every result is independently
#' matched to an explicit quotation or Markdown blockquote in the answer. A
#' generic read caps mixed measure and generic evidence at `"cited"`. Unknown,
#' errored, malformed, unsupported, and citation-unmatched evidence paths fail
#' closed as `"untrusted"`.
#'
#' Verification classifies the recorded evidence path. It does not fact-check
#' the answer or cryptographically authenticate receipt identifiers.
#'
#' @param chat An [ellmer::Chat] whose recorded turns should be verified.
#'
#' @return A `graft_verification` data frame with one row per completed answer.
#'   Scalar columns contain `answer_index`, `turn_index`, `answer_text`, and
#'   `label`. List columns contain `reason_codes`, `receipts`, `citations`,
#'   `tool_calls`, and `diagnostics`. Each citation records its tool-call index,
#'   candidate type and text, and matched result path and text. A chat without
#'   completed answers returns the same columns with zero rows.
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
  answer_text <- vapply(
    turns[answer_turns],
    \(turn) turn@text,
    character(1)
  )
  classifications <- Map(
    graft_verification_classify,
    windows,
    answer_text
  )
  result <- data.frame(
    answer_index = seq_along(answer_turns),
    turn_index = as.integer(answer_turns),
    answer_text = answer_text,
    label = vapply(classifications, `[[`, character(1), "label")
  )
  result$reason_codes <- lapply(classifications, `[[`, "reason_codes")
  result$receipts <- lapply(windows, `[[`, "receipts")
  result$citations <- lapply(classifications, `[[`, "citations")
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

graft_verification_classify <- function(window, answer_text) {
  if (length(window$tool_calls) == 0L && !window$unsupported) {
    return(list(
      label = "untrusted",
      reason_codes = "no_evidence",
      citations = list(),
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
  generic_count <- 0L
  matched_generic_count <- 0L
  citations <- list()
  truncated <- FALSE
  boundary_keys <- character()
  supported <- c(
    "graft_find",
    "graft_get",
    "graft_query",
    "graft_history",
    "graft_measure"
  )
  for (call_index in seq_along(window$tool_calls)) {
    call <- window$tool_calls[[call_index]]
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
      generic_count <- generic_count + 1L
      matches <- graft_verification_match_citations(
        answer_text,
        result@value$result,
        call_index
      )
      if (length(matches) == 0L) {
        reasons[["unmatched_citation"]] <- TRUE
      } else {
        matched_generic_count <- matched_generic_count + 1L
        citations <- c(citations, matches)
      }
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
  if (
    length(observed) == 0L &&
      generic_count > 0L &&
      identical(matched_generic_count, generic_count)
  ) {
    return(list(
      label = "cited",
      reason_codes = "matched_citations",
      citations = citations,
      diagnostics = diagnostics
    ))
  }
  if (length(observed) == 0L && measure_count > 0L) {
    return(list(
      label = "verified",
      reason_codes = "governed_measure_only",
      citations = citations,
      diagnostics = diagnostics
    ))
  }
  list(
    label = "untrusted",
    reason_codes = observed,
    citations = citations,
    diagnostics = diagnostics
  )
}

graft_verification_match_citations <- function(
  answer_text,
  result,
  tool_call_index
) {
  candidates <- c(
    graft_verification_quotation_candidates(answer_text),
    graft_verification_blockquote_candidates(answer_text)
  )
  values <- graft_verification_text_values(result)
  matches <- list()
  for (candidate in candidates) {
    matching <- which(vapply(
      values,
      \(value) {
        grepl(
          candidate$normalized_text,
          graft_verification_normalize_text(value$text),
          fixed = TRUE
        )
      },
      logical(1)
    ))
    if (length(matching) == 0L) {
      next
    }
    value <- values[[matching[[1L]]]]
    matches[[length(matches) + 1L]] <- list(
      tool_call_index = as.integer(tool_call_index),
      candidate_type = candidate$type,
      text = candidate$text,
      result_path = value$path,
      result_text = value$text
    )
  }
  matches
}

graft_verification_quotation_candidates <- function(text) {
  pattern <- paste(
    c(
      "(\"[^\"\r\n]+\")",
      "(\u201c[^\u201d\r\n]+\u201d)",
      "(\u201e[^\u201c\r\n]+\u201c)",
      "(\u201f[^\u201d\r\n]+\u201d)",
      "(\u00ab[^\u00bb\r\n]+\u00bb)",
      "(\u2018[^\u2019\r\n]+\u2019)",
      "(\u201a[^\u2018\r\n]+\u2018)",
      "(\u201b[^\u2019\r\n]+\u2019)",
      "(\u2039[^\u203a\r\n]+\u203a)"
    ),
    collapse = "|"
  )
  locations <- gregexpr(pattern, text, perl = TRUE)[[1L]]
  if (identical(locations, -1L)) {
    return(list())
  }
  lengths <- attr(locations, "match.length")
  candidates <- Map(
    function(start, length) {
      quoted <- substr(text, start, start + length - 1L)
      candidate <- substr(quoted, 2L, nchar(quoted) - 1L)
      graft_verification_candidate(candidate, "quotation")
    },
    locations,
    lengths
  )
  Filter(Negate(is.null), candidates)
}

graft_verification_blockquote_candidates <- function(text) {
  lines <- strsplit(text, "\\r?\\n", perl = TRUE)[[1L]]
  is_marker <- grepl("^[ ]{0,3}>", lines, perl = TRUE)
  blocks <- list()
  index <- 1L
  while (index <= length(lines)) {
    if (!is_marker[[index]]) {
      index <- index + 1L
      next
    }
    block <- character()
    paragraph_active <- FALSE
    while (index <= length(lines)) {
      line <- lines[[index]]
      if (is_marker[[index]]) {
        stripped <- sub(
          "^(?:[ ]{0,3}>[ \\t]?)+",
          "",
          line,
          perl = TRUE
        )
        block <- c(
          block,
          stripped
        )
        paragraph_active <- graft_verification_markdown_paragraph_line(stripped)
      } else if (
        paragraph_active &&
          nzchar(trimws(line)) &&
          (grepl("^(?: {4}|\\t)", line, perl = TRUE) ||
            graft_verification_markdown_paragraph_line(line))
      ) {
        block <- c(block, line)
      } else {
        break
      }
      index <- index + 1L
    }
    blocks[[length(blocks) + 1L]] <- paste(block, collapse = "\n")
  }
  candidates <- lapply(
    blocks,
    \(candidate) graft_verification_candidate(candidate, "blockquote")
  )
  Filter(Negate(is.null), candidates)
}

graft_verification_markdown_paragraph_line <- function(text) {
  if (
    !nzchar(trimws(text)) ||
      grepl("^(?: {4}|\\t)", text, perl = TRUE)
  ) {
    return(FALSE)
  }
  text <- sub("^ {0,3}", "", text)
  block_starts <- c(
    "^#{1,6}(?:[ \\t]+|$)",
    "^(?:`{3,}|~{3,})",
    "^>",
    "^(?:[-+*][ \\t]+|[0-9]{1,9}[.)][ \\t]+)",
    "^(?:(?:\\*[ \\t]*){3,}|(?:-[ \\t]*){3,}|(?:_[ \\t]*){3,})$",
    "^=+[ \\t]*$",
    "^\\[[^]]+\\]:",
    "^<(?:!--|!\\[CDATA\\[|\\?|![A-Z])",
    paste0(
      "^</?(?i:",
      paste(
        c(
          "address",
          "article",
          "aside",
          "base",
          "basefont",
          "blockquote",
          "body",
          "caption",
          "center",
          "col",
          "colgroup",
          "dd",
          "details",
          "dialog",
          "dir",
          "div",
          "dl",
          "dt",
          "fieldset",
          "figcaption",
          "figure",
          "footer",
          "form",
          "frame",
          "frameset",
          "h[1-6]",
          "head",
          "header",
          "hr",
          "html",
          "iframe",
          "legend",
          "li",
          "link",
          "main",
          "menu",
          "menuitem",
          "nav",
          "noframes",
          "ol",
          "optgroup",
          "option",
          "p",
          "param",
          "pre",
          "script",
          "search",
          "section",
          "style",
          "summary",
          "table",
          "tbody",
          "td",
          "textarea",
          "tfoot",
          "th",
          "thead",
          "title",
          "tr",
          "track",
          "ul"
        ),
        collapse = "|"
      ),
      ")(?:[ \\t/>]|$)"
    )
  )
  !any(vapply(
    block_starts,
    \(pattern) grepl(pattern, text, perl = TRUE),
    logical(1)
  ))
}

graft_verification_candidate <- function(text, type) {
  normalized <- graft_verification_normalize_text(text)
  if (nchar(normalized) < 10L) {
    return(NULL)
  }
  list(
    type = type,
    text = text,
    normalized_text = normalized
  )
}

graft_verification_normalize_text <- function(text) {
  text <- gsub("[\u2018\u2019\u201a\u201b\u2039\u203a]", "'", text)
  text <- gsub("[\u201c\u201d\u201e\u201f\u00ab\u00bb]", "\"", text)
  text <- gsub("[\u2010\u2011\u2012\u2013\u2014\u2015\u2212]", "-", text)
  text <- graft_verification_strip_emphasis(text)
  trimws(gsub("[[:space:]]+", " ", text))
}

graft_verification_strip_emphasis <- function(text) {
  xml <- commonmark::markdown_xml(text, sourcepos = TRUE)
  pattern <- paste0(
    "<(emph|strong) sourcepos=\"",
    "([0-9]+):([0-9]+)-([0-9]+):([0-9]+)\""
  )
  matches <- regmatches(
    xml,
    gregexpr(pattern, xml, perl = TRUE)
  )[[1L]]
  if (length(matches) == 0L) {
    return(text)
  }
  captures <- do.call(
    rbind,
    lapply(matches, function(match) {
      regmatches(match, regexec(pattern, match, perl = TRUE))[[1L]]
    })
  )
  ranges <- data.frame(
    type = captures[, 2L],
    start_line = as.integer(captures[, 3L]),
    start_column = as.integer(captures[, 4L]),
    end_line = as.integer(captures[, 5L]),
    end_column = as.integer(captures[, 6L])
  )
  ranges$width <- ifelse(ranges$type == "strong", 2L, 1L)
  range_key <- paste(
    ranges$start_line,
    ranges$start_column,
    ranges$end_line,
    ranges$end_column,
    sep = ":"
  )
  groups <- split(seq_len(nrow(ranges)), range_key)
  lines <- strsplit(text, "\\r?\\n", perl = TRUE)[[1L]]
  bytes <- lapply(lines, charToRaw)
  removed <- lapply(bytes, \(line) rep(FALSE, length(line)))
  for (indices in groups) {
    range <- ranges[indices[[1L]], , drop = FALSE]
    width <- sum(ranges$width[indices])
    if (
      range$start_line > length(bytes) ||
        range$end_line > length(bytes)
    ) {
      next
    }
    start <- range$start_column + seq_len(width) - 1L
    end <- seq.int(range$end_column - width + 1L, range$end_column)
    if (
      any(start > length(bytes[[range$start_line]])) ||
        any(end < 1L) ||
        any(end > length(bytes[[range$end_line]]))
    ) {
      next
    }
    markers <- c(
      bytes[[range$start_line]][start],
      bytes[[range$end_line]][end]
    )
    if (
      !all(as.integer(markers) %in% c(42L, 95L)) ||
        length(unique(as.integer(markers))) != 1L
    ) {
      next
    }
    removed[[range$start_line]][start] <- TRUE
    removed[[range$end_line]][end] <- TRUE
  }
  lines <- Map(
    \(line, drop) rawToChar(line[!drop]),
    bytes,
    removed
  )
  paste(unlist(lines, use.names = FALSE), collapse = "\n")
}

graft_verification_text_values <- function(value, path = "result") {
  if (is.factor(value)) {
    value <- as.character(value)
  }
  if (is.data.frame(value)) {
    values <- list()
    for (name in names(value)) {
      values <- c(
        values,
        graft_verification_text_values(value[[name]], paste0(path, "$", name))
      )
    }
    return(values)
  }
  if (is.list(value)) {
    values <- list()
    value_names <- names(value)
    for (index in seq_along(value)) {
      name <- if (is.null(value_names)) "" else value_names[[index]]
      item_path <- if (nzchar(name)) {
        paste0(path, "$", name)
      } else {
        paste0(path, "[[", index, "]]")
      }
      values <- c(
        values,
        graft_verification_text_values(value[[index]], item_path)
      )
    }
    return(values)
  }
  if (!is.character(value)) {
    return(list())
  }
  indices <- which(!is.na(value))
  lapply(indices, function(index) {
    item_path <- if (length(value) == 1L) {
      path
    } else {
      paste0(path, "[", index, "]")
    }
    list(path = item_path, text = value[[index]])
  })
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
