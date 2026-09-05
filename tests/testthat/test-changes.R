test_that("graft_changes reports records accepted since a snapshot", {
  fixture <- changes_fixture_store()
  columns <- c(
    "class",
    "record_id",
    "action",
    "revisions",
    "changed_fields",
    "revision_id",
    "revision_number",
    "batch_id",
    "commit_order",
    "committed_at",
    "record"
  )

  changes <- graft_changes(fixture$store, since = fixture$first)

  expect_identical(names(changes), columns)
  expect_identical(changes$class, c("Claim", "Claim"))
  expect_identical(
    changes$record_id,
    sort(
      c(fixture$ids$active_claim, test_graft_id("changes-new-claim")),
      method = "radix"
    )
  )
  active <- changes[changes$record_id == fixture$ids$active_claim, ]
  added <- changes[changes$record_id != fixture$ids$active_claim, ]
  expect_identical(active$action, "update")
  expect_identical(active$revisions, 2L)
  expect_identical(
    active$changed_fields[[1L]],
    c("importance", "statement_text")
  )
  expect_identical(active$revision_number, 3)
  expect_identical(
    active$record[[1L]]$statement_text,
    "Polyethylene remains very durable."
  )
  expect_identical(added$action, "insert")
  expect_identical(added$revisions, 1L)
  expect_identical(added$revision_number, 1)
  expect_identical(
    attr(changes, "since_commit_order"),
    fixture$first@commit_order
  )
  expect_identical(attr(changes, "since_batch_id"), fixture$first@batch_id)
  expect_identical(
    attr(changes, "until_commit_order"),
    fixture$third@commit_order
  )
  expect_identical(attr(changes, "until_batch_id"), fixture$third@batch_id)
  expect_identical(attr(changes, "truncated"), FALSE)
})

test_that("graft_changes bounds the window with until, views, and classes", {
  fixture <- changes_fixture_store()

  bounded <- graft_changes(
    fixture$store,
    since = fixture$first,
    until = fixture$second
  )
  expect_identical(nrow(bounded), 2L)
  expect_identical(
    bounded$revisions[bounded$record_id == fixture$ids$active_claim],
    1L
  )
  expect_identical(
    bounded$changed_fields[[which(
      bounded$record_id == fixture$ids$active_claim
    )]],
    "statement_text"
  )

  view <- graft_at(fixture$store, fixture$second)
  expect_identical(
    graft_changes(view, since = fixture$first)$revision_id,
    bounded$revision_id
  )
  expect_identical(
    graft_changes(view, since = fixture$first@batch_id)$revision_id,
    bounded$revision_id
  )

  everything <- graft_changes(fixture$store, until = fixture$first)
  expect_identical(unique(everything$action), "insert")
  expect_identical(nrow(everything), 10L)
  expect_identical(attr(everything, "since_batch_id"), NA_character_)

  entities <- graft_changes(
    fixture$store,
    until = fixture$first,
    class = "Entity"
  )
  expect_identical(unique(entities$class), "Entity")
  expect_identical(nrow(entities), 2L)

  limited <- graft_changes(fixture$store, until = fixture$first, limit = 3L)
  expect_identical(nrow(limited), 3L)
  expect_identical(attr(limited, "truncated"), TRUE)
  expect_identical(attr(limited, "limit"), 3L)

  none <- graft_changes(
    fixture$store,
    since = fixture$third,
    until = fixture$third
  )
  expect_identical(nrow(none), 0L)
  expect_identical(names(none), names(everything))
})

test_that("graft_changes rejects inverted, foreign, and late boundaries", {
  fixture <- changes_fixture_store()

  expect_error(
    graft_changes(fixture$store, since = fixture$third, until = fixture$first),
    class = "graft_validation_error"
  )
  expect_error(
    graft_changes(fixture$store, class = "Missing"),
    class = "graft_validation_error"
  )
  view <- graft_at(fixture$store, fixture$first)
  expect_error(
    graft_changes(view, until = fixture$second),
    class = "graft_snapshot_boundary_error"
  )
  other <- local_graft_ingest_store()
  expect_error(
    graft_changes(fixture$store, since = graft_snapshot(other)),
    class = "graft_snapshot_error"
  )
  divergent <- graft:::new_graft_snapshot(
    store_id = fixture$first@store_id,
    store_format_version = fixture$first@store_format_version,
    schema_build_digest = fixture$first@schema_build_digest,
    commit_order = fixture$first@commit_order,
    batch_id = fixture$second@batch_id,
    committed_at = fixture$first@committed_at,
    history_complete = TRUE
  )
  expect_error(
    graft_changes(fixture$store, since = divergent),
    class = "graft_snapshot_error"
  )
})

