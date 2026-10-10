# Bounded completed-output handoff prototype ---------------------------------

handoff_schema <- "graft-output-handoff/0.1"
handoff_default_required <- c("report", "table", "figure")
handoff_default_max_bytes <- 1024^2
handoff_default_max_total_bytes <- 4 * 1024^2
handoff_default_max_metadata_bytes <- 64 * 1024
# Bound descriptor count before any base64 payload is decoded.
handoff_max_outputs <- 128L
handoff_max_artifacts <- 1000L

handoff_abort <- function(message, subclass = "handoff_schema_error") {
  rlang::abort(
    message,
    class = c(subclass, "handoff_error"),
    call = rlang::caller_env()
  )
}

handoff_text <- function(value, name) {
  if (!rlang::is_string(value)) {
    handoff_abort(
      paste0("`", name, "` must be one bounded UTF-8 string."),
      "handoff_input_error"
    )
  }
  value <- enc2utf8(value)
  if (
    !validUTF8(value) ||
      !nzchar(value) ||
      !identical(trimws(value), value) ||
      grepl("[[:cntrl:]]", value) ||
      nchar(value, type = "bytes") > 1024L
  ) {
    handoff_abort(
      paste0("`", name, "` must be one bounded UTF-8 string."),
      "handoff_input_error"
    )
  }
  attributes(value) <- NULL
  value
}

handoff_plain_list <- function(value, name, named = FALSE) {
  if (
    !is.list(value) ||
      is.object(value) ||
      length(setdiff(names(attributes(value)), "names"))
  ) {
    handoff_abort(paste0("`", name, "` must be a plain list."))
  }
  if (
    named &&
      (is.null(names(value)) ||
        anyNA(names(value)) ||
        !all(nzchar(names(value))) ||
        anyDuplicated(names(value)))
  ) {
    handoff_abort(paste0("`", name, "` must be a named plain JSON object."))
  }
  value
}

handoff_named_object <- function(value, name) {
  handoff_plain_list(value, name, named = TRUE)
}

handoff_json_charge <- function(state, amount, max_bytes, name) {
  state$bytes <- state$bytes + as.numeric(amount)
  if (state$bytes > max_bytes) {
    handoff_abort(
      paste0("`", name, "` exceeds the JSON metadata byte bound."),
      "handoff_bounds_error"
    )
  }
}

handoff_json_value <- function(
  value,
  name,
  depth = 0L,
  max_bytes = Inf,
  state = NULL
) {
  if (is.null(state)) {
    state <- new.env(parent = emptyenv())
    state$bytes <- 0
  }
  if (depth > 16L) {
    handoff_abort(
      paste0("`", name, "` exceeds the JSON nesting bound."),
      "handoff_bounds_error"
    )
  }
  if (is.list(value)) {
    value <- handoff_plain_list(value, name)
    value_names <- names(value)
    if (!is.null(value_names)) {
      if (anyNA(value_names) || !all(nzchar(value_names))) {
        handoff_abort(paste0("`", name, "` has an invalid JSON object name."))
      }
      if (anyDuplicated(value_names)) {
        handoff_abort(paste0("`", name, "` has duplicate JSON object names."))
      }
    }
    handoff_json_charge(state, 2L + length(value), max_bytes, name)
    if (!is.null(value_names)) {
      handoff_json_charge(
        state,
        sum(6 * nchar(enc2utf8(value_names), type = "bytes") + 2),
        max_bytes,
        name
      )
    }
    for (index in seq_along(value)) {
      child_name <- paste0(name, "[", index, "]")
      handoff_json_value(
        value[[index]],
        child_name,
        depth + 1L,
        max_bytes,
        state
      )
    }
    return(invisible(NULL))
  }
  if (is.object(value) || !is.null(attributes(value))) {
    handoff_abort(paste0("`", name, "` contains an arbitrary R object."))
  }
  if (is.null(value)) {
    handoff_json_charge(state, 4L, max_bytes, name)
    return(invisible(NULL))
  }
  if (is.character(value) && !anyNA(value) && all(validUTF8(enc2utf8(value)))) {
    handoff_json_charge(
      state,
      sum(6 * nchar(enc2utf8(value), type = "bytes") + 2),
      max_bytes,
      name
    )
    return(invisible(NULL))
  }
  if (is.logical(value) && !anyNA(value)) {
    handoff_json_charge(state, 5 * length(value), max_bytes, name)
    return(invisible(NULL))
  }
  if (
    is.numeric(value) &&
      !anyNA(value) &&
      all(is.finite(value))
  ) {
    handoff_json_charge(state, 32 * length(value), max_bytes, name)
    return(invisible(NULL))
  }
  handoff_abort(paste0(
    "`",
    name,
    "` contains a value that is not JSON-compatible."
  ))
}

