new_kg_schema <- function(manifest, path = NULL) {
  structure(
    list(
      manifest = manifest,
      path = path
    ),
    class = "kg_schema"
  )
}

new_kg_schema_diff <- function(
  old_structural_digest,
  new_structural_digest,
  classes,
  slots,
  enums,
  tables,
  relations
) {
  structure(
    list(
      compatible = identical(old_structural_digest, new_structural_digest),
      old_structural_digest = old_structural_digest,
      new_structural_digest = new_structural_digest,
      classes = classes,
      slots = slots,
      enums = enums,
      tables = tables,
      relations = relations
    ),
    class = "kg_schema_diff"
  )
}

new_kg_store <- function(
  schema,
  connection,
  owns_connection,
  read_only,
  path,
  capabilities
) {
  store <- new.env(parent = emptyenv())
  store$schema <- schema
  store$connection <- connection
  store$owns_connection <- owns_connection
  store$read_only <- read_only
  store$path <- path
  store$closed <- FALSE
  store$capabilities <- capabilities
  class(store) <- "kg_store"
  store
}

is_kg_schema <- function(x) {
  inherits(x, "kg_schema")
}

as_kg_schema <- function(x, arg = rlang::caller_arg(x)) {
  if (is_kg_schema(x)) {
    return(x)
  }
  if (is.character(x) && length(x) == 1L && !is.na(x)) {
    return(kg_schema(x))
  }
  abort_schema_error(
    paste0("`", arg, "` must be a kg_schema object or a manifest path."),
    argument = arg
  )
}

is_kg_store <- function(x) {
  inherits(x, "kg_store") && is.environment(x)
}

validate_kg_store <- function(
  store,
  require_open = TRUE,
  arg = rlang::caller_arg(store)
) {
  if (!is_kg_store(store)) {
    abort_backend_error(
      paste0("`", arg, "` must be a kg_store object."),
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
      "The kg_store is closed.",
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
