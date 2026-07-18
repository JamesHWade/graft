graft_id_pattern <- "^graft:[0-7][0-9A-HJKMNP-TV-Z]{25}$"
graft_identity_algorithm <- "graft-identity-v1"

new_graft_id <- function(time = Sys.time()) {
  alphabet <- strsplit("0123456789ABCDEFGHJKMNPQRSTVWXYZ", "")[[1L]]
  milliseconds <- floor(as.numeric(time) * 1000)
  time_digits <- integer(10L)
  for (index in 10:1) {
    time_digits[[index]] <- milliseconds %% 32
    milliseconds <- floor(milliseconds / 32)
  }
  random_digits <- sample.int(32L, 16L, replace = TRUE) - 1L
  paste0(
    "graft:",
    paste0(alphabet[c(time_digits, random_digits) + 1L], collapse = "")
  )
}

is_graft_id <- function(x) {
  is.character(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    grepl(graft_id_pattern, x)
}

deterministic_graft_id <- function(record_class, values) {
  payload <- paste0(
    graft_identity_algorithm,
    "\u001f",
    record_class,
    "\u001f",
    canonical_identity_value(values)
  )
  hex <- digest::digest(payload, algo = "sha256", serialize = FALSE)
  hex_to_graft_id(substr(hex, 1L, 32L))
}

hex_to_graft_id <- function(hex) {
  alphabet <- strsplit("0123456789ABCDEFGHJKMNPQRSTVWXYZ", "")[[1L]]
  binary_nibble <- c(
    "0000",
    "0001",
    "0010",
    "0011",
    "0100",
    "0101",
    "0110",
    "0111",
    "1000",
    "1001",
    "1010",
    "1011",
    "1100",
    "1101",
    "1110",
    "1111"
  )
  digits <- strsplit(tolower(hex), "")[[1L]]
  bits <- paste0(binary_nibble[strtoi(digits, base = 16L) + 1L], collapse = "")
  bits <- paste0("00", bits)
  groups <- substring(
    bits,
    seq.int(1L, nchar(bits), by = 5L),
    seq.int(5L, nchar(bits), by = 5L)
  )
  indexes <- vapply(
    groups,
    \(.x) strtoi(.x, base = 2L),
    integer(1)
  )
  paste0("graft:", paste0(alphabet[indexes + 1L], collapse = ""))
}

canonical_identity_value <- function(x) {
  as.character(jsonlite::toJSON(
    x,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    POSIXt = "ISO8601",
    UTC = TRUE,
    pretty = FALSE
  ))
}

normalize_external_identifier <- function(namespace, value) {
  if (is.null(value) || length(value) == 0L || is.na(value[[1L]])) {
    return(NA_character_)
  }
  value <- trimws(as.character(value[[1L]]))
  if (!nzchar(value)) {
    return(NA_character_)
  }
  namespace <- tolower(trimws(namespace))
  switch(
    namespace,
    doi = {
      normalized <- tolower(value)
      normalized <- sub("^https?://(dx\\.)?doi\\.org/", "", normalized)
      normalized <- sub("^doi\\s*:\\s*", "", normalized)
      trimws(normalized)
    },
    inchikey = toupper(gsub("\\s+", "", value)),
    cas = toupper(gsub(
      "\\s+",
      "",
      sub("^cas\\s*:\\s*", "", value, ignore.case = TRUE)
    )),
    content_hash = tolower(gsub("\\s+", "", value)),
    value
  )
}

external_identifiers_for_row <- function(class_contract, row) {
  slots <- Filter(
    \(.x) !is.na(scalar_character(.x$external_identifier)),
    class_contract$slots
  )
  identifiers <- list()
  normalized_slots <- list()
  for (slot_name in names(slots)) {
    if (!slot_name %in% names(row)) {
      next
    }
    value <- row[[slot_name]][[1L]]
    if (is.null(value) || length(value) == 0L || is.na(value)) {
      next
    }
    value <- as.character(value)
    if (!nzchar(trimws(value))) {
      next
    }
    namespace <- scalar_character(slots[[slot_name]]$external_identifier)
    normalized <- normalize_external_identifier(namespace, value)
    identifiers[[length(identifiers) + 1L]] <- list(
      slot = slot_name,
      namespace = namespace,
      value = value,
      normalized_value = normalized
    )
    normalized_slots[[slot_name]] <- normalized
  }
  list(
    identifiers = identifiers,
    normalized_slots = normalized_slots
  )
}

new_identity_state <- function() {
  state <- new.env(parent = emptyenv())
  state$identifiers <- new.env(hash = TRUE, parent = emptyenv())
  state$ids <- new.env(hash = TRUE, parent = emptyenv())
  state
}

identity_registry_key <- function(record_class, namespace, normalized_value) {
  paste(record_class, namespace, normalized_value, sep = "\u001f")
}

lookup_registered_identifier <- function(
  connection,
  record_class,
  namespace,
  normalized_value
) {
  sql <- paste0(
    "SELECT record_id FROM ",
    quote_identifier(connection, "_graft_identifiers"),
    " WHERE ",
    quote_identifier(connection, "class"),
    " = ? AND ",
    quote_identifier(connection, "namespace"),
    " = ? AND ",
    quote_identifier(connection, "normalized_value"),
    " = ? AND ",
    quote_identifier(connection, "status"),
    " IN ('primary', 'equivalent')"
  )
  rows <- DBI::dbGetQuery(
    connection,
    sql,
    params = list(record_class, namespace, normalized_value)
  )
  unique(as.character(rows$record_id))
}

lookup_origin_id <- function(
  connection,
  record_class,
  producer,
  origin_key
) {
  if (is.na(origin_key)) {
    return(character())
  }
  sql <- paste0(
    "SELECT record_id FROM ",
    quote_identifier(connection, "_graft_record_origins"),
    " WHERE ",
    quote_identifier(connection, "class"),
    " = ? AND ",
    quote_identifier(connection, "producer"),
    " = ? AND ",
    quote_identifier(connection, "origin_key"),
    " = ?"
  )
  rows <- DBI::dbGetQuery(
    connection,
    sql,
    params = list(record_class, producer, origin_key)
  )
  unique(as.character(rows$record_id))
}

find_existing_id_classes <- function(store, record_id) {
  classes <- store$schema$manifest$classes
  found <- character()
  for (record_class in names(classes)) {
    table <- scalar_character(classes[[record_class]]$table)
    sql <- paste0(
      "SELECT COUNT(*) AS n FROM ",
      quote_identifier(store$connection, table),
      " WHERE ",
      quote_identifier(store$connection, "id"),
      " = ?"
    )
    count <- DBI::dbGetQuery(
      store$connection,
      sql,
      params = list(record_id)
    )$n[[1L]]
    if (count > 0L) {
      found <- c(found, record_class)
    }
  }
  found
}

derive_origin_key <- function(class_contract, row) {
  explicit <- row[[".graft_origin_key"]]
  if (!is.null(explicit)) {
    value <- explicit[[1L]]
    if (!is.null(value) && length(value) == 1L && !is.na(value)) {
      value <- trimws(as.character(value))
      if (nzchar(value)) {
        return(value)
      }
    }
  }
  slots <- empty_character(class_contract$origin_key_slots)
  if (length(slots) == 0L || !all(slots %in% names(row))) {
    return(NA_character_)
  }
  values <- lapply(slots, function(slot) {
    value <- row[[slot]][[1L]]
    if (is.null(value) || length(value) == 0L || all(is.na(value))) {
      return(NULL)
    }
    unname(value)
  })
  if (any(vapply(values, is.null, logical(1)))) {
    return(NA_character_)
  }
  names(values) <- slots
  paste0(
    "graft-origin-v1:",
    digest::digest(
      canonical_identity_value(values),
      algo = "sha256",
      serialize = FALSE
    )
  )
}

resolve_record_identity <- function(
  store,
  batch,
  record_class,
  class_contract,
  row,
  input_row,
  state
) {
  supplied_id <- row$id[[1L]]
  if (
    !is.null(supplied_id) && length(supplied_id) > 0L && !is.na(supplied_id)
  ) {
    supplied_id <- as.character(supplied_id)
    if (!is_graft_id(supplied_id)) {
      abort_identity_error(
        paste0("`", supplied_id, "` is not a valid internal graft ID."),
        record_class = record_class,
        input_row = input_row,
        record_id = supplied_id,
        field = "id",
        rule = "graft_ulid",
        observed_value = supplied_id
      )
    }
  } else {
    supplied_id <- NA_character_
  }

  external <- external_identifiers_for_row(class_contract, row)
  matched_ids <- character()
  for (identifier in external$identifiers) {
    key <- identity_registry_key(
      record_class,
      identifier$namespace,
      identifier$normalized_value
    )
    staged <- if (exists(key, state$identifiers, inherits = FALSE)) {
      get(key, state$identifiers, inherits = FALSE)
    } else {
      character()
    }
    stored <- lookup_registered_identifier(
      store$connection,
      record_class,
      identifier$namespace,
      identifier$normalized_value
    )
    matches <- unique(c(staged, stored))
    if (length(matches) > 1L) {
      abort_identity_error(
        paste0(
          "Identifier `",
          identifier$namespace,
          ":",
          identifier$value,
          "` resolves to multiple records."
        ),
        record_class = record_class,
        input_row = input_row,
        record_id = supplied_id,
        field = identifier$slot,
        rule = "unique_exact_identity",
        observed_value = identifier$value,
        matched_record_ids = matches
      )
    }
    matched_ids <- c(matched_ids, matches)
  }
  matched_ids <- unique(matched_ids)
  if (length(matched_ids) > 1L) {
    abort_identity_error(
      "Supplied external identifiers resolve to different records.",
      record_class = record_class,
      input_row = input_row,
      record_id = supplied_id,
      field = paste(
        vapply(external$identifiers, \(.x) .x$slot, character(1)),
        collapse = ","
      ),
      rule = "consistent_exact_identity",
      observed_value = lapply(external$identifiers, \(.x) .x$value),
      matched_record_ids = matched_ids
    )
  }

  origin_key <- derive_origin_key(class_contract, row)
  matched_by <- "new"
  record_id <- supplied_id
  if (!is.na(supplied_id)) {
    existing_classes <- unique(c(
      find_existing_id_classes(store, supplied_id),
      if (exists(supplied_id, state$ids, inherits = FALSE)) {
        get(supplied_id, state$ids, inherits = FALSE)
      } else {
        character()
      }
    ))
    incompatible <- setdiff(existing_classes, record_class)
    if (length(incompatible) > 0L) {
      abort_identity_error(
        paste0(
          "Internal ID `",
          supplied_id,
          "` already belongs to class ",
          paste(incompatible, collapse = ", "),
          "."
        ),
        record_class = record_class,
        input_row = input_row,
        record_id = supplied_id,
        field = "id",
        rule = "class_compatible_id",
        observed_value = supplied_id,
        existing_classes = existing_classes
      )
    }
    if (length(matched_ids) == 1L && !identical(matched_ids, supplied_id)) {
      abort_identity_error(
        "The supplied internal ID conflicts with an external identifier.",
        record_class = record_class,
        input_row = input_row,
        record_id = supplied_id,
        field = "id",
        rule = "internal_external_identity_agreement",
        observed_value = supplied_id,
        matched_record_ids = matched_ids
      )
    }
    matched_by <- if (record_class %in% existing_classes) {
      "internal_id"
    } else {
      "new"
    }
  } else if (
    identical(scalar_character(class_contract$id_policy), "resolve_exact") &&
      length(matched_ids) == 1L
  ) {
    record_id <- matched_ids[[1L]]
    matched_by <- "external_identity"
  } else {
    origin_ids <- lookup_origin_id(
      store$connection,
      record_class,
      batch$producer,
      origin_key
    )
    if (length(origin_ids) > 1L) {
      abort_identity_error(
        "The producer origin key resolves to multiple records.",
        record_class = record_class,
        input_row = input_row,
        field = ".graft_origin_key",
        rule = "unique_origin",
        observed_value = origin_key,
        matched_record_ids = origin_ids
      )
    }
    if (length(origin_ids) == 1L) {
      record_id <- origin_ids[[1L]]
      matched_by <- "origin_key"
    } else {
      policy <- scalar_character(class_contract$id_policy)
      if (identical(policy, "require")) {
        abort_identity_error(
          "This class requires a supplied internal ID.",
          record_class = record_class,
          input_row = input_row,
          field = "id",
          rule = "required_internal_id",
          observed_value = NULL
        )
      }
      if (identical(policy, "deterministic")) {
        key_slots <- empty_character(class_contract$origin_key_slots)
        key_values <- lapply(key_slots, \(.x) row[[.x]][[1L]])
        names(key_values) <- key_slots
        missing <- vapply(
          key_values,
          \(.x) is.null(.x) || length(.x) == 0L || all(is.na(.x)),
          logical(1)
        )
        if (length(key_values) == 0L || any(missing)) {
          abort_identity_error(
            "Deterministic identity requires every configured key slot.",
            record_class = record_class,
            input_row = input_row,
            field = paste(key_slots[missing], collapse = ","),
            rule = "deterministic_key_complete",
            observed_value = key_values
          )
        }
        record_id <- deterministic_graft_id(record_class, key_values)
        existing_classes <- find_existing_id_classes(store, record_id)
        matched_by <- if (record_class %in% existing_classes) {
          "deterministic"
        } else {
          "new"
        }
      } else {
        record_id <- new_graft_id()
      }
    }
  }

  if (is.na(origin_key)) {
    origin_key <- paste0("graft-record-v1:", record_id)
  }
  existing_origin_ids <- lookup_origin_id(
    store$connection,
    record_class,
    batch$producer,
    origin_key
  )
  if (
    length(existing_origin_ids) > 0L &&
      !record_id %in% existing_origin_ids
  ) {
    abort_identity_error(
      "The producer origin key conflicts with the resolved internal ID.",
      record_class = record_class,
      input_row = input_row,
      record_id = record_id,
      field = ".graft_origin_key",
      rule = "origin_identity_agreement",
      observed_value = origin_key,
      matched_record_ids = existing_origin_ids
    )
  }
  assign(record_id, record_class, state$ids)
  for (identifier in external$identifiers) {
    key <- identity_registry_key(
      record_class,
      identifier$namespace,
      identifier$normalized_value
    )
    assign(key, record_id, state$identifiers)
  }
  list(
    record_id = record_id,
    matched_by = matched_by,
    origin_key = origin_key,
    identifiers = external$identifiers,
    normalized_slots = external$normalized_slots
  )
}
