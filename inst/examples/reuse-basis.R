# Application-owned teaching recipe, not a Graft serialization or access API.
# Checkpoints are trusted host data. The host declares the evidence closure.
reuse_ids <- function(ids) {
  if (
    !is.character(ids) ||
      !is.null(dim(ids)) ||
      anyNA(ids) ||
      !all(nzchar(ids)) ||
      anyDuplicated(ids) ||
      length(ids) > 1000L
  ) {
    stop("Select at most 1,000 unique, non-empty record IDs.", call. = FALSE)
  }
  ids
}

reuse_closure <- function(roots, dependencies) {
  reuse_ids(roots)
  if (
    !is.data.frame(dependencies) ||
      !identical(names(dependencies), c("outcome", "dependency")) ||
      !is.character(dependencies$outcome) ||
      !is.character(dependencies$dependency) ||
      anyNA(dependencies) ||
      !all(nzchar(dependencies$outcome)) ||
      !all(nzchar(dependencies$dependency)) ||
      anyDuplicated(dependencies)
  ) {
    stop("Declare unique outcome/dependency ID pairs.", call. = FALSE)
  }
  selected <- character()
  visit <- function(id, ancestors = character()) {
    if (id %in% ancestors) {
      stop("Dependency cycles require review.", call. = FALSE)
    }
    if (id %in% selected) {
      return(invisible(NULL))
    }
    for (dependency in dependencies$dependency[dependencies$outcome == id]) {
      visit(dependency, c(ancestors, id))
    }
    selected <<- c(selected, id)
    reuse_ids(selected)
    invisible(NULL)
  }
  for (id in roots) {
    visit(id)
  }
  sort(selected, method = "radix")
}

capture_reuse_basis <- function(store, roots, dependencies) {
  ids <- reuse_closure(roots, dependencies)
  snapshot <- graft::graft_snapshot(store)
  view <- graft::graft_at(store, snapshot)
  records <- data.frame(
    record_id = ids,
    class = character(length(ids)),
    revision_id = character(length(ids))
  )
  for (i in seq_along(ids)) {
    # A historical deletion is not a current accepted record.
    value <- graft::graft_get(view, ids[[i]], include = character())
    history <- graft::graft_history(view, ids[[i]], limit = 1L)
    stopifnot(nrow(history) == 1L)
    records$class[[i]] <- value$class
    records$revision_id[[i]] <- history$revision_id[[1L]]
  }
  list(
    version = 1L,
    snapshot = snapshot,
    roots = roots,
    records = records,
    dependencies = dependencies[dependencies$outcome %in% ids, , drop = FALSE]
  )
}

read_reuse_basis <- function(store, basis, allow_read) {
  if (
    !identical(basis$version, 1L) ||
      !is.data.frame(basis$records) ||
      !identical(names(basis$records), c("record_id", "class", "revision_id"))
  ) {
    stop("Unsupported reuse checkpoint.", call. = FALSE)
  }
  ids <- reuse_ids(basis$records$record_id)
  expected <- reuse_closure(basis$roots, basis$dependencies)
  if (!identical(ids, expected)) {
    stop(
      "The checkpoint does not contain its complete declared closure.",
      call. = FALSE
    )
  }
  # This callback is supplied by the host, never restored from the checkpoint.
  if (!isTRUE(allow_read(ids))) {
    stop("Reuse is not authorized.", call. = FALSE)
  }
  view <- graft::graft_at(store, basis$snapshot)
  values <- lapply(seq_along(ids), function(i) {
    value <- graft::graft_get(view, ids[[i]], include = character())
    history <- graft::graft_history(view, ids[[i]], limit = 1L)
    if (
      nrow(history) != 1L ||
        !identical(history$revision_id[[1L]], basis$records$revision_id[[i]]) ||
        !identical(value$class, basis$records$class[[i]])
    ) {
      stop("An exact selected revision is unavailable.", call. = FALSE)
    }
    value$record
  })
  if (!isTRUE(allow_read(ids))) {
    stop("Reuse is not authorized.", call. = FALSE)
  }
  stats::setNames(values, ids)
}

review_reuse_basis <- function(store, basis) {
  # This is host inspection. Authorize access before calling it.
  changes <- graft::graft_changes(
    store,
    since = basis$snapshot,
    record_ids = basis$records$record_id,
    limit = 1000L
  )
  if (isTRUE(attr(changes, "truncated"))) {
    stop("The change assessment is incomplete.", call. = FALSE)
  }
  affected <- changes$record_id
  repeat {
    expanded <- union(
      affected,
      basis$dependencies$outcome[
        basis$dependencies$dependency %in% affected
      ]
    )
    if (setequal(expanded, affected)) {
      break
    }
    affected <- expanded
  }
  list(changes = changes, needs_review = intersect(basis$roots, affected))
}

# A deliberately narrow consultation surface: the model cannot choose IDs,
# query the store, request history, or bypass the host's current policy.
reuse_consultation_tool <- function(store, basis, allow_read, eligible) {
  ellmer::tool(
    function() {
      authorized <- function(ids) {
        isTRUE(allow_read(ids)) && isTRUE(eligible(basis))
      }
      value <- read_reuse_basis(store, basis, authorized)
      jsonlite::toJSON(value, auto_unbox = TRUE, null = "null")
    },
    name = "consult_selected_knowledge",
    description = "Read the complete host-selected knowledge for this task.",
    arguments = list(),
    annotations = list(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
}
