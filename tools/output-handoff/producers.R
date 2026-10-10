# Public producer adapters ---------------------------------------------------

# This file is sourced after handoff.R.  It intentionally consumes only the
# public Commons, ellmer, and Deputy values that a host receives at its
# boundary; private producer registries and constructors are out of scope.

producer_abort <- function(message, subclass = "handoff_producer_error") {
  handoff_abort(message, subclass = subclass)
}

producer_operation_id <- function(value) {
  handoff_text(value, "operation_id")
}

producer_plain_producer <- function(value) {
  handoff_named_object(value, "producer")
}

producer_slots <- function(keys, media_types) {
  if (
    !is.character(keys) ||
      anyNA(keys) ||
      !length(keys) ||
      !all(nzchar(keys)) ||
      anyDuplicated(keys)
  ) {
    producer_abort("`keys` must be unique, nonempty character keys.")
  }
  if (
    !is.character(media_types) ||
      anyNA(media_types) ||
      length(media_types) != length(keys) ||
      !all(nzchar(media_types))
  ) {
    producer_abort("`media_types` must match the declared output keys.")
  }
  list(keys = keys, media_types = media_types)
}

producer_content_tool_result <- function(value) {
  if (S7::S7_inherits(value, ellmer::ContentToolResult)) {
    if (!is.null(value@error)) {
      producer_abort("The producer returned a native ContentToolResult error.")
    }
    list(value = value@value, extra = value@extra)
  } else {
    list(value = value, extra = list())
  }
}

producer_commons_tag <- function(extra) {
  if (!is.list(extra) || is.null(extra$commons_tag)) {
    return(NULL)
  }
  tag <- extra$commons_tag
  if (
    !is.character(tag) ||
      length(tag) != 1L ||
      is.na(tag) ||
      !validUTF8(enc2utf8(tag)) ||
      !nzchar(tag) ||
      !identical(trimws(tag), tag) ||
      grepl("[[:cntrl:]]", tag) ||
      nchar(enc2utf8(tag), type = "bytes") > 1024L
  ) {
    producer_abort(
      "`ContentToolResult@extra$commons_tag` must be one bounded scalar."
    )
  }
  enc2utf8(tag)
}

producer_inline_image <- function(
  content,
  expected_media_type,
  index,
  max_bytes = handoff_default_max_bytes
) {
  if (!S7::S7_inherits(content, ellmer::ContentImageInline)) {
    producer_abort(
      paste0(
        "Output content ",
        index,
        " must be ContentText or ContentImageInline."
      )
    )
  }
  if (!identical(content@type, expected_media_type)) {
    producer_abort(
      paste0(
        "Inline image content ",
        index,
        " does not match its host-declared media type."
      )
    )
  }
  data <- content@data
  if (
    !is.character(data) ||
      length(data) != 1L ||
      is.na(data) ||
      !validUTF8(enc2utf8(data))
  ) {
    producer_abort(paste0("Inline image content ", index, " has no bytes."))
  }
  # Bound the source string before normalising line breaks.  jsonlite emits
  # wrapped base64 for larger values, so allow a small, explicit whitespace
  # overhead while still refusing an unbounded allocation.
  max_encoded_bytes <- 4 * ceiling(as.double(max_bytes) / 3) + 4
  max_whitespace_bytes <- max(4, ceiling(max_encoded_bytes / 32))
  raw_encoded_bytes <- nchar(data, type = "bytes")
  if (raw_encoded_bytes > max_encoded_bytes + max_whitespace_bytes) {
    producer_abort(paste0(
      "Inline image content ",
      index,
      " exceeds the declared byte bound."
    ))
  }
  normalized_data <- gsub("[[:space:]]+", "", data)
  normalized_bytes <- nchar(normalized_data, type = "bytes")
  if (
    normalized_bytes > max_encoded_bytes ||
      raw_encoded_bytes - normalized_bytes > max_whitespace_bytes
  ) {
    producer_abort(paste0(
      "Inline image content ",
      index,
      " exceeds the declared byte bound."
    ))
  }
  bytes <- tryCatch(
    jsonlite::base64_dec(normalized_data),
    error = \(error) NULL
  )
  if (
    !is.raw(bytes) ||
      length(bytes) > max_bytes ||
      !identical(
        gsub("[[:space:]]+", "", jsonlite::base64_enc(bytes)),
        normalized_data
      )
  ) {
    producer_abort(paste0(
      "Inline image content ",
      index,
      " is not canonical base64."
    ))
  }
  bytes
}

producer_content_items <- function(value, slots, max_bytes) {
  if (
    is.character(value) &&
      length(value) == 1L &&
      !is.na(value) &&
      validUTF8(enc2utf8(value))
  ) {
    if (nchar(enc2utf8(value), type = "bytes") > max_bytes) {
      producer_abort("Scalar producer text exceeds the declared byte bound.")
    }
    return(list(list(value, slots$media_types[[1L]])))
  }
  if (!is.list(value) || is.object(value) || !length(value)) {
    producer_abort(
      "A completed Commons value must be one text string or an ordered content list."
    )
  }
  if (length(value) > length(slots$keys)) {
    producer_abort("The producer returned more content items than host slots.")
  }
  supplied_names <- names(value)
  if (!is.null(supplied_names)) {
    if (
      anyNA(supplied_names) ||
        !all(nzchar(supplied_names)) ||
        anyDuplicated(supplied_names) ||
        !identical(supplied_names, slots$keys[seq_along(value)])
    ) {
      producer_abort(
        "Named content must use the host-declared output keys in order."
      )
    }
  }
  lapply(seq_along(value), function(index) {
    content <- value[[index]]
    media_type <- slots$media_types[[index]]
    if (S7::S7_inherits(content, ellmer::ContentText)) {
      text <- content@text
      if (
        !is.character(text) ||
          length(text) != 1L ||
          is.na(text) ||
          !validUTF8(enc2utf8(text))
      ) {
        producer_abort(paste0("Text content ", index, " is not valid UTF-8."))
      }
      if (nchar(enc2utf8(text), type = "bytes") > max_bytes) {
        producer_abort(paste0(
          "Text content ",
          index,
          " exceeds the declared byte bound."
        ))
      }
      return(list(enc2utf8(text), media_type))
    }
    list(
      producer_inline_image(content, media_type, index, max_bytes),
      media_type
    )
  })
}

