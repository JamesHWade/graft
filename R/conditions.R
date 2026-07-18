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
