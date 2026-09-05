changes_fixture_store <- function(env = parent.frame()) {
  store <- local_graft_ingest_store(env = env)
  fixture <- retrieval_fixture_records()
  graft_ingest(
    store,
    fixture$records,
    graft_provenance("changes-fixture", idempotency_key = "changes-1")
  )
  first <- graft_snapshot(store)
  revised <- fixture$records
  revised$Claim$statement_text[[1L]] <- "Polyethylene remains very durable."
  revised$Claim <- rbind(
    revised$Claim,
    data.frame(
      id = test_graft_id("changes-new-claim"),
      statement_text = "Polyethylene resists moisture.",
      primary_subject = fixture$ids$entity,
      claim_type = "finding",
      importance = "medium",
      polarity = "positive",
      status = "active",
      superseded_by = NA_character_,
      about = I(list(fixture$ids$entity))
    )
  )
  graft_ingest(
    store,
    revised,
    graft_provenance("changes-fixture", idempotency_key = "changes-2")
  )
  second <- graft_snapshot(store)
  revised$Claim$importance[[1L]] <- "medium"
  graft_ingest(
    store,
    revised,
    graft_provenance("changes-fixture", idempotency_key = "changes-3")
  )
  list(
    store = store,
    ids = fixture$ids,
    first = first,
    second = second,
    third = graft_snapshot(store)
  )
}

# A synthetic stored delete revision, not a supported delete or Forget API.
# Graft has no public general record-deletion command. Match its persisted format.
append_test_tombstone <- function(store, id) {
  connection <- graft_test_connection(store)
  latest <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT revision_id, batch_id, revision_number FROM _graft_record_revisions WHERE record_id = ?",
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
  revision <- test_graft_id(paste0("revision-", batch))
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO _graft_record_observations (record_id, class, batch_id,",
      "disposition, revision_id, origin_key, matched_by,",
      "identity_evidence_json, observed_at)",
      "SELECT record_id, class, ?, 'deleted', ?, origin_key, matched_by,",
      "identity_evidence_json, observed_at FROM _graft_record_observations",
      "WHERE record_id = ? AND batch_id = ?"
    ),
    params = list(batch, revision, id, latest$batch_id[[1L]])
  )
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE _graft_record_heads SET revision_id = ?, revision_number = ?",
      "WHERE record_id = ?"
    ),
    params = list(revision, latest$revision_number[[1L]] + 1, id)
  )
  invisible(batch)
}