test_that("graft_changes reports a deleted head as a deletion", {
  fixture <- changes_fixture_store()
  connection <- graft_test_connection(fixture$store)
  latest <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT revision_id, batch_id, revision_number, commit_order",
      "FROM _graft_record_revisions WHERE record_id = ?",
      "ORDER BY commit_order DESC LIMIT 1"
    ),
    params = list(fixture$ids$active_claim)
  )
  delete_batch <- test_graft_id("changes-delete-batch")
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO _graft_batches (batch_id, schema_build_digest, commit_order,",
      "producer, producer_version, source_run_id, idempotency_key,",
      "metadata_json, started_at, committed_at, status)",
      "SELECT ?, schema_build_digest, commit_order + 1, producer,",
      "producer_version, source_run_id, 'changes-delete', metadata_json,",
      "started_at, committed_at, status FROM _graft_batches WHERE batch_id = ?"
    ),
    params = list(delete_batch, latest$batch_id[[1L]])
  )
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO _graft_record_revisions (revision_id, record_id, class,",
      "batch_id, schema_build_digest, revision_number, operation, payload_json,",
      "content_digest, changed_fields_json, prior_revision_id, recorded_at,",
      "commit_order)",
      "SELECT ?, record_id, class, ?, schema_build_digest, revision_number + 1,",
      "'delete', payload_json, content_digest, '[]', revision_id, recorded_at,",
      "commit_order + 1 FROM _graft_record_revisions WHERE revision_id = ?"
    ),
    params = list(
      test_graft_id("changes-delete-revision"),
      delete_batch,
      latest$revision_id[[1L]]
    )
  )
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
    params = list(
      delete_batch,
      test_graft_id("changes-delete-revision"),
      fixture$ids$active_claim,
      latest$batch_id[[1L]]
    )
  )
  view <- graft_at(fixture$store, graft_snapshot(fixture$store))

  changes <- graft_changes(view, since = fixture$third)

  expect_identical(changes$record_id, fixture$ids$active_claim)
  expect_identical(changes$action, "delete")
  expect_identical(changes$changed_fields[[1L]], character())
  expect_null(changes$record[[1L]])
  expect_identical(changes$revisions, 1L)
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE _graft_record_heads SET revision_id = ?, revision_number = ?",
      "WHERE record_id = ?"
    ),
    params = list(
      test_graft_id("changes-delete-revision"),
      latest$revision_number[[1L]] + 1,
      fixture$ids$active_claim
    )
  )
  live <- graft_changes(fixture$store, since = fixture$third)
  expect_identical(live$action, "delete")
})

test_that("graft_changes validates the prior boundary payload", {
  fixture <- changes_fixture_store()
  connection <- graft_test_connection(fixture$store)
  first_revision <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT revision_id FROM _graft_record_revisions WHERE record_id = ?",
      "ORDER BY commit_order ASC LIMIT 1"
    ),
    params = list(fixture$ids$active_claim)
  )$revision_id[[1L]]
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE _graft_record_revisions SET payload_json = ",
      "replace(payload_json, 'Polyethylene remains durable.', 'corrupted')",
      "WHERE revision_id = ?"
    ),
    params = list(first_revision)
  )

  expect_error(
    graft_changes(fixture$store, since = fixture$first, until = fixture$second),
    class = "graft_error"
  )
})

