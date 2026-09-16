# EXPERIMENT ONLY. Same host/content layer; only metadata history differs.
artifact_store <- function(root, backend, schema) {
  stopifnot(backend %in% c("manifest", "graft"))
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  store <- list(
    root = normalizePath(root),
    backend = backend,
    schema = schema,
    capacity = 50L
  )
  if (backend == "graft") {
    store$connection <- artifact_connection(store)
  }
  store
}

artifact_connection <- function(store) {
  graft::graft_open(
    graft::graft_schema(store$schema),
    file.path(store$root, "metadata.duckdb"),
    okf = "disabled"
  )
}

artifact_all_current <- function(store) {
  if (store$backend == "manifest") {
    path <- file.path(store$root, "current.json")
    refs <- if (file.exists(path)) artifact_read_json(path) else list()
    if (length(refs) > store$capacity) {
      artifact_error("Current index exceeds bound.")
    }
    return(refs)
  }
  conn <- store$connection
  rows <- graft::graft_find(
    conn,
    "artifact:",
    class = "artifact",
    limit = store$capacity
  )
  if (isTRUE(attr(rows, "truncated"))) {
    artifact_error("Current index exceeds bound.")
  }
  stats::setNames(
    lapply(seq_len(nrow(rows)), function(i) {
      list(id = rows$record[[i]]$id, revision = rows$record[[i]]$revision)
    }),
    rows$id
  )
}

artifact_current <- function(store, id) {
  artifact_all_current(store)[[id]]
}

artifact_publish <- function(store, metadata, ref) {
  if (store$backend == "manifest") {
    artifact_write(
      charToRaw(artifact_json(metadata)),
      artifact_digest_path(store$root, "manifests", ref$revision)
    )
    index <- artifact_all_current(store)
    index[[ref$id]] <- ref
    artifact_write(
      charToRaw(artifact_json(index)),
      file.path(store$root, "current.json"),
      replace = TRUE
    )
    return(invisible(ref))
  }
  conn <- store$connection
  row <- data.frame(
    id = ref$id,
    revision = ref$revision,
    payload = metadata$payload,
    media_type = metadata$media_type,
    manifest = artifact_json(metadata)
  )
  plan <- graft::graft_plan(
    conn,
    list(artifact = row),
    graft::graft_provenance(metadata$producer)
  )
  if (!plan@valid) {
    artifact_error("Graft rejected artifact metadata.")
  }
  graft::graft_commit(conn, plan)
  invisible(ref)
}

artifact_metadata <- function(store, ref) {
  artifact_digest_path(store$root, "manifests", ref$revision)
  if (store$backend == "manifest") {
    return(artifact_read_json(artifact_digest_path(
      store$root,
      "manifests",
      ref$revision
    )))
  }
  conn <- store$connection
  rows <- graft::graft_history(conn, ref$id, limit = 100L)
  # Do not silently substitute latest when history exceeds this prototype bound.
  match <- which(vapply(
    rows$record,
    function(row) identical(row$revision, ref$revision),
    logical(1)
  ))
  if (!length(match)) {
    artifact_error("Exact revision absent from bounded history.")
  }
  jsonlite::fromJSON(
    rows$record[[match[[1L]]]]$manifest,
    simplifyVector = FALSE
  )
}

artifact_close <- function(store) {
  if (store$backend == "graft") {
    graft::graft_close(store$connection)
  }
  invisible(NULL)
}
