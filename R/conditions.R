graft_abort <- function(.subclass, message, ..., call = rlang::caller_env()) {
  rlang::abort(
    message = message,
    class = c(.subclass, "graft_error"),
    ...,
    call = call
  )
}

artifact_abort <- function(message, call = rlang::caller_env()) {
  graft_abort("graft_artifact_error", message, call = call)
}

graft_value_abort <- function(message, call = rlang::caller_env()) {
  graft_abort("graft_value_error", message, call = call)
}
