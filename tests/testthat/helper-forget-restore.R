# Synthetic protocol model only: one writer, closed stores, trusted local files.
# These helpers are not a production purge, backup, or authorization API.
forget_error <- function(class = "forget_unavailable") {
  stop(structure(
    list(message = "Knowledge generation is unavailable.", call = NULL),
    class = c(class, "error", "condition")
  ))
}

forget_journal_read <- function(journal) {
  files <- sort(list.files(
    journal,
    pattern = "^event-[0-9]+[.]rds$",
    full.names = TRUE
  ))
  if (length(files) == 0L) {
    forget_error()
  }
  readRDS(tail(files, 1L))
}

forget_journal_write <- function(journal, state) {
  files <- list.files(journal, pattern = "^event-[0-9]+[.]rds$")
  destination <- file.path(
    journal,
    sprintf("event-%06d.rds", length(files) + 1L)
  )
  temporary <- tempfile("pending-", tmpdir = journal)
  on.exit(unlink(temporary))
  saveRDS(state, temporary)
  if (!file.rename(temporary, destination)) {
    forget_error()
  }
  invisible(state)
}

forget_fingerprint <- function(path) {
  if (!file.exists(path)) {
    forget_error()
  }
  digest::digest(file = path, algo = "sha256")
}

forget_open <- function(path, read) {
  store <- graft_open(
    graft_schema(system.file(
      "extdata/narrative-knowledge.data-dict.json",
      package = "graft"
    )),
    path,
    read_only = TRUE,
    okf = "disabled"
  )
  on.exit(graft_close(store))
  read(store)
}

forget_manifest <- function(path, reader, epoch) {
  list(
    format = 1L,
    reader = reader,
    epoch = epoch,
    snapshot = forget_open(path, \(store) S7::props(graft_snapshot(store))),
    checksum = forget_fingerprint(path)
  )
}

# The host journal admits only the exact certified image; changing an epoch in
# a backup sidecar cannot turn an old database into a sanitized generation.
forget_read <- function(journal, path, manifest, read) {
  state <- forget_journal_read(journal)
  if (
    !identical(state$status, "active") ||
      !identical(manifest, state$manifest) ||
      !identical(manifest$format, 1L) ||
      !identical(forget_fingerprint(path), manifest$checksum)
  ) {
    forget_error()
  }
  value <- forget_open(path, function(store) {
    if (!identical(S7::props(graft_snapshot(store)), manifest$snapshot)) {
      forget_error()
    }
    read(store)
  })
  if (!identical(forget_journal_read(journal), state)) {
    forget_error()
  }
  value
}

# This schema-specific dependency closure belongs to the synthetic host.
# Incoming private derivatives are removed; an outward source survives while
# another retained artifact references it. Forgetting the source cascades inward.
forget_selection <- function(records, roots) {
  all_ids <- unlist(lapply(records, `[[`, "id"), use.names = FALSE)
  if (!length(roots) || !all(roots %in% all_ids)) {
    forget_error()
  }
  selected <- roots
  repeat {
    before <- selected
    links <- records$support
    source_dependents <- links$knowledge_id[links$source_id %in% selected]
    selected <- union(selected, source_dependents)
    selected <- union(
      selected,
      links$id[
        links$knowledge_id %in% selected | links$source_id %in% selected
      ]
    )
    used_before <- unique(links$source_id[links$id %in% selected])
    used_after <- unique(links$source_id[!links$id %in% selected])
    selected <- union(selected, setdiff(used_before, used_after))
    if (identical(before, selected)) break
  }
  sort(selected)
}

forget_preview <- function(journal, records, roots, request) {
  state <- forget_journal_read(journal)
  if (!identical(state$status, "active")) {
    forget_error()
  }
  list(
    action = "forget",
    request = request,
    reader = state$manifest$reader,
    prior = state$manifest,
    ids = forget_selection(records, roots)
  )
}

forget_accept <- function(journal, preview, authorize) {
  state <- forget_journal_read(journal)
  if (identical(state$request, preview$request)) {
    if (!identical(state$preview, preview)) {
      forget_error()
    }
    return(invisible(state))
  }
  if (
    !identical(preview$action, "forget") ||
      !identical(state$status, "active") ||
      !identical(preview$prior, state$manifest) ||
      !isTRUE(authorize(preview))
  ) {
    forget_error("forget_not_authorized")
  }
  state$status <- "blocked"
  state$request <- preview$request
  state$preview <- preview
  state$epoch <- state$manifest$epoch + 1L
  state$manifest <- NULL
  forget_journal_write(journal, state)
}