test_that("graft_changes validates a deleted revision before hiding it", {
  fixture <- changes_fixture_store()
  connection <- graft_test_connection(fixture$store)
  latest <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT revision_id, batch_id, revision_number FROM",
      "_graft_record_revisions WHERE record_id = ?",
      "ORDER BY commit_order DESC LIMIT 1"
    ),
    params = list(fixture$ids$active_claim)
  )
  delete_batch <- test_graft_id("changes-corrupt-delete-batch")
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO _graft_batches (batch_id, schema_build_digest, commit_order,",
      "producer, producer_version, source_run_id, idempotency_key,",
      "metadata_json, started_at, committed_at, status)",
      "SELECT ?, schema_build_digest, commit_order + 1, producer,",
      "producer_version, source_run_id, 'changes-corrupt-delete', metadata_json,",
      "started_at, committed_at, status FROM _graft_batches WHERE batch_id = ?"
    ),
    params = list(delete_batch, latest$batch_id[[1L]])
  )
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO _graft_record_revisions (revision_id, record_id, class,",
      "batch_id, schema_build_digest, revision_number, operation, payload_json,",
      "content_digest, changed_fields_json, prior_revision_id, recorded_at,",
      "commit_order)",
      "SELECT ?, record_id, class, ?, schema_build_digest, revision_number + 1,",
      "'delete', replace(payload_json, 'durable', 'corrupted'), content_digest,",
      "'[]', revision_id, recorded_at, commit_order + 1",
      "FROM _graft_record_revisions WHERE revision_id = ?"
    ),
    params = list(
      test_graft_id("changes-corrupt-delete-revision"),
      delete_batch,
      latest$revision_id[[1L]]
    )
  )
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
    params = list(
      delete_batch,
      test_graft_id("changes-corrupt-delete-revision"),
      fixture$ids$active_claim,
      latest$batch_id[[1L]]
    )
  )
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE _graft_record_heads SET revision_id = ?, revision_number = ?",
      "WHERE record_id = ?"
    ),
    params = list(
      test_graft_id("changes-corrupt-delete-revision"),
      latest$revision_number[[1L]] + 1,
      fixture$ids$active_claim
    )
  )
  view <- graft_at(fixture$store, graft_snapshot(fixture$store))

  expect_error(
    graft_changes(view, since = fixture$third),
    class = "graft_error"
  )
  after_delete <- graft_view_snapshot(view)
  resurrected <- retrieval_fixture_records()$records
  graft_ingest(
    fixture$store,
    resurrected,
    graft_provenance("changes-fixture", idempotency_key = "changes-4")
  )
  expect_error(
    graft_changes(fixture$store, since = after_delete),
    class = "graft_error"
  )
})

test_that("selected IDs are filtered before bounds and intersect class restrictions", {
  store <- local_narrative_store()
  before <- graft_snapshot(store)
  records <- narrative_fixture()$narrative_records()
  records$knowledge$body <- paste(records$knowledge$body, "Changed.")
  records$source$quote <- "Revised evidence."
  graft_ingest(
    store,
    records,
    graft_provenance("scope", idempotency_key = "changed")
  )
  after <- graft_snapshot(store)
  unscoped <- graft_changes(store, since = before, limit = 1L)
  expect_identical(attr(unscoped, "truncated"), TRUE)
  expect_identical("source:trial-v1" %in% unscoped$record_id, FALSE)
  scoped <- graft_changes(
    store,
    since = before,
    limit = 1L,
    record_ids = c(source = "source:trial-v1", "source:trial-v1", "missing")
  )
  expect_identical(scoped$record_id, "source:trial-v1")
  expect_identical(scoped$record[[1L]]$quote, "Revised evidence.")
  expect_identical(attr(scoped, "truncated"), FALSE)
  expect_identical(attr(scoped, "until_batch_id"), after@batch_id)
  expect_identical(
    graft_changes(
      graft_at(store, after),
      since = before,
      record_ids = "source:trial-v1",
      limit = 1L
    ),
    scoped
  )
  expect_equal(
    nrow(graft_changes(
      store,
      since = before,
      record_ids = "source:trial-v1",
      class = "knowledge"
    )),
    0L
  )
  limited <- graft_changes(
    store,
    since = before,
    limit = 1L,
    record_ids = c("knowledge:question", "source:trial-v1")
  )
  expect_identical(attr(limited, "truncated"), TRUE)
  expect_identical(limited$record_id, "knowledge:question")
})

test_that("empty and unknown selections never fall back to the whole store", {
  store <- local_narrative_store()
  empty <- graft_changes(store, record_ids = character())
  expect_equal(nrow(empty), 0L)
  expect_identical(attr(empty, "truncated"), FALSE)
  expect_named(empty, names(graft_changes(store)))
  expect_identical(graft_changes(store, record_ids = "missing"), empty)
  expect_identical(graft_changes(store, record_ids = "' OR TRUE --"), empty)
  expect_gt(nrow(graft_changes(store, record_ids = NULL)), 0L)
  expect_error(
    graft_changes(
      store,
      since = graft_snapshot(local_narrative_store()),
      record_ids = character()
    ),
    class = "graft_snapshot_error"
  )
})

test_that("record selection validates vector shape and input bounds", {
  store <- local_narrative_store()
  for (ids in list(NA_character_, "", 1L, list("id"), matrix("id"))) {
    expect_error(
      graft_changes(store, record_ids = ids),
      class = "graft_validation_error"
    )
  }
  expect_error(
    graft_changes(store, record_ids = rep("id", 5001L)),
    class = "graft_limit_error"
  )
  expect_equal(
    nrow(graft_changes(store, record_ids = rep("missing", 5000L))),
    0L
  )
})
