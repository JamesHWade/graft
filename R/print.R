#' @export
print.kg_schema <- function(x, ...) {
  info <- kg_schema_info(x)
  cat("<kg_schema> ", info$schema_name, sep = "")
  if (!is.na(info$schema_version)) {
    cat(" ", info$schema_version, sep = "")
  }
  cat("\n")
  cat("  classes:    ", info$class_count, "\n", sep = "")
  cat("  relations:  ", info$relation_count, "\n", sep = "")
  cat("  structural: ", info$structural_digest, "\n", sep = "")
  invisible(x)
}

#' @export
print.kg_schema_diff <- function(x, ...) {
  status <- if (isTRUE(x$compatible)) "compatible" else "incompatible"
  cat("<kg_schema_diff> ", status, "\n", sep = "")
  if (!isTRUE(x$compatible)) {
    cat("  old: ", x$old_structural_digest, "\n", sep = "")
    cat("  new: ", x$new_structural_digest, "\n", sep = "")
  }
  print_change_summary <- function(name, changes) {
    counts <- vapply(changes, length, integer(1))
    cat(
      "  ",
      name,
      ": +",
      counts[["added"]],
      " -",
      counts[["removed"]],
      " ~",
      counts[["changed"]],
      "\n",
      sep = ""
    )
  }
  print_change_summary("classes", x$classes)
  cat("  slots:   ", nrow(x$slots), " change(s)\n", sep = "")
  print_change_summary("enums", x$enums)
  print_change_summary("tables", x$tables)
  print_change_summary("relations", x$relations)
  invisible(x)
}
