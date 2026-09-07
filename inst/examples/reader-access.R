# Application-owned teaching recipe, not an authentication or Graft access API.
# The Reader, locator, grant revision, and read callback are trusted host inputs.
reader_knowledge_unavailable <- function() {
  stop(structure(
    list(message = "Accepted knowledge is unavailable.", call = NULL),
    class = c("reader_knowledge_unavailable", "error", "condition")
  ))
}

reader_knowledge_access <- function(reader, locate, grant) {
  force(reader)
  force(locate)
  force(grant)
  read_once <- function(read) {
    revision <- grant(reader)
    if (
      !is.character(revision) ||
        length(revision) != 1L ||
        is.na(revision) ||
        !nzchar(revision)
    ) {
      reader_knowledge_unavailable()
    }
    location <- locate(reader)
    store <- graft::graft_open(
      graft::graft_schema(location$schema),
      location$path,
      read_only = TRUE,
      okf = "disabled"
    )
    on.exit(graft::graft_close(store))
    if (!identical(graft::graft_snapshot(store)@store_id, location$store_id)) {
      reader_knowledge_unavailable()
    }
    value <- read(store)
    if (!identical(grant(reader), revision)) {
      reader_knowledge_unavailable()
    }
    value
  }
  function(read) {
    tryCatch(read_once(read), error = function(error) {
      reader_knowledge_unavailable()
    })
  }
}

reader_record_tool <- function(access, snapshot) {
  force(access)
  force(snapshot)
  access(function(store) {
    graft::graft_at(store, snapshot)
    NULL
  })
  ellmer::tool(
    function(id) {
      access(function(store) {
        view <- graft::graft_at(store, snapshot)
        graft::graft_tools(view, result_format = "json")$graft_get(id)
      })
    },
    name = "graft_get",
    description = "Read one accepted record from this Reader's pinned knowledge.",
    arguments = list(id = ellmer::type_string("Accepted record identifier.")),
    annotations = list(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
}

# Synthetic fixture only. The same public schema and one colliding local ID
# deliberately prevent schema names or globally unique IDs from hiding errors.
reader_access_fixture <- function(directory) {
  schema <- system.file(
    "extdata/narrative-knowledge.data-dict.json",
    package = "graft",
    mustWork = TRUE
  )
  narrative <- new.env()
  sys.source(
    system.file("examples/narrative-knowledge.R", package = "graft"),
    narrative
  )
  create <- function(reader) {
    path <- file.path(directory, paste0(reader, ".duckdb"))
    store <- graft::graft_open(
      graft::graft_schema(schema),
      path,
      okf = "disabled"
    )
    on.exit(graft::graft_close(store))
    records <- narrative$narrative_records()
    qualify <- function(ids) {
      ifelse(ids == "knowledge:preference", ids, paste0(ids, ":", reader))
    }
    records <- lapply(records, function(table) {
      table$id <- qualify(table$id)
      table
    })
    records$knowledge$body <- paste(reader, records$knowledge$body)
    records$knowledge$owner_binding <- paste0("private-owner-", reader)
    records$source$document_revision <- paste0("private-document-", reader)
    records$source$quote <- paste(
      reader,
      "private capture from https://example.org/report"
    )
    records$support$knowledge_id <- qualify(records$support$knowledge_id)
    records$support$source_id <- qualify(records$support$source_id)
    if (reader == "bob") {
      records$knowledge <- records$knowledge[1:3, ]
    }
    records$GraftDefinition <- data.frame(
      name = "knowledge_count",
      target = "knowledge",
      expr = "ROW_COUNT()"
    )
    graft::graft_ingest(
      store,
      records,
      graft::graft_provenance(paste0("host-", reader), idempotency_key = "seed")
    )
    snapshot <- graft::graft_snapshot(store)
    list(
      path = path,
      schema = schema,
      store_id = snapshot@store_id,
      snapshot = snapshot
    )
  }
  stats::setNames(lapply(c("alice", "bob"), create), c("alice", "bob"))
}
