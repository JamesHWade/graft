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

#' @export
print.kg_store <- function(x, ...) {
  info <- kg_store_info(x)
  status <- if (isTRUE(info$closed)) {
    "closed"
  } else if (isTRUE(info$initialized)) {
    "initialized"
  } else {
    "uninitialized"
  }
  mode <- if (isTRUE(info$read_only)) "read-only" else "read-write"
  cat("<kg_store> DuckDB ", status, " (", mode, ")\n", sep = "")
  cat("  path:       ", info$path, "\n", sep = "")
  cat("  structural: ", info$structural_digest, "\n", sep = "")
  invisible(x)
}

#' @export
print.kg_batch <- function(x, ...) {
  cat("<kg_batch> ", x$batch_id, "\n", sep = "")
  cat("  producer:    ", x$producer, "\n", sep = "")
  cat(
    "  source run:  ",
    scalar_character(x$source_run_id, "<none>"),
    "\n",
    sep = ""
  )
  cat(
    "  idempotency: ",
    scalar_character(x$idempotency_key, "<none>"),
    "\n",
    sep = ""
  )
  invisible(x)
}

#' @export
print.kg_ingest_result <- function(x, ...) {
  status <- if (isTRUE(x$replay)) "replay" else "committed"
  cat("<kg_ingest_result> ", status, " ", x$batch_id, "\n", sep = "")
  cat("  inserted: ", sum(x$inserted), "\n", sep = "")
  cat("  updated:  ", sum(x$updated), "\n", sep = "")
  cat("  matched:  ", sum(x$matched), "\n", sep = "")
  cat("  observed: ", sum(x$observed), "\n", sep = "")
  invisible(x)
}

#' @export
print.kg_validation_report <- function(x, ...) {
  status <- if (isTRUE(x$valid)) "valid" else "invalid"
  cat("<kg_validation_report> ", status, "\n", sep = "")
  cat("  failures: ", nrow(x$failures), "\n", sep = "")
  if (!isTRUE(x$valid)) {
    summary <- table(x$failures$condition_class)
    for (name in names(summary)) {
      cat("  ", name, ": ", unname(summary[[name]]), "\n", sep = "")
    }
  }
  invisible(x)
}

#' @export
print.kg_record <- function(x, ...) {
  cat("<kg_record> ", x$class, " ", x$id, "\n", sep = "")
  related <- intersect(
    c("identifiers", "claims", "evidence"),
    names(x)
  )
  for (name in related) {
    value <- x[[name]]
    count <- if (is.data.frame(value)) nrow(value) else length(value)
    cat("  ", name, ": ", count, "\n", sep = "")
  }
  invisible(x)
}

#' @export
print.kg_context <- function(x, ...) {
  cat(x$text, "\n", sep = "")
  invisible(x)
}
