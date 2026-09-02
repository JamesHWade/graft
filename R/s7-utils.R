graft_plan_version <- "0.2.0"

graft_sha256 <- function(x, serialize = FALSE) {
  paste0(
    "sha256:",
    digest::digest(x, algo = "sha256", serialize = serialize)
  )
}

is_graft_digest <- function(x) {
  is.character(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    grepl("^sha256:[0-9a-f]{64}$", x)
}

graft_optional_string <- function(x, field) {
  if (is.null(x)) {
    return(NA_character_)
  }
  if (
    is.character(x) &&
      length(x) == 1L &&
      !is.na(x) &&
      nzchar(trimws(x))
  ) {
    return(trimws(x))
  }
  abort_validation_error(
    paste0("`", field, "` must be one non-empty string or `NULL`."),
    field = field,
    rule = "optional_scalar_character",
    observed_value = x
  )
}

abort_commit_plan <- function(
  subclass,
  message,
  ...,
  call = rlang::caller_env()
) {
  graft_abort(
    c(subclass, "graft_commit_plan_error"),
    message,
    ...,
    call = call
  )
}
