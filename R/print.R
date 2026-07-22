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
  cat(
    "<kg_schema_diff> ",
    x$classification,
    "\n",
    sep = ""
  )
  structural <- if (isTRUE(x$compatible)) "unchanged" else "changed"
  cat("  structural: ", structural, "\n", sep = "")
  if (!isTRUE(x$compatible)) {
    cat("  old: ", x$old_structural_digest, "\n", sep = "")
    cat("  new: ", x$new_structural_digest, "\n", sep = "")
  }
  print_change_summary <- function(name, changes) {
    counts <- lengths(changes)
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
print.kg_migration_plan <- function(x, ...) {
  cat(
    "<kg_migration_plan> ",
    x$classification,
    " ",
    x$migration_id,
    "\n",
    sep = ""
  )
  cat("  from:       ", x$from_build_digest, "\n", sep = "")
  cat("  to:         ", x$to_build_digest, "\n", sep = "")
  cat("  changes:    ", nrow(x$changes), "\n", sep = "")
  rules <- sort(unique(x$changes$rule), method = "radix")
  if (length(rules) > 0L) {
    cat("  rules:      ", paste(rules, collapse = ", "), "\n", sep = "")
  }
  cat("  operations: ", length(x$operations), "\n", sep = "")
  cat("  digest:     ", x$plan_digest, "\n", sep = "")
  invisible(x)
}

#' @export
print.kg_store_check <- function(x, ...) {
  status <- if (isTRUE(x$valid)) "valid" else "invalid"
  mode <- if (isTRUE(x$deep)) "deep" else "shallow"
  cat("<kg_store_check> ", status, " (", mode, ")\n", sep = "")
  cat("  issues:    ", x$reported_issues, "\n", sep = "")
  cat("  truncated: ", x$truncated, "\n", sep = "")
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

#' @export
print.kg_subgraph <- function(x, ...) {
  cat("<kg_subgraph> ", x$request$kind, "\n", sep = "")
  cat("  nodes:      ", nrow(x$nodes), "\n", sep = "")
  cat("  edges:      ", nrow(x$edges), "\n", sep = "")
  cat("  projection: ", x$projection, "\n", sep = "")
  cat("  truncated:  ", x$truncated, "\n", sep = "")
  invisible(x)
}