handoff_json_bytes <- function(value, name, max_bytes = Inf) {
  handoff_json_value(value, name, max_bytes = max_bytes)
  tryCatch(
    charToRaw(enc2utf8(jsonlite::toJSON(
      value,
      auto_unbox = TRUE,
      null = "null",
      digits = NA,
      pretty = FALSE
    ))),
    error = function(error) {
      handoff_abort(paste0("`", name, "` could not be encoded as JSON."))
    }
  )
}

handoff_size <- function(value, name) {
  if (
    !is.numeric(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.finite(value) ||
      value < 0 ||
      value != floor(value) ||
      value > .Machine$integer.max
  ) {
    handoff_abort(paste0("`", name, "` must be a nonnegative whole number."))
  }
  as.integer(value)
}

handoff_limit <- function(value, name) {
  value <- handoff_size(value, name)
  if (value < 1L) {
    handoff_abort(
      paste0("`", name, "` must be a positive whole number."),
      "handoff_input_error"
    )
  }
  value
}

handoff_digest <- function(value, name) {
  if (!rlang::is_string(value) || !grepl("^[0-9a-f]{64}$", value)) {
    handoff_abort(paste0("`", name, "` must be a lowercase SHA-256 digest."))
  }
  attributes(value) <- NULL
  value
}

handoff_sha256 <- function(bytes) {
  digest::digest(bytes, algo = "sha256", serialize = FALSE)
}

handoff_base64 <- function(bytes) {
  gsub("[[:space:]]", "", jsonlite::base64_enc(bytes), perl = TRUE)
}

handoff_ref_record <- function(ref) {
  if (!S7::S7_inherits(ref, ArtifactRef)) {
    handoff_abort("A retained output reference must be an ArtifactRef value.")
  }
  list(
    id = handoff_text(ref@id, "ref$id"),
    revision = handoff_digest(ref@revision, "ref$revision")
  )
}

handoff_ref_value <- function(record, name = "ref") {
  record <- handoff_plain_list(record, name)
  if (!identical(names(record), c("id", "revision"))) {
    handoff_abort(paste0(
      "`",
      name,
      "` must contain exactly `id` and `revision`."
    ))
  }
  ArtifactRef(
    id = handoff_text(record$id, paste0(name, "$id")),
    revision = handoff_digest(record$revision, paste0(name, "$revision"))
  )
}

handoff_descriptor <- function(value, max_bytes) {
  value <- handoff_plain_list(value, "output descriptor")
  if (!identical(names(value)[names(value) == "encoding"], "encoding")) {
    handoff_abort("Each output descriptor must declare an encoding.")
  }
  encoding <- handoff_text(value$encoding, "output$encoding")
  if (!encoding %in% c("base64", "retained")) {
    handoff_abort(
      "An output descriptor encoding must be `base64` or `retained`."
    )
  }
  fields <- c(
    "key",
    "media_type",
    "size",
    "sha256",
    "encoding",
    if (identical(encoding, "base64")) "data" else "ref"
  )
  if (!identical(sort(names(value)), sort(fields))) {
    handoff_abort("An output descriptor has unsupported or missing fields.")
  }
  descriptor <- list(
    key = handoff_text(value$key, "output$key"),
    media_type = handoff_text(value$media_type, "output$media_type"),
    size = handoff_size(value$size, "output$size"),
    sha256 = handoff_digest(value$sha256, "output$sha256"),
    encoding = encoding
  )
  if (descriptor$size > max_bytes) {
    handoff_abort(
      "An output exceeds the per-output byte bound.",
      "handoff_bounds_error"
    )
  }
  if (identical(encoding, "base64")) {
    data <- value$data
    if (
      !rlang::is_string(data) ||
        !is.null(attributes(data)) ||
        !validUTF8(data)
    ) {
      handoff_abort("A base64 output must contain one data string.")
    }
    encoded_input_size <- nchar(data, type = "bytes")
    max_encoded_size <- 4 * ceiling(as.numeric(max_bytes) / 3)
    if (encoded_input_size > 2 * max_encoded_size) {
      handoff_abort(
        "A base64 output exceeds the encoded byte bound.",
        "handoff_bounds_error"
      )
    }
    data <- gsub("[[:space:]]", "", data, perl = TRUE)
    encoded_size <- nchar(data, type = "bytes")
    if (encoded_size != 4 * ceiling(as.numeric(descriptor$size) / 3)) {
      handoff_abort(
        "A base64 output has an incomplete or oversized byte string."
      )
    }
    bytes <- tryCatch(
      jsonlite::base64_dec(data),
      error = function(error) {
        handoff_abort("A base64 output contains invalid data.")
      }
    )
    if (!is.raw(bytes) || !identical(handoff_base64(bytes), data)) {
      handoff_abort("A base64 output must contain canonical complete bytes.")
    }
    if (
      !identical(descriptor$size, as.integer(length(bytes))) ||
        !identical(descriptor$sha256, handoff_sha256(bytes))
    ) {
      handoff_abort("A base64 output size or digest does not match its bytes.")
    }
    descriptor$data <- data
    return(list(descriptor = descriptor, bytes = bytes, ref = NULL))
  }
  ref <- handoff_ref_record(handoff_ref_value(value$ref, "output$ref"))
  descriptor$ref <- ref
  list(descriptor = descriptor, bytes = NULL, ref = ref)
}

handoff_descriptor_metadata <- function(descriptor) {
  result <- descriptor[c("key", "media_type", "size", "sha256", "encoding")]
  if (identical(descriptor$encoding, "retained")) {
    result$ref <- descriptor$ref
  }
  result
}

handoff_root_outputs <- function(descriptors, refs, keys) {
  result <- Map(
    function(descriptor, ref) {
      list(
        key = descriptor$key,
        descriptor = handoff_descriptor_metadata(descriptor),
        ref = ref
      )
    },
    descriptors,
    refs
  )
  names(result) <- keys
  result
}

handoff_check_metadata <- function(
  bytes,
  max_metadata_bytes,
  store_limit,
  name
) {
  if (length(bytes) > max_metadata_bytes || length(bytes) > store_limit) {
    handoff_abort(
      paste0(name, " metadata exceeds its configured byte bound."),
      "handoff_bounds_error"
    )
  }
}

handoff_closure_info <- function(store, roots, max_artifacts) {
  pending <- unname(roots)
  pending_keys <- vapply(
    pending,
    \(ref) paste(ref@id, ref@revision, sep = "\n"),
    character(1)
  )
  seen <- character()
  sizes <- numeric()
  while (length(pending)) {
    ref <- pending[[1L]]
    pending <- pending[-1L]
    key <- paste(ref@id, ref@revision, sep = "\n")
    if (key %in% seen) {
      next
    }
    seen <- c(seen, key)
    if (length(seen) > max_artifacts) {
      handoff_abort(
        "The artifact dependency closure exceeds its artifact bound.",
        "handoff_bounds_error"
      )
    }
    artifact <- tryCatch(
      graft_read(store, ref),
      error = function(error) {
        handoff_abort(
          paste0(
            "An artifact dependency could not be verified: ",
            conditionMessage(error)
          ),
          "handoff_selection_error"
        )
      }
    )
    sizes <- c(sizes, length(artifact@bytes))
    for (dependency in artifact@dependencies) {
      dependency_key <- paste(
        dependency@id,
        dependency@revision,
        sep = "\n"
      )
      if (!(dependency_key %in% c(seen, pending_keys))) {
        pending <- c(pending, list(dependency))
        pending_keys <- c(pending_keys, dependency_key)
      }
    }
  }
  list(bytes = sum(sizes), count = length(seen))
}

handoff_validate_completion <- function(
  completion,
  max_bytes,
  max_total_bytes,
  max_metadata_bytes
) {
  completion <- handoff_plain_list(completion, "completion")
  fields <- c(
    "schema",
    "operation_id",
    "state",
    "producer",
    "errors",
    "outputs"
  )
  if (!identical(sort(names(completion)), sort(fields))) {
    handoff_abort("A completion packet has unsupported or missing fields.")
  }
  if (
    !rlang::is_string(completion$schema) ||
      !identical(completion$schema, handoff_schema)
  ) {
    handoff_abort(paste0("Completion schema must be `", handoff_schema, "`."))
  }
  operation_id <- handoff_text(completion$operation_id, "operation_id")
  if (
    !rlang::is_string(completion$state) ||
      !identical(completion$state, "complete")
  ) {
    handoff_abort(
      "Only completed output packets can be retained.",
      "handoff_state_error"
    )
  }
  producer <- handoff_named_object(completion$producer, "producer")
  if (!length(producer)) {
    handoff_abort("`producer` must contain at least one named field.")
  }
  handoff_json_value(
    producer,
    "producer",
    max_bytes = max_metadata_bytes
  )
  errors <- handoff_plain_list(completion$errors, "errors")
  if (length(errors) || !is.null(names(errors))) {
    handoff_abort(
      "A complete output packet must contain `errors = list()`. ",
      "handoff_state_error"
    )
  }
  outputs <- handoff_plain_list(completion$outputs, "outputs")
  if (is.null(names(outputs)) && length(outputs)) {
    names(outputs) <- rep.int("", length(outputs))
  }
  if (!length(outputs)) {
    handoff_abort("A complete output packet must contain output descriptors.")
  }
  if (length(outputs) > handoff_max_outputs) {
    handoff_abort(
      paste0(
        "A completion packet may contain at most ",
        handoff_max_outputs,
        " outputs."
      ),
      "handoff_bounds_error"
    )
  }
  declared_sizes <- vapply(
    seq_along(outputs),
    function(index) {
      output <- handoff_plain_list(
        outputs[[index]],
        paste0("outputs[", index, "]")
      )
      handoff_size(output$size, paste0("outputs[", index, "]$size"))
    },
    integer(1)
  )
  if (sum(as.numeric(declared_sizes)) > max_total_bytes) {
    handoff_abort(
      "Completed outputs exceed the total byte bound.",
      "handoff_bounds_error"
    )
  }
  validated <- lapply(outputs, handoff_descriptor, max_bytes = max_bytes)
  descriptors <- lapply(validated, `[[`, "descriptor")
  keys <- vapply(descriptors, `[[`, character(1), "key")
  if (anyDuplicated(keys)) {
    handoff_abort("Output descriptor keys must be unique.")
  }
  order <- order(keys, method = "radix")
  list(
    schema = handoff_schema,
    operation_id = operation_id,
    producer = producer,
    errors = list(),
    descriptors = unname(descriptors[order]),
    payloads = unname(validated[order]),
    keys = keys[order]
  )
}

handoff_selection_equal <- function(left, right) {
  if (
    !S7::S7_inherits(left, ArtifactSelection) ||
      !S7::S7_inherits(right, ArtifactSelection)
  ) {
    return(FALSE)
  }
  identical(
    list(
      left@id,
      lapply(left@roots, handoff_ref_record),
      lapply(left@artifacts, handoff_ref_record)
    ),
    list(
      right@id,
      lapply(right@roots, handoff_ref_record),
      lapply(right@artifacts, handoff_ref_record)
    )
  )
}

handoff_verified_selection <- function(store, inputs, max_metadata_bytes) {
  if (!S7::S7_inherits(inputs, ArtifactSelection)) {
    handoff_abort(
      "`inputs` must be an ArtifactSelection value.",
      "handoff_input_error"
    )
  }
  verified <- tryCatch(
    graft_read_selection(
      store,
      inputs@id,
      max_metadata_bytes = max_metadata_bytes
    ),
    error = function(error) {
      handoff_abort(
        paste0(
          "The host input selection could not be verified: ",
          conditionMessage(error)
        ),
        "handoff_selection_error"
      )
    }
  )
  if (!handoff_selection_equal(inputs, verified)) {
    handoff_abort(
      "The supplied host input selection does not match its retained selection.",
      "handoff_selection_error"
    )
  }
  verified
}

handoff_store_limit <- function(store) {
  if (!S7::S7_inherits(store, ArtifactStore)) {
    handoff_abort(
      "`store` must be a Graft artifact store handle.",
      "handoff_input_error"
    )
  }
  tryCatch(
    S7::validate(store),
    error = function(error) {
      handoff_abort(
        "`store` must be a valid Graft artifact store handle.",
        "handoff_input_error"
      )
    }
  )
  list(
    bytes = as.integer(store@max_bytes)
  )
}

handoff_check_gate <- function(eligible, stage) {
  if (!is.function(eligible)) {
    handoff_abort(
      "`eligible` must be a zero-argument callback.",
      "handoff_input_error"
    )
  }
  allowed <- tryCatch(
    eligible(),
    error = function(error) {
      handoff_abort(
        paste0("The host eligibility callback failed before ", stage, "."),
        "handoff_eligibility_error"
      )
    }
  )
  if (!is.logical(allowed) || length(allowed) != 1L || is.na(allowed)) {
    handoff_abort(
      paste0(
        "The host eligibility callback must return one logical value before ",
        stage,
        "."
      ),
      "handoff_eligibility_error"
    )
  }
  if (!isTRUE(allowed)) {
    handoff_abort(
      paste0("Host eligibility was withdrawn before ", stage, "."),
      "handoff_eligibility_error"
    )
  }
  invisible(TRUE)
}

handoff_placeholder_ref <- function(id) {
  list(id = id, revision = strrep("0", 64L))
}

handoff_save <- function(store, value, id, media_type, dependencies) {
  tryCatch(
    graft_save(
      store,
      value,
      id = id,
      media_type = media_type,
      dependencies = dependencies
    ),
    error = function(error) {
      handoff_abort(
        paste0(
          "Graft could not save the completed output handoff: ",
          conditionMessage(error)
        ),
        "handoff_store_error"
      )
    }
  )
}

handoff_output <- function(key, bytes, media_type) {
  key <- handoff_text(key, "key")
  media_type <- handoff_text(media_type, "media_type")
  if (is.raw(bytes)) {
    payload <- bytes
  } else if (rlang::is_string(bytes) && validUTF8(enc2utf8(bytes))) {
    payload <- charToRaw(enc2utf8(bytes))
  } else {
    handoff_abort(
      "`bytes` must be raw bytes or one nonmissing UTF-8 string.",
      "handoff_input_error"
    )
  }
  attributes(payload) <- NULL
  list(
    key = key,
    media_type = media_type,
    size = as.integer(length(payload)),
    sha256 = handoff_sha256(payload),
    encoding = "base64",
    data = handoff_base64(payload)
  )
}

retain_completed_output <- function(
  store,
  completion,
  inputs,
  id,
  eligible,
  required = handoff_default_required,
  max_bytes = handoff_default_max_bytes,
  max_total_bytes = handoff_default_max_total_bytes,
  max_metadata_bytes = handoff_default_max_metadata_bytes
) {
  store_limits <- handoff_store_limit(store)
  store_limit <- store_limits$bytes
  id <- handoff_text(id, "id")
  max_bytes <- handoff_limit(max_bytes, "max_bytes")
  max_total_bytes <- handoff_limit(max_total_bytes, "max_total_bytes")
  max_metadata_bytes <- handoff_limit(
    max_metadata_bytes,
    "max_metadata_bytes"
  )
  if (
    !is.character(required) ||
      anyNA(required) ||
      !all(nzchar(required)) ||
      anyDuplicated(required)
  ) {
    handoff_abort(
      "`required` must be a character vector of unique nonempty keys.",
      "handoff_input_error"
    )
  }
  if (length(required) && any(nchar(required, type = "bytes") > 1024L)) {
    handoff_abort(
      "`required` keys exceed the key bound.",
      "handoff_input_error"
    )
  }
  verified_inputs <- handoff_verified_selection(
    store,
    inputs,
    max_metadata_bytes
  )
  packet <- handoff_validate_completion(
    completion,
    max_bytes,
    max_total_bytes,
    max_metadata_bytes
  )
  if (length(required) && !all(required %in% packet$keys)) {
    missing <- required[!required %in% packet$keys]
    handoff_abort(
      paste0(
        "The completed output packet is missing required output(s): ",
        paste(missing, collapse = ", "),
        "."
      ),
      "handoff_schema_error"
    )
  }
  sizes <- vapply(packet$descriptors, `[[`, integer(1), "size")
  if (any(sizes > store_limit)) {
    handoff_abort(
      "A completed output exceeds the artifact store byte bound.",
      "handoff_bounds_error"
    )
  }

  retained_refs <- list()
  for (descriptor in packet$descriptors) {
    if (!identical(descriptor$encoding, "retained")) {
      next
    }
    ref <- handoff_ref_value(descriptor$ref, "output$ref")
    retained_refs <- c(retained_refs, list(ref))
    artifact <- tryCatch(
      graft_read(store, ref),
      error = function(error) {
        handoff_abort(
          paste0(
            "A retained output reference could not be verified: ",
            conditionMessage(error)
          ),
          "handoff_selection_error"
        )
      }
    )
    if (
      !identical(descriptor$media_type, artifact@media_type) ||
        !identical(descriptor$size, as.integer(length(artifact@bytes))) ||
        !identical(descriptor$sha256, handoff_sha256(artifact@bytes))
    ) {
      handoff_abort(
        paste0(
          "Retained output `",
          descriptor$key,
          "` does not match its exact artifact reference."
        ),
        "handoff_schema_error"
      )
    }
  }

  evidence_descriptors <- lapply(
    packet$descriptors,
    handoff_descriptor_metadata
  )
  evidence <- list(
    schema = packet$schema,
    operation_id = packet$operation_id,
    producer = packet$producer,
    errors = packet$errors,
    outputs = evidence_descriptors,
    input_selection_id = verified_inputs@id
  )
  evidence_bytes <- handoff_json_bytes(
    evidence,
    "evidence",
    min(max_metadata_bytes, store_limit)
  )
  handoff_check_metadata(
    evidence_bytes,
    max_metadata_bytes,
    store_limit,
    "Evidence"
  )

  evidence_id <- handoff_text(paste0(id, ":evidence"), "evidence id")
  root_id <- handoff_text(paste0(id, ":root"), "root id")
  output_ids <- vapply(
    packet$keys,
    \(key) handoff_text(paste0(id, ":output:", key), "output id"),
    character(1)
  )
  placeholder_evidence <- handoff_placeholder_ref(evidence_id)
  placeholder_outputs <- lapply(seq_along(packet$descriptors), function(index) {
    descriptor <- packet$descriptors[[index]]
    if (identical(descriptor$encoding, "retained")) {
      return(descriptor$ref)
    }
    handoff_placeholder_ref(output_ids[[index]])
  })
  root_preflight <- list(
    schema = packet$schema,
    operation_id = packet$operation_id,
    input_selection_id = verified_inputs@id,
    evidence = placeholder_evidence,
    outputs = handoff_root_outputs(
      packet$descriptors,
      placeholder_outputs,
      packet$keys
    )
  )
  root_preflight_bytes <- handoff_json_bytes(
    root_preflight,
    "root",
    min(max_metadata_bytes, store_limit)
  )
  handoff_check_metadata(
    root_preflight_bytes,
    max_metadata_bytes,
    store_limit,
    "Root"
  )
  closure <- handoff_closure_info(
    store,
    c(unname(verified_inputs@roots), retained_refs),
    handoff_max_artifacts
  )
  new_output_sizes <- vapply(
    packet$descriptors,
    function(descriptor) {
      if (identical(descriptor$encoding, "base64")) descriptor$size else 0L
    },
    integer(1)
  )
  projected_bytes <- closure$bytes +
    length(evidence_bytes) +
    sum(as.numeric(new_output_sizes)) +
    length(root_preflight_bytes)
  projected_count <- closure$count +
    2L +
    sum(vapply(
      packet$descriptors,
      function(x) {
        identical(x$encoding, "base64")
      },
      logical(1)
    ))
  if (
    projected_bytes > store_limit || projected_count > handoff_max_artifacts
  ) {
    handoff_abort(
      "The completed output closure exceeds the artifact store bound.",
      "handoff_bounds_error"
    )
  }
  handoff_check_gate(eligible, "writing evidence")
  evidence_ref <- handoff_save(
    store,
    evidence_bytes,
    id = evidence_id,
    media_type = "application/json",
    dependencies = verified_inputs@roots
  )

  output_refs <- vector("list", length(packet$descriptors))
  names(output_refs) <- packet$keys
  for (index in seq_along(packet$descriptors)) {
    descriptor <- packet$descriptors[[index]]
    handoff_check_gate(
      eligible,
      paste0("writing output `", descriptor$key, "`")
    )
    if (identical(descriptor$encoding, "base64")) {
      output_refs[[index]] <- handoff_save(
        store,
        packet$payloads[[index]]$bytes,
        id = output_ids[[index]],
        media_type = descriptor$media_type,
        dependencies = list(evidence_ref)
      )
      next
    }
    output_refs[[index]] <- handoff_ref_value(descriptor$ref, "output$ref")
  }

  root <- list(
    schema = packet$schema,
    operation_id = packet$operation_id,
    input_selection_id = verified_inputs@id,
    evidence = handoff_ref_record(evidence_ref),
    outputs = handoff_root_outputs(
      packet$descriptors,
      lapply(output_refs, handoff_ref_record),
      packet$keys
    )
  )
  root_bytes <- handoff_json_bytes(
    root,
    "root",
    min(max_metadata_bytes, store_limit)
  )
  handoff_check_metadata(root_bytes, max_metadata_bytes, store_limit, "Root")
  final_closure <- handoff_closure_info(
    store,
    c(unname(verified_inputs@roots), list(evidence_ref), unname(output_refs)),
    handoff_max_artifacts
  )
  if (
    final_closure$bytes + length(root_bytes) > store_limit ||
      final_closure$count + 1L > handoff_max_artifacts
  ) {
    handoff_abort(
      "The completed output closure exceeds the artifact store bound.",
      "handoff_bounds_error"
    )
  }
  handoff_check_gate(eligible, "publishing the completed root")
  root_dependencies <- c(
    list(evidence_ref),
    unname(output_refs)
  )
  root_ref <- handoff_save(
    store,
    root_bytes,
    id = root_id,
    media_type = "application/json",
    dependencies = root_dependencies
  )
  tryCatch(
    graft_select(
      store,
      root_ref,
      max_artifacts = handoff_max_artifacts,
      max_metadata_bytes = max_metadata_bytes
    ),
    error = function(error) {
      handoff_abort(
        paste0(
          "The completed output root could not be verified: ",
          conditionMessage(error)
        ),
        "handoff_selection_error"
      )
    }
  )
  list(
    root = root_ref,
    outputs = output_refs,
    evidence = evidence_ref
  )
}