# Fault hooks model process interruption between durable protocol steps.
forget_finish <- function(
  journal,
  candidate,
  purge_paths,
  certify,
  interrupt = identity
) {
  state <- forget_journal_read(journal)
  if (identical(state$status, "active")) {
    return(invisible(state))
  }
  manifest <- forget_manifest(candidate, state$preview$reader, state$epoch)
  if (
    identical(manifest$snapshot$store_id, state$preview$prior$snapshot$store_id)
  ) {
    forget_error()
  }
  if (!isTRUE(certify(candidate, state$preview))) {
    forget_error()
  }
  backup <- paste0(candidate, ".backup")
  if (!file.exists(backup) && !file.copy(candidate, backup)) {
    forget_error()
  }
  if (!identical(forget_fingerprint(backup), manifest$checksum)) {
    forget_error()
  }
  interrupt("candidate_validated")
  for (path in purge_paths) {
    unlink(path, recursive = TRUE)
    if (file.exists(path)) {
      forget_error()
    }
    interrupt("copy_removed")
  }
  state$manifest <- manifest
  state$status <- "active"
  state$completion <- "local copies removed; offline backup retained and denied"
  forget_journal_write(journal, state)
  interrupt("published")
  invisible(state)
}

forget_fixture <- function(.local_envir = parent.frame()) {
  directory <- withr::local_tempdir(.local_envir = .local_envir)
  records <- narrative_fixture()$narrative_records()
  records$knowledge$body[2L] <- "PRIVATE-FORGET-ORIGINAL"
  correction <- records$knowledge[2L, , drop = FALSE]
  correction$body <- "PRIVATE-FORGET-CORRECTED"
  survivor <- records$knowledge[1L, , drop = FALSE]
  survivor$body <- "Retained accepted correction."
  build <- function(name, remove = character()) {
    path <- file.path(directory, paste0(name, ".duckdb"))
    store <- graft_open(
      graft_schema(system.file(
        "extdata/narrative-knowledge.data-dict.json",
        package = "graft"
      )),
      path,
      okf = "disabled"
    )
    on.exit(graft_close(store))
    selected <- lapply(records, function(table) {
      table[!table$id %in% remove, , drop = FALSE]
    })
    selected <- selected[vapply(selected, nrow, integer(1)) > 0L]
    graft_ingest(
      store,
      selected,
      graft_provenance("synthetic-host", idempotency_key = "seed")
    )
    original <- graft_snapshot(store)
    for (value in list(correction, survivor)) {
      if (!value$id %in% remove) {
        graft_ingest(
          store,
          list(knowledge = value),
          graft_provenance("synthetic-host")
        )
      }
    }
    list(path = path, original = original)
  }
  certify <- function(path, preview) {
    expected <- lapply(records, function(table) {
      table[!table$id %in% preview$ids, , drop = FALSE]
    })
    expected_ids <- sort(unlist(
      lapply(expected, `[[`, "id"),
      use.names = FALSE
    ))
    connection <- DBI::dbConnect(duckdb::duckdb(), path, read_only = TRUE)
    on.exit(DBI::dbDisconnect(connection, shutdown = TRUE))
    # Test-only raw inspection includes fields omitted by public reads.
    ids <- DBI::dbGetQuery(
      connection,
      "SELECT record_id FROM _graft_record_heads"
    )$record_id
    if (!identical(sort(ids), expected_ids)) {
      return(FALSE)
    }
    tables <- lapply(DBI::dbListTables(connection), \(table) {
      DBI::dbReadTable(connection, table)
    })
    encoded <- jsonlite::toJSON(tables, auto_unbox = TRUE)
    if (
      any(vapply(
        preview$ids,
        \(id) grepl(id, encoded, fixed = TRUE),
        logical(1)
      ))
    ) {
      return(FALSE)
    }
    TRUE
  }
  alice <- build("alice")
  bob <- build("bob")
  journal <- file.path(directory, "independent-journal")
  dir.create(journal)
  manifest <- forget_manifest(alice$path, "alice", 0L)
  forget_journal_write(journal, list(status = "active", manifest = manifest))
  backup <- file.path(directory, "offline-backup.duckdb")
  if (!file.copy(alice$path, backup)) {
    forget_error()
  }
  copies <- file.path(
    directory,
    c("managed-okf", "query-cache", "reuse-checkpoint", "conversation")
  )
  for (path in copies) {
    writeLines("PRIVATE-FORGET-CORRECTED", path)
  }
  list(
    directory = directory,
    certify = certify,
    records = records,
    build = build,
    alice = alice,
    bob = bob,
    journal = journal,
    manifest = manifest,
    backup = backup,
    copies = copies,
    purge_paths = c(alice$path, copies)
  )
}
