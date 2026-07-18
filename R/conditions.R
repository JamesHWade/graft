graft_abort <- function(.subclass, message, ..., call = rlang::caller_env()) {
  rlang::abort(
    message = message,
    class = c(.subclass, "graft_error"),
    ...,
    call = call
  )
}

abort_schema_error <- function(message, ..., call = rlang::caller_env()) {
  graft_abort("graft_schema_error", message, ..., call = call)
}

abort_schema_mismatch <- function(diff, call = rlang::caller_env()) {
  graft_abort(
    "graft_schema_mismatch",
    paste0(
      "The schema structural digests differ: ",
      diff$old_structural_digest,
      " != ",
      diff$new_structural_digest,
      "."
    ),
    schema_diff = diff,
    call = call
  )
}

abort_backend_error <- function(
  message,
  ...,
  operation = NULL,
  parent = NULL,
  call = rlang::caller_env()
) {
  graft_abort(
    "graft_backend_error",
    message,
    ...,
    backend = "duckdb",
    operation = operation,
    parent = parent,
    call = call
  )
}

abort_record_condition <- function(
  subclass,
  message,
  ...,
  record_class = NULL,
  input_row = NULL,
  record_id = NULL,
  field = NULL,
  rule = NULL,
  observed_value = NULL,
  call = rlang::caller_env()
) {
  details <- list(
    class = record_class,
    input_row = input_row,
    record_id = record_id,
    field = field,
    rule = rule,
    observed_value = observed_value
  )
  graft_abort(
    subclass,
    message,
    ...,
    record_class = record_class,
    input_row = input_row,
    record_id = record_id,
    field = field,
    rule = rule,
    observed_value = observed_value,
    details = details,
    call = call
  )
}

abort_validation_error <- function(
  message,
  ...,
  record_class = NULL,
  input_row = NULL,
  record_id = NULL,
  field = NULL,
  rule = NULL,
  observed_value = NULL,
  call = rlang::caller_env()
) {
  abort_record_condition(
    "graft_validation_error",
    message,
    ...,
    record_class = record_class,
    input_row = input_row,
    record_id = record_id,
    field = field,
    rule = rule,
    observed_value = observed_value,
    call = call
  )
}

abort_identity_error <- function(
  message,
  ...,
  record_class = NULL,
  input_row = NULL,
  record_id = NULL,
  field = NULL,
  rule = NULL,
  observed_value = NULL,
  call = rlang::caller_env()
) {
  abort_record_condition(
    "graft_identity_error",
    message,
    ...,
    record_class = record_class,
    input_row = input_row,
    record_id = record_id,
    field = field,
    rule = rule,
    observed_value = observed_value,
    call = call
  )
}

abort_reference_error <- function(
  message,
  ...,
  record_class = NULL,
  input_row = NULL,
  record_id = NULL,
  field = NULL,
  rule = NULL,
  observed_value = NULL,
  call = rlang::caller_env()
) {
  abort_record_condition(
    "graft_reference_error",
    message,
    ...,
    record_class = record_class,
    input_row = input_row,
    record_id = record_id,
    field = field,
    rule = rule,
    observed_value = observed_value,
    call = call
  )
}

signal_batch_replay <- function(result, call = rlang::caller_env()) {
  rlang::cnd_signal(rlang::cnd(
    class = c("graft_batch_replay", "graft_condition"),
    message = paste0(
      "Batch replay returned the committed result for `",
      result$batch_id,
      "`."
    ),
    batch_id = result$batch_id,
    result = result,
    call = call
  ))
  invisible(result)
}
