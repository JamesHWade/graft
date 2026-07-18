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
