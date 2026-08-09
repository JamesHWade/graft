.onLoad <- function(...) {
  S7::methods_register()
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