producer_outputs <- function(
  value,
  keys,
  media_types,
  max_bytes = handoff_default_max_bytes
) {
  max_bytes <- handoff_limit(max_bytes, "max_bytes")
  slots <- producer_slots(keys, media_types)
  items <- producer_content_items(value, slots, max_bytes)
  Map(
    \(item, key) handoff_output(key, item[[1L]], item[[2L]]),
    items,
    slots$keys[seq_along(items)]
  )
}

producer_packet <- function(operation_id, producer, outputs) {
  list(
    schema = handoff_schema,
    operation_id = producer_operation_id(operation_id),
    state = "complete",
    producer = producer_plain_producer(producer),
    errors = list(),
    outputs = outputs
  )
}

commons_completion <- function(
  value,
  operation_id,
  producer,
  keys = c("report", "table", "figure"),
  media_types = c("text/plain", "application/json", "image/png"),
  max_bytes = handoff_default_max_bytes
) {
  content <- producer_content_tool_result(value)
  producer <- producer_plain_producer(producer)
  tag <- producer_commons_tag(content$extra)
  if (!is.null(tag)) {
    producer$commons_tag <- tag
  }
  producer_packet(
    operation_id = operation_id,
    producer = producer,
    outputs = producer_outputs(content$value, keys, media_types, max_bytes)
  )
}

producer_agent_result <- function(result) {
  if (!S7::S7_inherits(result, deputy::AgentResult)) {
    producer_abort("`result` must be a completed Deputy AgentResult.")
  }
  if (!identical(result$stop_reason, "complete")) {
    producer_abort(
      paste0("Deputy completed with stop reason `", result$stop_reason, "`.")
    )
  }
  result
}

producer_event_metadata <- function(event) {
  metadata <- list(
    result_id = event$result_id,
    result_type = event$result_type,
    tool_name = event$tool_name,
    tool_fingerprint = event$tool_fingerprint,
    tool_call_id = event$tool_call_id,
    arguments = event$arguments,
    run_id = event$run_id,
    agent_id = event$agent_id,
    session_id = event$session_id
  )
  # Keep the object JSON-compatible while retaining NULL fields for a stable
  # field vocabulary.  The core validator accepts explicit nulls.
  handoff_json_value(metadata, "producer$trusted_result")
  metadata
}

producer_delivery_failure <- function(result, event) {
  if (is.null(event$tool_call_id)) {
    return("The trusted result event has no tool call identity.")
  }
  matching <- Filter(
    function(item) {
      identical(item$type, "tool_end") &&
        identical(item$tool_call_id, event$tool_call_id)
    },
    result$events
  )
  if (!length(matching)) {
    return("The trusted producer call has no completed tool delivery event.")
  }
  failures <- Filter(
    function(item) {
      !is.null(item$tool_error)
    },
    matching
  )
  if (!length(failures)) {
    if (length(matching) != 1L) {
      return("The trusted producer call has an ambiguous tool delivery.")
    }
    return(NULL)
  }
  "The trusted producer call did not complete successfully."
}

deputy_completion <- function(
  result,
  result_type,
  operation_id,
  producer,
  keys = c("report", "table", "figure"),
  media_types = c("text/plain", "application/json", "image/png"),
  max_bytes = handoff_default_max_bytes
) {
  result <- producer_agent_result(result)
  if (
    !is.character(result_type) ||
      length(result_type) != 1L ||
      is.na(result_type) ||
      !nzchar(result_type)
  ) {
    producer_abort("`result_type` must be one nonempty string.")
  }
  events <- deputy::result_trusted_results(result, type = result_type)
  if (length(events) != 1L) {
    denied <- any(vapply(
      result$events,
      function(event) {
        identical(event$type, "permission") &&
          identical(event$decision, "deny")
      },
      logical(1)
    ))
    producer_abort(
      if (denied) {
        "The designated producer call was denied and produced no trusted result."
      } else {
        "A completed Deputy run must contain exactly one matching trusted result."
      }
    )
  }
  event <- events[[1L]]
  if (
    !identical(event$type, "trusted_result") ||
      is.null(event$value)
  ) {
    producer_abort(
      "The matching Deputy event is not a complete trusted result."
    )
  }
  delivery_error <- producer_delivery_failure(result, event)
  if (!is.null(delivery_error)) {
    producer_abort(delivery_error)
  }
  if (
    S7::S7_inherits(event$value, ellmer::ContentToolResult) &&
      !is.null(event$value@error)
  ) {
    producer_abort("The designated producer returned a native tool error.")
  }
  content <- producer_content_tool_result(event$value)
  producer <- producer_plain_producer(producer)
  tag <- producer_commons_tag(content$extra)
  if (!is.null(tag)) {
    producer$commons_tag <- tag
  }
  producer$trusted_result <- producer_event_metadata(event)
  producer_packet(
    operation_id = operation_id,
    producer = producer,
    outputs = producer_outputs(content$value, keys, media_types, max_bytes)
  )
}
