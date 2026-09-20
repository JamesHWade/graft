# This file is intentionally self-contained so the example can be copied out
# of the package and adapted to a host application.

project_memory_stream <- function() {
  "metric:active-customer"
}

project_memory_purpose <- function() {
  "project-assistance"
}

project_memory_actor <- function() {
  "project-memory-demo-reviewer"
}

project_memory_note_id <- function() {
  "metric:active-customer"
}

project_memory_source_id <- function() {
  "metrics.md"
}

project_memory_text <- function(value, name) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(value)
  ) {
    stop(sprintf("`%s` must be one non-missing character value.", name))
  }
  enc2utf8(value)
}

project_memory_decision_id <- function(value, name = "expected") {
  if (is.null(value)) {
    return(NULL)
  }
  if (is.character(value)) {
    return(project_memory_text(value, name))
  }
  if (S7::S7_inherits(value)) {
    id <- S7::prop(value, "id")
    return(project_memory_text(id, paste0(name, "@id")))
  }
  stop(sprintf("`%s` must be NULL, a decision, or a decision id.", name))
}

project_memory_ref_id <- function(ref, name = "ref") {
  if (!S7::S7_inherits(ref)) {
    stop(sprintf("`%s` must be an artifact reference.", name))
  }
  project_memory_text(S7::prop(ref, "id"), paste0(name, "@id"))
}

project_memory_ref_label <- function(ref) {
  paste(
    S7::prop(ref, "id"),
    S7::prop(ref, "revision"),
    sep = " @ "
  )
}

project_memory_review_key <- function(note_ref, expected) {
  predecessor <- project_memory_decision_id(expected)
  if (is.null(predecessor)) {
    predecessor <- "none"
  }
  key <- paste0(
    "accept:",
    project_memory_ref_id(note_ref, "note_ref"),
    "@",
    S7::prop(note_ref, "revision"),
    ":expected:",
    predecessor
  )
  if (nchar(enc2utf8(key), type = "bytes") >= 1024L) {
    stop("The project-memory review key exceeds Graft's key bound.")
  }
  key
}

project_memory_withdraw_key <- function(expected) {
  predecessor <- project_memory_decision_id(expected)
  if (is.null(predecessor)) {
    stop("The project-memory withdrawal requires a current decision.")
  }
  key <- paste0("withdraw:", predecessor)
  if (nchar(enc2utf8(key), type = "bytes") >= 1024L) {
    stop("The project-memory withdrawal key exceeds Graft's key bound.")
  }
  key
}

# Open the local project-memory artifact store.
#
# A missing or empty directory is initialized. Existing stores are reopened
# without changing their retained contents.
#
# @param path Absolute or relative path for the local Graft store.
# @returns A Graft artifact-store handle.
open_project_memory <- function(path) {
  if (
    !is.character(path) ||
      length(path) != 1L ||
      is.na(path) ||
      !nzchar(path)
  ) {
    stop("`path` must be one non-empty path.")
  }
  create <- !dir.exists(path) ||
    !length(list.files(path, all.files = TRUE, no.. = TRUE))
  graft::graft_store(path, create = create)
}

project_memory_recall <- function(store) {
  graft::graft_recall(
    store,
    stream = project_memory_stream(),
    purpose = project_memory_purpose(),
    eligible = TRUE
  )
}

project_memory_find_artifact <- function(artifacts, ref) {
  matches <- vapply(
    artifacts,
    function(artifact) {
      identical(
        project_memory_ref_id(artifact@ref),
        project_memory_ref_id(ref)
      ) &&
        identical(
          S7::prop(artifact@ref, "revision"),
          S7::prop(ref, "revision")
        )
    },
    logical(1)
  )
  if (!any(matches)) {
    return(NULL)
  }
  artifacts[[which(matches)[[1L]]]]
}

