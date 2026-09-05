reuse_example <- function() {
  env <- new.env(parent = environment())
  sys.source(system.file("examples/reuse-basis.R", package = "graft"), env)
  env
}

reuse_consumer_selection <- function(consumer) {
  if (consumer == "research") {
    list(
      roots = "knowledge:conclusion",
      dependencies = data.frame(
        outcome = c("knowledge:conclusion", "support:conclusion"),
        dependency = c("support:conclusion", "source:trial-v1")
      )
    )
  } else {
    list(
      roots = c("knowledge:interpretation", "knowledge:preference"),
      dependencies = data.frame(
        outcome = c("knowledge:interpretation", "support:interpretation"),
        dependency = c("support:interpretation", "source:trial-v1")
      )
    )
  }
}

capture_consumer_basis <- function(store, consumer = "reading") {
  selection <- reuse_consumer_selection(consumer)
  reuse_example()$capture_reuse_basis(
    store,
    selection$roots,
    selection$dependencies
  )
}

# A synthetic stored delete revision, not a supported delete or Forget API.
# Graft has no public general record-deletion command. Match its persisted format.
append_reuse_tombstone <- function(store, id) {
  connection <- graft_test_connection(store)
  latest <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT revision_id FROM _graft_record_revisions WHERE record_id = ?",
      "ORDER BY commit_order DESC LIMIT 1"
    ),
    params = list(id)
  )
  snapshot <- graft_snapshot(store)
  batch <- test_graft_id(paste0("delete-", id, snapshot@commit_order))
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO _graft_batches (batch_id, schema_build_digest, commit_order,",
      "producer, producer_version, source_run_id, idempotency_key,",
      "metadata_json, started_at, committed_at, status)",
      "SELECT ?, schema_build_digest, commit_order + 1, producer,",
      "producer_version, source_run_id, ?, metadata_json, started_at,",
      "committed_at, status FROM _graft_batches WHERE batch_id = ?"
    ),
    params = list(batch, batch, snapshot@batch_id)
  )
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO _graft_record_revisions (revision_id, record_id, class,",
      "batch_id, schema_build_digest, revision_number, operation, payload_json,",
      "content_digest, changed_fields_json, prior_revision_id, recorded_at, commit_order)",
      "SELECT ?, record_id, class, ?, schema_build_digest, revision_number + 1,",
      "'delete', payload_json, content_digest, '[]', revision_id, recorded_at, ?",
      "FROM _graft_record_revisions WHERE revision_id = ?"
    ),
    params = list(
      test_graft_id(paste0("revision-", batch)),
      batch,
      snapshot@commit_order + 1,
      latest$revision_id[[1L]]
    )
  )
  invisible(batch)
}
