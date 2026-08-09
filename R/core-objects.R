new_compiled_schema <- function(manifest, path = NULL) {
  list(
    manifest = manifest,
    path = path
  )
}

is_compiled_schema <- function(x) {
  is.list(x) &&
    !is.object(x) &&
    identical(names(x), c("manifest", "path")) &&
    is.list(x$manifest) &&
    (is.null(x$path) || is_nonempty_string(x$path))
}

new_store_backend <- function(
  schema,
  connection,
  owns_connection,
  read_only,
  path,
  capabilities,
  okf_mode,
  okf_path
) {
  store <- new.env(parent = emptyenv())
  store$schema <- schema
  store$connection <- connection
  store$owns_connection <- owns_connection
  store$read_only <- read_only
  store$path <- path
  store$closed <- FALSE
  store$capabilities <- capabilities
  store$okf_mode <- okf_mode
  store$okf_path <- okf_path
  store$okf_expected <- NULL
  store$verification <- NULL
  store
}

is_store_backend <- function(x) {
  is.environment(x) &&
    !is.object(x) &&
    all(
      c(
        "schema",
        "connection",
        "owns_connection",
        "read_only",
        "path",
        "closed",
        "capabilities",
        "okf_mode",
        "okf_path",
        "okf_expected",
        "verification"
      ) %in%
        ls(x, all.names = TRUE)
    )
}

validate_store_backend <- function(
  store,
  require_open = TRUE,
  arg = rlang::caller_arg(store)
) {
  if (!is_store_backend(store)) {
    abort_backend_error(
      paste0("`", arg, "` has invalid internal store state."),
      operation = "validate_store",
      argument = arg
    )
  }
  if (
    !isTRUE(store$closed) &&
      !isTRUE(tryCatch(
        DBI::dbIsValid(store$connection),
        error = \(.x) FALSE
      ))
  ) {
    store$closed <- TRUE
  }
  if (isTRUE(require_open) && isTRUE(store$closed)) {
    abort_backend_error(
      "The GraftStore is closed.",
      operation = "validate_store",
      store_path = store$path
    )
  }
  invisible(store)
}

scalar_character <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0L) {
    return(default)
  }
  as.character(x[[1L]])
}

scalar_logical <- function(x, default = FALSE) {
  if (is.null(x) || length(x) == 0L) {
    return(default)
  }
  isTRUE(x[[1L]])
}

empty_character <- function(x) {
  if (is.null(x)) {
    return(character())
  }
  as.character(unlist(x, use.names = FALSE))
}