project_memory_result <- function(recall) {
  decision <- recall@decision
  selection <- recall@selection
  result <- list(
    status = recall@status,
    stream = project_memory_stream(),
    purpose = project_memory_purpose(),
    decision_id = if (is.null(decision)) NULL else decision@id,
    decision = decision,
    selection_id = if (is.null(selection)) NULL else selection@id,
    selection = selection,
    note = NULL,
    source = NULL,
    note_ref = NULL,
    source_ref = NULL
  )
  if (!identical(recall@status, "accepted")) {
    return(result)
  }

  roots <- recall@roots
  if (
    length(roots) != 1L ||
      !identical(
        project_memory_ref_id(roots[[1L]]@ref),
        project_memory_note_id()
      )
  ) {
    stop("The current project-memory selection has an invalid note root.")
  }
  note <- roots[[1L]]
  dependencies <- note@dependencies
  if (
    length(dependencies) != 1L ||
      !identical(
        project_memory_ref_id(dependencies[[1L]]),
        project_memory_source_id()
      )
  ) {
    stop("The current project-memory note has an invalid source dependency.")
  }
  source_ref <- dependencies[[1L]]
  source <- project_memory_find_artifact(recall@artifacts, source_ref)
  if (is.null(source)) {
    stop("The current project-memory source dependency is not retained.")
  }
  if (
    !identical(project_memory_ref_id(source@ref), project_memory_source_id())
  ) {
    stop("The current project-memory source identity is invalid.")
  }
  if (
    !is.character(note@data) ||
      length(note@data) != 1L ||
      is.na(note@data) ||
      !is.character(source@data) ||
      length(source@data) != 1L ||
      is.na(source@data)
  ) {
    stop("The current project-memory content is not valid text.")
  }
  result$note <- note@data
  result$source <- source@data
  result$note_ref <- note@ref
  result$source_ref <- source@ref
  result
}

# Save and accept one reviewed project-memory note.
#
# The source excerpt is retained as a dependency of the note. The explicit
# predecessor and deterministic request key make corrections and retries
# visible in the decision stream.
#
# @param store A Graft artifact-store handle.
# @param note Reviewed project-memory text.
# @param source Exact source excerpt supporting `note`.
# @param expected Expected current decision, decision id, or `NULL` for an
#   empty stream.
# @returns A concise proof of the accepted note and its retained source.
save_project_memory <- function(store, note, source, expected = NULL) {
  note <- project_memory_text(note, "note")
  source <- project_memory_text(source, "source")
  source_ref <- graft::graft_save(
    store,
    source,
    id = project_memory_source_id(),
    media_type = "text/markdown"
  )
  note_ref <- graft::graft_save(
    store,
    note,
    id = project_memory_note_id(),
    media_type = "text/plain",
    dependencies = source_ref
  )
  key <- project_memory_review_key(note_ref, expected)
  decision <- graft::graft_accept(
    store,
    x = note_ref,
    stream = project_memory_stream(),
    expected = expected,
    key = key,
    actor = project_memory_actor(),
    reason = "A trusted local reviewer accepted this project note.",
    purpose = project_memory_purpose()
  )
  current <- project_memory_recall(store)
  if (!identical(current@decision@id, decision@id)) {
    stop(
      "The review request was already committed, but it is no longer current."
    )
  }
  project_memory_result(current)
}

# Read the current reviewed project-memory note and exact source.
#
# The read checks current consultation eligibility and resolves only the
# verified note root and its exact source dependency.
#
# @param store A Graft artifact-store handle.
# @returns A structured `missing`, `withdrawn`, or `accepted` result.
read_project_memory <- function(store) {
  project_memory_result(project_memory_recall(store))
}

# Withdraw the current reviewed project-memory note.
#
# @param store A Graft artifact-store handle.
# @param expected Expected current acceptance decision or decision id.
# @returns A structured `withdrawn` result.
withdraw_project_memory <- function(store, expected) {
  current <- project_memory_recall(store)
  if (
    !identical(current@status, "accepted") ||
      is.null(current@decision)
  ) {
    stop("There is no current accepted project-memory note to withdraw.")
  }
  decision <- graft::graft_withdraw(
    store,
    stream = project_memory_stream(),
    expected = expected,
    key = project_memory_withdraw_key(expected),
    actor = project_memory_actor(),
    reason = "The reviewer stopped using this project note."
  )
  result <- project_memory_result(project_memory_recall(store))
  if (!identical(result$decision_id, decision@id)) {
    stop("The withdrawal was committed, but it is no longer current.")
  }
  result
}

# Build the fixed, read-only ellmer tool used by the live preview.
project_memory_tool <- function(store, eligible = function() TRUE) {
  graft::graft_tool(
    store,
    stream = project_memory_stream(),
    purpose = project_memory_purpose(),
    eligible = eligible
  )
}
