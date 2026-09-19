graft_abort <- function(.subclass, message, ..., call = rlang::caller_env()) {
  rlang::abort(
    message = message,
    class = c(.subclass, "graft_error"),
    ...,
    call = call
  )
}
