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
    canonical_url = normalize_canonical_url(value),
    value
  )
}

normalize_canonical_url <- function(value) {
  # v1 preserves path/query bytes and canonicalizes only HTTP URL structure.
  match <- regexec(
    "^(https?)://([^/?#]*)([^?#]*)(\\?[^#]*)?(?:#.*)?$",
    value,
    ignore.case = TRUE,
    perl = TRUE
  )
  parts <- regmatches(value, match)[[1L]]
  if (length(parts) == 0L || !nzchar(parts[[3L]])) {
    return(value)
  }
  scheme <- tolower(parts[[2L]])
  authority <- normalize_url_authority(parts[[3L]], scheme)
  if (is.na(authority)) {
    return(value)
  }
  path <- parts[[4L]]
  query <- if (length(parts) >= 5L) parts[[5L]] else ""
  if (!nzchar(path)) {
    path <- "/"
  } else if (!identical(path, "/") && endsWith(path, "/")) {
    path <- substr(path, 1L, nchar(path) - 1L)
  }
  paste0(scheme, "://", authority, path, query)
}

normalize_url_authority <- function(authority, scheme) {
  at <- gregexpr("@", authority, fixed = TRUE)[[1L]]
  if (identical(at, -1L)) {
    userinfo <- ""
    host_port <- authority
  } else {
    split_at <- utils::tail(at, 1L)
    userinfo <- substr(authority, 1L, split_at)
    host_port <- substr(authority, split_at + 1L, nchar(authority))
  }
  if (startsWith(host_port, "[")) {
    match <- regexec(
      "^(\\[[^]]+\\])(?::([0-9]+))?$",
      host_port,
      perl = TRUE
    )
  } else {
    match <- regexec("^([^:]+)(?::([0-9]+))?$", host_port, perl = TRUE)
  }
  parts <- regmatches(host_port, match)[[1L]]
  if (length(parts) == 0L || !nzchar(parts[[2L]])) {
    return(NA_character_)
  }
  host <- tolower(parts[[2L]])
  if (!startsWith(host, "[") && startsWith(host, "www.")) {
    host <- substring(host, 5L)
  }
  port <- if (length(parts) >= 3L) parts[[3L]] else ""
  default_port <- identical(port, "80") &&
    identical(scheme, "http") ||
    identical(port, "443") && identical(scheme, "https")
  if (isTRUE(default_port)) {
    port <- ""
  }
  paste0(
    userinfo,
    host,
    if (nzchar(port)) paste0(":", port) else ""
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
    quote_identifier(connection, "_graft_origins"),
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
  rows <- DBI::dbGetQuery(
    store$connection,
    paste0(
      "SELECT DISTINCT class FROM ",
      quote_identifier(store$connection, graft_current_view_name),
      " WHERE record_id = ?"
    ),
    params = list(record_id)
  )
  as.character(rows$class)
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
    id_format <- scalar_character(class_contract$id_format, "graft")
    if (identical(id_format, "graft") && !is_graft_id(supplied_id)) {
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
    if (
      identical(id_format, "linkml") &&
        (length(supplied_id) != 1L || !nzchar(trimws(supplied_id)))
    ) {
      abort_identity_error(
        "A LinkML identifier must be one non-empty string.",
        record_class = record_class,
        input_row = input_row,
        record_id = supplied_id,
        field = "id",
        rule = "linkml_identifier",
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

resolve_candidate_identities <- function(manifest, batch, staged, snapshot) {
  flattened <- flatten_candidate_identities(staged)
  candidates <- flattened$candidates
  identifiers <- flattened$identifiers
  issues <- flattened$issues
  if (nrow(candidates) == 0L) {
    return(list(
      staged = staged,
      identifiers = empty_candidate_identifiers(),
      origins = empty_candidate_origins(),
      issues = issues
    ))
  }
  identifier_matches <- candidate_identifier_matches(
    identifiers,
    snapshot$identifiers
  )
  length(identifier_matches) <- nrow(candidates)
  origin_matches <- candidate_origin_matches(
    candidates,
    snapshot$origins,
    batch$producer
  )
  for (row in seq_len(nrow(candidates))) {
    external_ids <- unique(identifier_matches[[row]])
    origin_ids <- unique(origin_matches[[row]])
    supplied_id <- if (candidates$supplied_valid[[row]]) {
      candidates$supplied_id[[row]]
    } else {
      character()
    }
    if (length(external_ids) > 1L) {
      issues[[length(issues) + 1L]] <- candidate_identity_issue(
        candidates,
        row,
        field = candidate_identity_fields(identifiers, row),
        rule = "consistent_exact_identity",
        message = "Supplied external identifiers resolve to different records."
      )
    }
    if (
      length(supplied_id) == 1L &&
        length(external_ids) > 0L &&
        any(external_ids != supplied_id)
    ) {
      issues[[length(issues) + 1L]] <- candidate_identity_issue(
        candidates,
        row,
        field = "id",
        rule = "internal_external_identity_agreement",
        message = "The supplied internal ID conflicts with an external identifier."
      )
    }
    if (length(origin_ids) > 1L) {
      issues[[length(issues) + 1L]] <- candidate_identity_issue(
        candidates,
        row,
        field = ".graft_origin_key",
        rule = "unique_origin",
        message = "The producer origin key resolves to multiple records."
      )
    }
    resolved_ids <- unique(c(supplied_id, external_ids))
    if (
      length(resolved_ids) == 1L &&
        length(origin_ids) > 0L &&
        any(origin_ids != resolved_ids)
    ) {
      issues[[length(issues) + 1L]] <- candidate_identity_issue(
        candidates,
        row,
        field = ".graft_origin_key",
        rule = "origin_identity_agreement",
        message = "The producer origin conflicts with the resolved record ID."
      )
    }
  }
  parent <- seq_len(nrow(candidates))
  identity_groups <- split(
    identifiers$candidate_id,
    paste(
      "identifier",
      identifiers$class,
      identifiers$namespace,
      identifiers$normalized_value,
      sep = "\u001f"
    )
  )
  origin_present <- !is.na(candidates$origin_key)
  origin_groups <- split(
    candidates$candidate_id[origin_present],
    paste(
      "origin",
      candidates$class[origin_present],
      batch$producer,
      candidates$origin_key[origin_present],
      sep = "\u001f"
    )
  )
  for (group in c(identity_groups, origin_groups)) {
    if (length(group) < 2L) {
      next
    }
    for (candidate_id in group[-1L]) {
      parent <- union_candidate_components(parent, group[[1L]], candidate_id)
    }
  }
  component <- vapply(
    seq_len(nrow(candidates)),
    \(.x) candidate_component_root(parent, .x),
    integer(1)
  )
  assigned <- rep(NA_character_, nrow(candidates))
  matched_by <- rep("new", nrow(candidates))
  identity_reason <- rep("unresolved", nrow(candidates))
  identity_evidence <- rep(canonical_json(list()), nrow(candidates))
  current_classes <- split(
    as.character(snapshot$current$class),
    as.character(snapshot$current$record_id)
  )
  component_rows <- split(seq_len(nrow(candidates)), component)
  for (rows in component_rows) {
    known <- unique(c(
      candidates$supplied_id[rows][candidates$supplied_valid[rows]],
      unlist(identifier_matches[rows], use.names = FALSE),
      unlist(origin_matches[rows], use.names = FALSE)
    ))
    known <- known[!is.na(known) & nzchar(known)]
    if (length(known) > 1L) {
      for (row in rows) {
        issues[[length(issues) + 1L]] <- candidate_identity_issue(
          candidates,
          row,
          field = candidate_identity_fields(identifiers, row),
          rule = "consistent_exact_identity",
          message = "Candidate identity evidence resolves to multiple records."
        )
      }
      next
    }
    if (length(known) == 1L) {
      assigned[rows] <- known[[1L]]
      evidence <- component_resolution_evidence(
        candidates,
        identifiers,
        snapshot$identifiers,
        snapshot$origins,
        rows,
        known[[1L]],
        batch$producer
      )
      reason <- resolution_evidence_reason(evidence)
      matched_by[rows] <- reason
      identity_reason[rows] <- reason
      identity_evidence[rows] <- canonical_json(evidence)
      next
    }
    record_class <- candidates$class[[rows[[1L]]]]
    contract <- manifest$classes[[record_class]]
    policy <- scalar_character(contract$id_policy)
    if (identical(policy, "require")) {
      for (row in rows) {
        issues[[length(issues) + 1L]] <- candidate_identity_issue(
          candidates,
          row,
          field = "id",
          rule = "required_internal_id",
          message = "This class requires a supplied internal ID."
        )
      }
      next
    }
    if (
      identical(policy, "deterministic") &&
        any(vapply(
          rows,
          \(.x) candidate_deterministic_key_missing(staged, candidates, .x),
          logical(1)
        ))
    ) {
      for (row in rows) {
        issues[[length(issues) + 1L]] <- candidate_identity_issue(
          candidates,
          row,
          field = paste(
            empty_character(contract$origin_key_slots),
            collapse = ","
          ),
          rule = "deterministic_key_complete",
          message = "Deterministic identity requires every configured key field."
        )
      }
      next
    }
    identifier_keys <- sort(
      unique(candidate_component_identifier_keys(identifiers, rows)),
      method = "radix"
    )
    if (identical(policy, "deterministic")) {
      key_values <- candidate_deterministic_key_values(
        staged,
        candidates,
        rows[[1L]]
      )
      seed <- list(deterministic_keys = key_values)
      reason <- "deterministic_key"
      evidence <- list(list(
        kind = reason,
        slots = names(key_values),
        value_digest = graft_sha256(canonical_json(key_values))
      ))
    } else if (length(identifier_keys) > 0L) {
      seed <- list(exact_identifiers = identifier_keys)
      reason <- "exact_identifier_mint"
      evidence <- lapply(identifier_keys, \(.x) {
        list(kind = reason, key = .x)
      })
    } else {
      seed <- candidate_identity_seed(
        staged,
        candidates,
        rows[[1L]],
        batch$producer
      )
      reason <- "mint"
      evidence <- list(list(
        kind = reason,
        seed_digest = graft_sha256(canonical_json(seed))
      ))
    }
    assigned[rows] <- deterministic_graft_id(record_class, seed)
    matched_by[rows] <- reason
    identity_reason[rows] <- reason
    identity_evidence[rows] <- canonical_json(evidence)
  }
  candidates$record_id <- assigned
  candidates$matched_by <- matched_by
  candidates$identity_reason <- identity_reason
  candidates$identity_evidence <- identity_evidence
  for (row in seq_len(nrow(candidates))) {
    record_id <- candidates$record_id[[row]]
    if (is.na(record_id)) {
      next
    }
    actual <- unique(current_classes[[record_id]])
    incompatible <- setdiff(actual, candidates$class[[row]])
    if (length(incompatible) > 0L) {
      issues[[length(issues) + 1L]] <- candidate_identity_issue(
        candidates,
        row,
        field = "id",
        rule = "class_compatible_id",
        message = paste0(
          "Internal ID `",
          record_id,
          "` already belongs to another class."
        )
      )
    }
  }
  duplicate_ids <- unique(assigned[!is.na(assigned) & duplicated(assigned)])
  for (record_id in duplicate_ids) {
    for (row in which(assigned == record_id)) {
      issues[[length(issues) + 1L]] <- candidate_identity_issue(
        candidates,
        row,
        field = "id",
        rule = "unique_batch_id",
        message = paste0("Internal ID `", record_id, "` occurs more than once.")
      )
    }
  }
  mapped_identifiers <- map_candidate_identifiers(
    identifiers,
    assigned,
    snapshot$identifiers
  )
  identifier_keys <- paste(
    mapped_identifiers$class,
    mapped_identifiers$namespace,
    mapped_identifiers$normalized_value,
    sep = "\u001f"
  )
  for (key in unique(identifier_keys)) {
    indexes <- which(identifier_keys == key)
    mapped <- unique(mapped_identifiers$record_id[indexes])
    mapped <- mapped[!is.na(mapped)]
    if (length(mapped) < 2L) {
      next
    }
    for (candidate_id in unique(mapped_identifiers$candidate_id[indexes])) {
      issues[[length(issues) + 1L]] <- candidate_identity_issue(
        candidates,
        candidate_id,
        field = paste(unique(mapped_identifiers$slot[indexes]), collapse = ","),
        rule = "unique_exact_identity",
        message = "An exact identifier maps to multiple candidate records."
      )
    }
  }
  origins <- map_candidate_origins(candidates, batch$producer)
  origin_keys <- paste(
    origins$class,
    origins$producer,
    origins$origin_key,
    sep = "\u001f"
  )
  present_origins <- !is.na(origins$origin_key)
  for (key in unique(origin_keys[present_origins])) {
    indexes <- which(origin_keys == key)
    if (length(indexes) < 2L) {
      next
    }
    for (candidate_id in origins$candidate_id[indexes]) {
      issues[[length(issues) + 1L]] <- candidate_identity_issue(
        candidates,
        candidate_id,
        field = ".graft_origin_key",
        rule = "unique_batch_origin",
        message = "A producer origin key occurs more than once for a class."
      )
    }
  }
  for (row in seq_len(nrow(candidates))) {
    record_class <- candidates$class[[row]]
    input_row <- candidates$input_row[[row]]
    staged[[record_class]]$data$id[[input_row]] <- assigned[[row]]
    staged[[record_class]]$identities[[input_row]]$record_id <- assigned[[row]]
    staged[[record_class]]$identities[[input_row]]$matched_by <- matched_by[[
      row
    ]]
    staged[[record_class]]$identities[[input_row]]$identity_reason <-
      identity_reason[[row]]
    staged[[record_class]]$identities[[input_row]]$identity_evidence <-
      identity_evidence[[row]]
    staged[[record_class]]$identities[[
      input_row
    ]]$origin_key <- origins$origin_key[[row]]
  }
  list(
    staged = staged,
    identifiers = mapped_identifiers[
      c(
        "record_id",
        "class",
        "input_row",
        "slot",
        "namespace",
        "value",
        "normalized_value",
        "status",
        "assigned_by"
      )
    ],
    origins = origins[
      c("record_id", "class", "input_row", "producer", "origin_key")
    ],
    issues = issues
  )
}

flatten_candidate_identities <- function(staged) {
  candidates <- list()
  identifiers <- list()
  issues <- list()
  candidate_id <- 0L
  for (record_class in names(staged)) {
    class_staged <- staged[[record_class]]
    contract <- class_staged$contract
    for (index in seq_len(nrow(class_staged$data))) {
      candidate_id <- candidate_id + 1L
      identity <- class_staged$identities[[index]]
      supplied <- scalar_character(identity$supplied_id)
      valid <- is_valid_candidate_id(supplied, contract)
      if (!is.na(supplied) && !valid) {
        issues[[length(issues) + 1L]] <- new_plan_issue(
          record_class = record_class,
          input_row = index,
          record_id = supplied,
          field = "id",
          rule = if (
            identical(scalar_character(contract$id_format), "linkml")
          ) {
            "linkml_identifier"
          } else {
            "graft_ulid"
          },
          message = paste0("`", supplied, "` is not a valid record ID."),
          condition_class = "graft_identity_error"
        )
      }
      candidates[[length(candidates) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        class = record_class,
        input_row = as.integer(index),
        supplied_id = supplied,
        supplied_valid = valid,
        origin_key = scalar_character(identity$origin_key),
        stringsAsFactors = FALSE
      )
      for (identifier in identity$identifiers) {
        identifiers[[length(identifiers) + 1L]] <- data.frame(
          candidate_id = candidate_id,
          class = record_class,
          input_row = as.integer(index),
          slot = identifier$slot,
          namespace = identifier$namespace,
          value = identifier$value,
          normalized_value = identifier$normalized_value,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  list(
    candidates = if (length(candidates) == 0L) {
      empty_candidates()
    } else {
      do.call(rbind, candidates)
    },
    identifiers = if (length(identifiers) == 0L) {
      empty_candidate_identifier_input()
    } else {
      do.call(rbind, identifiers)
    },
    issues = issues
  )
}

is_valid_candidate_id <- function(record_id, contract) {
  if (is.na(record_id)) {
    return(FALSE)
  }
  if (identical(scalar_character(contract$id_format, "graft"), "graft")) {
    return(is_graft_id(record_id))
  }
  nzchar(trimws(record_id))
}

candidate_identifier_matches <- function(identifiers, stored) {
  matches <- vector("list", max(c(identifiers$candidate_id, 0L)))
  if (nrow(identifiers) == 0L || nrow(stored) == 0L) {
    return(matches)
  }
  stored_keys <- paste(
    stored$class,
    stored$namespace,
    stored$normalized_value,
    sep = "\u001f"
  )
  input_keys <- paste(
    identifiers$class,
    identifiers$namespace,
    identifiers$normalized_value,
    sep = "\u001f"
  )
  by_key <- split(as.character(stored$record_id), stored_keys)
  for (index in seq_len(nrow(identifiers))) {
    candidate_id <- identifiers$candidate_id[[index]]
    matches[candidate_id] <- list(unique(c(
      matches[[candidate_id]],
      by_key[[input_keys[[index]]]]
    )))
  }
  matches
}

candidate_origin_matches <- function(candidates, stored, producer) {
  matches <- vector("list", nrow(candidates))
  if (nrow(stored) == 0L) {
    return(matches)
  }
  stored_keys <- paste(
    stored$class,
    stored$producer,
    stored$origin_key,
    sep = "\u001f"
  )
  by_key <- split(as.character(stored$record_id), stored_keys)
  for (row in seq_len(nrow(candidates))) {
    if (is.na(candidates$origin_key[[row]])) {
      next
    }
    key <- paste(
      candidates$class[[row]],
      producer,
      candidates$origin_key[[row]],
      sep = "\u001f"
    )
    matches[[row]] <- unique(by_key[[key]])
  }
  matches
}

union_candidate_components <- function(parent, left, right) {
  left_root <- candidate_component_root(parent, left)
  right_root <- candidate_component_root(parent, right)
  if (left_root != right_root) {
    parent[[right_root]] <- left_root
  }
  parent
}

candidate_component_root <- function(parent, index) {
  while (parent[[index]] != index) {
    index <- parent[[index]]
  }
  index
}

candidate_identity_fields <- function(identifiers, candidate_id) {
  fields <- unique(identifiers$slot[identifiers$candidate_id == candidate_id])
  if (length(fields) == 0L) "id" else paste(fields, collapse = ",")
}

candidate_identity_issue <- function(candidates, row, field, rule, message) {
  record_id <- if ("record_id" %in% names(candidates)) {
    candidates$record_id[[row]]
  } else {
    candidates$supplied_id[[row]]
  }
  new_plan_issue(
    record_class = candidates$class[[row]],
    input_row = candidates$input_row[[row]],
    record_id = record_id,
    field = field,
    rule = rule,
    message = message,
    condition_class = "graft_identity_error"
  )
}

candidate_deterministic_key_missing <- function(staged, candidates, row) {
  record_class <- candidates$class[[row]]
  input_row <- candidates$input_row[[row]]
  contract <- staged[[record_class]]$contract
  keys <- empty_character(contract$origin_key_slots)
  length(keys) == 0L ||
    any(vapply(
      keys,
      \(.x) is_missing_value(staged[[record_class]]$data[[.x]][[input_row]]),
      logical(1)
    ))
}

candidate_deterministic_key_values <- function(staged, candidates, row) {
  record_class <- candidates$class[[row]]
  input_row <- candidates$input_row[[row]]
  keys <- empty_character(staged[[record_class]]$contract$origin_key_slots)
  values <- lapply(
    keys,
    \(.x) unname(staged[[record_class]]$data[[.x]][[input_row]])
  )
  names(values) <- keys
  values
}

component_resolution_evidence <- function(
  candidates,
  identifiers,
  stored_identifiers,
  stored_origins,
  rows,
  record_id,
  producer
) {
  evidence <- list()
  supplied <- rows[
    candidates$supplied_valid[rows] &
      candidates$supplied_id[rows] == record_id
  ]
  for (row in supplied) {
    evidence[[length(evidence) + 1L]] <- list(
      kind = "supplied_id",
      class = candidates$class[[row]],
      input_row = candidates$input_row[[row]],
      record_id = record_id
    )
  }
  stored_identifier_keys <- paste(
    stored_identifiers$class,
    stored_identifiers$namespace,
    stored_identifiers$normalized_value,
    stored_identifiers$record_id,
    sep = "\u001f"
  )
  candidate_identifier_keys <- paste(
    identifiers$class,
    identifiers$namespace,
    identifiers$normalized_value,
    record_id,
    sep = "\u001f"
  )
  matched_identifiers <- identifiers[
    identifiers$candidate_id %in%
      rows &
      candidate_identifier_keys %in% stored_identifier_keys,
    ,
    drop = FALSE
  ]
  for (index in seq_len(nrow(matched_identifiers))) {
    evidence[[length(evidence) + 1L]] <- list(
      kind = "external_identifier",
      class = matched_identifiers$class[[index]],
      input_row = matched_identifiers$input_row[[index]],
      slot = matched_identifiers$slot[[index]],
      namespace = matched_identifiers$namespace[[index]],
      normalized_value = matched_identifiers$normalized_value[[index]],
      record_id = record_id
    )
  }
  stored_origin_keys <- paste(
    stored_origins$class,
    stored_origins$producer,
    stored_origins$origin_key,
    stored_origins$record_id,
    sep = "\u001f"
  )
  candidate_origin_keys <- paste(
    candidates$class[rows],
    producer,
    candidates$origin_key[rows],
    record_id,
    sep = "\u001f"
  )
  matched_origins <- rows[candidate_origin_keys %in% stored_origin_keys]
  for (row in matched_origins) {
    evidence[[length(evidence) + 1L]] <- list(
      kind = "origin",
      class = candidates$class[[row]],
      input_row = candidates$input_row[[row]],
      producer = producer,
      origin_key = candidates$origin_key[[row]],
      record_id = record_id
    )
  }
  keys <- vapply(evidence, canonical_json, character(1))
  unname(evidence[order(keys, method = "radix")])
}

resolution_evidence_reason <- function(evidence) {
  kinds <- unique(vapply(evidence, \(.x) .x$kind, character(1)))
  if (length(kinds) > 1L) {
    return("agreeing_identity")
  }
  switch(
    kinds[[1L]],
    supplied_id = "supplied_id",
    external_identifier = "external_identifier",
    origin = "origin",
    "component_identity"
  )
}

candidate_component_identifier_keys <- function(identifiers, rows) {
  selected <- identifiers[identifiers$candidate_id %in% rows, , drop = FALSE]
  paste(
    "identifier",
    selected$class,
    selected$namespace,
    selected$normalized_value,
    sep = "\u001f"
  )
}

candidate_component_origin_keys <- function(candidates, rows, producer) {
  selected <- candidates[rows, , drop = FALSE]
  selected <- selected[!is.na(selected$origin_key), , drop = FALSE]
  paste("origin", selected$class, producer, selected$origin_key, sep = "\u001f")
}

candidate_identity_seed <- function(staged, candidates, row, producer) {
  record_class <- candidates$class[[row]]
  input_row <- candidates$input_row[[row]]
  values <- as.list(staged[[record_class]]$data[input_row, , drop = FALSE])
  values <- values[setdiff(names(values), c("id", "created_at", "updated_at"))]
  list(producer = producer, input_row = input_row, values = values)
}

map_candidate_identifiers <- function(identifiers, assigned, stored) {
  if (nrow(identifiers) == 0L) {
    return(empty_candidate_identifiers())
  }
  identifiers$record_id <- assigned[identifiers$candidate_id]
  identifier_key <- paste(
    identifiers$class,
    identifiers$namespace,
    identifiers$normalized_value,
    sep = "\u001f"
  )
  stored_key <- paste(
    stored$class,
    stored$namespace,
    stored$normalized_value,
    sep = "\u001f"
  )
  stored_index <- match(identifier_key, stored_key)
  same_record <- !is.na(stored_index) &
    stored$record_id[stored_index] == identifiers$record_id
  record_key <- paste(
    identifiers$class,
    identifiers$record_id,
    sep = "\u001f"
  )
  stored_primary <- stored$status == "primary"
  primary_record_key <- paste(
    stored$class[stored_primary],
    stored$record_id[stored_primary],
    sep = "\u001f"
  )
  has_primary <- record_key %in% primary_record_key
  identifiers$status <- rep("equivalent", nrow(identifiers))
  identifiers$status[same_record & has_primary] <- stored$status[
    stored_index[same_record & has_primary]
  ]
  order <- order(
    identifiers$class,
    identifiers$record_id,
    identifiers$namespace,
    identifiers$normalized_value,
    identifiers$slot,
    method = "radix"
  )
  needs_primary <- !has_primary[order] & !duplicated(record_key[order])
  identifiers$status[order[needs_primary]] <- "primary"
  identifiers$assigned_by <- "authoritative"
  identifiers
}

map_candidate_origins <- function(candidates, producer) {
  origin_key <- candidates$origin_key
  missing <- is.na(origin_key) & !is.na(candidates$record_id)
  origin_key[missing] <- paste0(
    "graft-record-v1:",
    candidates$record_id[missing]
  )
  data.frame(
    candidate_id = candidates$candidate_id,
    record_id = candidates$record_id,
    class = candidates$class,
    input_row = candidates$input_row,
    producer = producer,
    origin_key = origin_key,
    stringsAsFactors = FALSE
  )
}

empty_candidates <- function() {
  data.frame(
    candidate_id = integer(),
    class = character(),
    input_row = integer(),
    supplied_id = character(),
    supplied_valid = logical(),
    origin_key = character(),
    stringsAsFactors = FALSE
  )
}

empty_candidate_identifier_input <- function() {
  data.frame(
    candidate_id = integer(),
    class = character(),
    input_row = integer(),
    slot = character(),
    namespace = character(),
    value = character(),
    normalized_value = character(),
    stringsAsFactors = FALSE
  )
}

empty_candidate_identifiers <- function() {
  data.frame(
    record_id = character(),
    class = character(),
    input_row = integer(),
    slot = character(),
    namespace = character(),
    value = character(),
    normalized_value = character(),
    status = character(),
    assigned_by = character(),
    stringsAsFactors = FALSE
  )
}

empty_candidate_origins <- function() {
  data.frame(
    record_id = character(),
    class = character(),
    input_row = integer(),
    producer = character(),
    origin_key = character(),
    stringsAsFactors = FALSE
  )
}
