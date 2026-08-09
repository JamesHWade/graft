canonical_slot_value <- function(value, slot) {
  canonical_slot_type(slot)
  if (!scalar_logical(slot$multivalued)) {
    return(canonical_slot_scalar(value, slot))
  }
  if (is.null(value) || length(value) == 0L) {
    return(list())
  }
  values <- lapply(
    seq_along(value),
    \(index) canonical_slot_scalar(value[[index]], slot)
  )
  if (!scalar_logical(slot$ordered)) {
    keys <- vapply(values, canonical_json, character(1))
    values <- values[order(keys, method = "radix")]
  }
  unname(values)
}

canonical_slot_scalar <- function(value, slot) {
  type <- canonical_slot_type(slot)
  if (is.null(value) || length(value) == 0L) {
    return(NULL)
  }
  if (length(value) != 1L) {
    abort_backend_error(
      "A scalar logical-record value must contain exactly one item.",
      operation = "canonicalize_record",
      field = scalar_character(slot$name),
      value_length = length(value)
    )
  }
  if (scalar_logical(slot$object_reference)) {
    if (is.na(value)) {
      return(NA_character_)
    }
    return(as.character(value))
  }
  if (is.na(value)) {
    return(switch(
      type,
      BOOLEAN = NA,
      BIGINT = NA_real_,
      DOUBLE = NA_real_,
      DECIMAL = NA_real_,
      DATE = as.Date(NA_character_),
      TIME = NA_character_,
      TIMESTAMP = as.POSIXct(
        NA_real_,
        origin = "1970-01-01",
        tz = "UTC"
      ),
      NA_character_
    ))
  }
  switch(
    type,
    BOOLEAN = as.logical(value),
    BIGINT = as.numeric(value),
    DOUBLE = as.numeric(value),
    DECIMAL = as.numeric(value),
    DATE = as.Date(value),
    TIME = canonical_time_value(value),
    TIMESTAMP = as.POSIXct(value, tz = "UTC"),
    as.character(value)
  )
}

canonical_slot_type <- function(slot, operation = "canonicalize_record") {
  type <- toupper(scalar_character(slot$relational_type, "VARCHAR"))
  if (
    scalar_logical(slot$object_reference) &&
      !identical(type, "VARCHAR")
  ) {
    slot_name <- scalar_character(slot$name, "<unknown>")
    abort_schema_error(
      paste0(
        "Object-reference slot `",
        slot_name,
        "` must use relational type `VARCHAR`, not `",
        type,
        "`."
      ),
      operation = operation,
      field = slot_name,
      relational_type = type,
      rule = "object_reference_varchar"
    )
  }
  type
}

canonical_time_value <- function(value) {
  seconds <- if (inherits(value, "difftime")) {
    as.numeric(value, units = "secs")
  } else if (is.numeric(value)) {
    as.numeric(value)
  } else {
    parts <- as.numeric(strsplit(as.character(value), ":", fixed = TRUE)[[1L]])
    if (length(parts) < 2L || length(parts) > 3L || anyNA(parts)) {
      abort_backend_error(
        "A TIME value could not be canonicalized.",
        operation = "canonicalize_record",
        observed_value = value
      )
    }
    parts[[1L]] *
      3600 +
      parts[[2L]] * 60 +
      if (length(parts) == 3L) {
        parts[[3L]]
      } else {
        0
      }
  }
  total_microseconds <- round(seconds * 1e6)
  if (
    !is.finite(total_microseconds) ||
      total_microseconds < 0 ||
      total_microseconds >= 86400 * 1e6
  ) {
    abort_backend_error(
      "A TIME value must be between 00:00:00 and 23:59:59.999999.",
      operation = "canonicalize_record",
      observed_value = value
    )
  }
  hour <- floor(total_microseconds / (3600 * 1e6))
  remainder <- total_microseconds - hour * 3600 * 1e6
  minute <- floor(remainder / (60 * 1e6))
  remainder <- remainder - minute * 60 * 1e6
  second <- floor(remainder / 1e6)
  microsecond <- as.integer(remainder - second * 1e6)
  result <- sprintf("%02d:%02d:%02d", hour, minute, second)
  if (microsecond > 0L) {
    fraction <- sub("0+$", "", sprintf("%06d", microsecond))
    result <- paste0(result, ".", fraction)
  }
  result
}

logical_record_content <- function(payload) {
  payload[setdiff(names(payload), c("created_at", "updated_at"))]
}

logical_record_content_digest <- function(payload) {
  paste0(
    "sha256:",
    digest::digest(
      canonical_json(logical_record_content(payload)),
      algo = "sha256",
      serialize = FALSE
    )
  )
}

logical_record_changed_fields <- function(payload, prior_payload = NULL) {
  content <- logical_record_content(payload)
  if (is.null(prior_payload)) {
    return(sort(names(content), method = "radix"))
  }
  prior_content <- logical_record_content(prior_payload)
  fields <- union(names(content), names(prior_content))
  changed <- fields[vapply(
    fields,
    function(field) {
      current <- canonical_json(list(value = content[[field]]))
      prior <- canonical_json(list(value = prior_content[[field]]))
      !identical(current, prior)
    },
    logical(1)
  )]
  sort(changed, method = "radix")
}

changed_fields_json <- function(fields) {
  canonical_json(unname(as.list(fields)))
}

canonical_manifest_payload <- function(payload, contract) {
  slots <- contract$slots
  canonical <- payload
  for (slot_name in names(slots)) {
    if (!scalar_logical(slots[[slot_name]]$object_reference)) {
      next
    }
    canonical[slot_name] <- list(canonical_slot_value(
      payload[[slot_name]],
      slots[[slot_name]]
    ))
  }
  canonical
}

parse_revision_payload <- function(payload_json) {
  tryCatch(
    jsonlite::fromJSON(payload_json, simplifyVector = FALSE),
    error = function(error) {
      abort_backend_error(
        paste0(
          "Could not parse a record revision payload: ",
          conditionMessage(error)
        ),
        operation = "read_record_revision",
        parent = error
      )
    }
  )
}
