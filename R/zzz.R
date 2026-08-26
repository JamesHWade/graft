.onLoad <- function(...) {
  S7::methods_register()
}

S7::method(print, GraftSchema) <- function(x, ...) {
  cat(
    "<GraftSchema> ",
    x@name,
    " (",
    graft_schema_version_label(x),
    ")\n",
    sep = ""
  )
  cat("  classes: ", length(x@classes), "\n", sep = "")
  cat("  digest:  ", x@build_digest, "\n", sep = "")
  invisible(x)
}

S7::method(print, GraftStore) <- function(x, ...) {
  mode <- if (isTRUE(x@read_only)) "read-only" else "writable"
  status <- if (isTRUE(x@closed)) "closed" else "open"
  cat("<GraftStore> ", x@id, "\n", sep = "")
  cat(
    "  schema: ",
    x@schema@name,
    " (",
    graft_schema_version_label(x@schema),
    ")\n",
    sep = ""
  )
  cat("  path:   ", x@path, "\n", sep = "")
  cat("  mode:   ", mode, ", ", status, "\n", sep = "")
  invisible(x)
}

graft_schema_version_label <- function(schema) {
  version <- schema@version
  if (is.na(version)) "<unversioned>" else version
}

S7::method(print, GraftProvenance) <- function(x, ...) {
  cat("<GraftProvenance> ", x@producer, "\n", sep = "")
  cat(
    "  run:         ",
    scalar_character(x@run_id, "<none>"),
    "\n",
    sep = ""
  )
  cat(
    "  idempotency: ",
    scalar_character(x@idempotency_key, "<none>"),
    "\n",
    sep = ""
  )
  invisible(x)
}

S7::method(print, GraftCommitPlan) <- function(x, ...) {
  status <- if (isTRUE(x@valid)) "valid" else "invalid"
  cat("<GraftCommitPlan> ", status, " ", x@plan_id, "\n", sep = "")
  cat("  source:  ", x@source, "\n", sep = "")
  cat("  changes: ", nrow(x@changes), "\n", sep = "")
  cat("  issues:  ", nrow(x@issues), "\n", sep = "")
  cat("  digest:  ", x@plan_digest, "\n", sep = "")
  invisible(x)
}
