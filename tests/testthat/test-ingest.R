test_that("a valid multi-class batch commits atomically", {
  store <- local_ingest_store()
  records <- valid_atomic_records()
  batch <- kg_batch("tempest", "0.8.0", "run-001", "run-001")

  result <- kg_ingest(store, batch, records)

  expect_s3_class(result, "kg_ingest_result")
  expect_identical(sum(result$inserted), 7L)
  expect_identical(sum(result$observed), 7L)
  expect_identical(
    DBI::dbReadTable(store$connection, "_graft_batches")$status,
    "committed"
  )
  expect_equal(nrow(DBI::dbReadTable(store$connection, "claim__about")), 1L)
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_origins")),
    7L
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_observations")),
    7L
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_revisions")),
    7L
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_heads")),
    7L
  )
  batch_row <- DBI::dbReadTable(store$connection, "_graft_batches")
  expect_identical(
    batch_row$schema_build_digest,
    store$schema$manifest$fingerprints$build_digest
  )
  expect_identical(batch_row$commit_order, 1)
})

test_that("invalid evidence rolls back every table and batch row", {
  store <- local_ingest_store()
  records <- valid_atomic_records()
  records$ClaimEvidence$source_id <- test_graft_id("missing-source")

  condition <- catch_graft_ingest_condition(
    kg_ingest(
      store,
      kg_batch("tempest", "0.8.0", "bad-run", "bad-run"),
      records
    )
  )

  expect_s3_class(condition, "graft_reference_error")
  expect_identical(condition$record_class, "ClaimEvidence")
  client_tables <- vapply(
    store$schema$manifest$tables,
    \(.x) nrow(DBI::dbReadTable(store$connection, .x$name)),
    integer(1)
  )
  relation_tables <- vapply(
    store$schema$manifest$relations,
    \(.x) nrow(DBI::dbReadTable(store$connection, .x$table)),
    integer(1)
  )
  metadata <- c(
    "_graft_batches",
    "_graft_identifiers",
    "_graft_record_heads",
    "_graft_record_origins",
    "_graft_record_observations",
    "_graft_record_revisions"
  )
  metadata_rows <- vapply(
    metadata,
    \(.x) nrow(DBI::dbReadTable(store$connection, .x)),
    integer(1)
  )
  expect_identical(unname(client_tables), integer(length(client_tables)))
  expect_identical(unname(relation_tables), integer(length(relation_tables)))
  expect_identical(unname(metadata_rows), integer(length(metadata_rows)))
})

test_that("preflight validation never writes", {
  store <- local_ingest_store()
  records <- valid_atomic_records()
  records$Claim$confidence <- 2
  before <- lapply(DBI::dbListTables(store$connection), function(table) {
    DBI::dbReadTable(store$connection, table)
  })
  names(before) <- DBI::dbListTables(store$connection)

  report <- kg_validate_data(store, records)

  expect_s3_class(report, "kg_validation_report")
  expect_identical(report$valid, FALSE)
  expect_identical(report$failures$rule, "maximum_value")
  after <- lapply(names(before), function(table) {
    DBI::dbReadTable(store$connection, table)
  })
  names(after) <- names(before)
  expect_identical(after, before)
})

test_that("committed idempotency replay creates no additional rows", {
  store <- local_ingest_store()
  records <- list(Entity = valid_atomic_records()$Entity)
  first <- kg_ingest(
    store,
    kg_batch("tempest", "0.8.0", "run-replay", "replay-key"),
    records
  )
  before <- vapply(
    DBI::dbListTables(store$connection),
    \(.x) nrow(DBI::dbReadTable(store$connection, .x)),
    integer(1)
  )
  replay_condition <- NULL

  replay <- withCallingHandlers(
    kg_ingest(
      store,
      kg_batch("tempest", "0.8.1", "run-replay-again", "replay-key"),
      records
    ),
    graft_batch_replay = function(condition) {
      replay_condition <<- condition
    }
  )

  after <- vapply(
    DBI::dbListTables(store$connection),
    \(.x) nrow(DBI::dbReadTable(store$connection, .x)),
    integer(1)
  )
  expect_s3_class(replay_condition, "graft_batch_replay")
  expect_identical(replay$batch_id, first$batch_id)
  expect_identical(replay$replay, TRUE)
  expect_identical(after, before)
})

test_that("origin-key upserts update mutable data without changing ID", {
  store <- local_ingest_store()
  first <- data.frame(
    preferred_name = "First name",
    .graft_origin_key = "entity-42",
    check.names = FALSE
  )
  second <- data.frame(
    preferred_name = "Updated name",
    .graft_origin_key = "entity-42",
    check.names = FALSE
  )
  first_result <- kg_write(
    store,
    kg_batch("producer-a", idempotency_key = "origin-1"),
    "Entity",
    first
  )
  original <- DBI::dbReadTable(store$connection, "entity")

  second_result <- kg_write(
    store,
    kg_batch("producer-a", idempotency_key = "origin-2"),
    "Entity",
    second
  )
  updated <- DBI::dbReadTable(store$connection, "entity")

  expect_identical(first_result$inserted[["Entity"]], 1L)
  expect_identical(second_result$updated[["Entity"]], 1L)
  expect_identical(updated$id, original$id)
  expect_identical(updated$preferred_name, "Updated name")
  expect_identical(updated$created_at, original$created_at)
  expect_gte(updated$updated_at, original$updated_at)

  matched_result <- kg_write(
    store,
    kg_batch("producer-a", idempotency_key = "origin-match"),
    "Entity",
    second
  )
  revisions <- DBI::dbReadTable(
    store$connection,
    "_graft_record_revisions"
  )
  heads <- DBI::dbReadTable(store$connection, "_graft_record_heads")
  observations <- DBI::dbReadTable(
    store$connection,
    "_graft_record_observations"
  )
  payloads <- lapply(
    revisions$payload_json,
    jsonlite::fromJSON,
    simplifyVector = FALSE
  )
  changed <- lapply(
    revisions$changed_fields_json,
    jsonlite::fromJSON,
    simplifyVector = FALSE
  )

  expect_identical(matched_result$matched[["Entity"]], 1L)
  expect_equal(nrow(revisions), 2L)
  expect_identical(revisions$revision_number, c(1, 2))
  expect_identical(revisions$operation, c("insert", "update"))
  expect_identical(
    revisions$prior_revision_id,
    c(NA_character_, revisions$revision_id[[1L]])
  )
  expect_identical(revisions$commit_order, c(1, 2))
  expect_identical(payloads[[1L]]$preferred_name, "First name")
  expect_identical(payloads[[2L]]$preferred_name, "Updated name")
  expect_in("created_at", names(payloads[[1L]]))
  expect_in("updated_at", names(payloads[[1L]]))
  expect_identical(
    unlist(changed[[2L]], use.names = FALSE),
    "preferred_name"
  )
  expect_identical(heads$revision_id, revisions$revision_id[[2L]])
  expect_identical(
    observations$revision_id,
    c(revisions$revision_id, revisions$revision_id[[2L]])
  )
  expect_identical(
    observations$disposition,
    c("inserted", "updated", "matched")
  )

  changed_id <- data.frame(
    id = test_graft_id("different"),
    preferred_name = "Wrong ID",
    .graft_origin_key = "entity-42",
    check.names = FALSE
  )
  condition <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("producer-a", idempotency_key = "origin-3"),
      "Entity",
      changed_id
    )
  )
  expect_s3_class(condition, "graft_identity_error")
  expect_identical(DBI::dbReadTable(store$connection, "entity")$id, original$id)
})

test_that("generated Claim.about synchronization preserves retained rows", {
  store <- local_ingest_store()
  entity_one <- test_graft_id("about-one")
  entity_two <- test_graft_id("about-two")
  entity_three <- test_graft_id("about-three")
  claim_id <- test_graft_id("about-claim")
  kg_ingest(
    store,
    kg_batch("tempest", idempotency_key = "about-1"),
    list(
      Entity = data.frame(
        id = c(entity_one, entity_two, entity_three),
        preferred_name = c("One", "Two", "Three")
      ),
      Claim = data.frame(
        id = claim_id,
        statement_text = "A claim",
        about = I(list(c(entity_one, entity_two))),
        .graft_origin_key = "claim-1",
        check.names = FALSE
      )
    )
  )
  before <- DBI::dbReadTable(store$connection, "claim__about")
  retained_before <- before[before$object == entity_two, , drop = FALSE]

  result <- kg_write(
    store,
    kg_batch("tempest", idempotency_key = "about-2"),
    "Claim",
    data.frame(
      statement_text = "A claim",
      about = I(list(c(entity_two, entity_three))),
      .graft_origin_key = "claim-1",
      check.names = FALSE
    )
  )
  after <- DBI::dbReadTable(store$connection, "claim__about")
  retained_after <- after[after$object == entity_two, , drop = FALSE]

  expect_identical(result$updated[["Claim"]], 1L)
  expect_identical(unique(after$subject), claim_id)
  expect_setequal(after$object, c(entity_two, entity_three))
  expect_identical(retained_after$id, retained_before$id)
  expect_identical(retained_after$created_at, retained_before$created_at)
  expect_length(
    intersect(after$id[after$object == entity_three], before$id),
    0L
  )

  revisions <- DBI::dbReadTable(
    store$connection,
    "_graft_record_revisions"
  )
  claim_revisions <- revisions[revisions$class == "Claim", , drop = FALSE]
  payloads <- lapply(
    claim_revisions$payload_json,
    jsonlite::fromJSON,
    simplifyVector = FALSE
  )
  changed <- jsonlite::fromJSON(
    claim_revisions$changed_fields_json[[2L]],
    simplifyVector = FALSE
  )
  expect_identical(
    unlist(payloads[[1L]]$about, use.names = FALSE),
    sort(c(entity_one, entity_two))
  )
  expect_identical(
    unlist(payloads[[2L]]$about, use.names = FALSE),
    sort(c(entity_two, entity_three))
  )
  expect_identical(unlist(changed, use.names = FALSE), "about")
})

test_that("post-revision failures roll back history and current state", {
  store <- local_ingest_store()
  local_mocked_bindings(
    write_staged_records = function(...) stop("forced write failure")
  )

  condition <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "forced-failure"),
      "Entity",
      data.frame(preferred_name = "Must roll back")
    )
  )

  expect_s3_class(condition, "graft_backend_error")
  expect_equal(nrow(DBI::dbReadTable(store$connection, "entity")), 0L)
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_revisions")),
    0L
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_heads")),
    0L
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_batches")),
    0L
  )
})

test_that("ingestion refuses current-state drift from revision heads", {
  store <- local_ingest_store()
  input <- data.frame(
    preferred_name = "Accepted",
    .graft_origin_key = "drift-check",
    check.names = FALSE
  )
  kg_write(
    store,
    kg_batch("tempest", idempotency_key = "drift-1"),
    "Entity",
    input
  )
  DBI::dbExecute(
    store$connection,
    "UPDATE entity SET preferred_name = 'Direct write'"
  )

  condition <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "drift-2"),
      "Entity",
      transform(input, preferred_name = "Proposed update")
    )
  )

  expect_s3_class(condition, "graft_backend_error")
  expect_match(conditionMessage(condition), "differs from its revision head")
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_revisions")),
    1L
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_batches")),
    1L
  )
})

test_that("one exact entity can be observed in thirty batches", {
  store <- local_ingest_store()
  for (index in seq_len(30L)) {
    kg_write(
      store,
      kg_batch(
        "tempest",
        source_run_id = paste0("run-", index),
        idempotency_key = paste0("run-", index)
      ),
      "Entity",
      data.frame(
        preferred_name = "Water",
        inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
      )
    )
  }

  expect_equal(nrow(DBI::dbReadTable(store$connection, "entity")), 1L)
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_observations")),
    30L
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_revisions")),
    1L
  )
  batches <- DBI::dbReadTable(store$connection, "_graft_batches")
  expect_identical(batches$commit_order, as.numeric(seq_len(30L)))
})

test_that("structural mismatch refuses ingestion", {
  store <- local_ingest_store()
  incompatible <- modified_ingest_schema(store$schema)
  incompatible$manifest$fingerprints$structural_digest <- paste0(
    "sha256:",
    paste(rep("f", 64L), collapse = "")
  )
  store$schema <- incompatible

  condition <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest"),
      "Entity",
      data.frame(preferred_name = "No write")
    )
  )

  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "structural_digest_content_mismatch")
  expect_equal(nrow(DBI::dbReadTable(store$connection, "entity")), 0L)
})

test_that("ingested stores reopen without initializing Python", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema, path)
  kg_init(store)
  kg_write(
    store,
    kg_batch("tempest", idempotency_key = "persisted"),
    "Entity",
    data.frame(preferred_name = "Persisted")
  )
  kg_disconnect(store)
  python_before <- reticulate::py_available(initialize = FALSE)

  reopened <- kg_connect_duckdb(schema, path)
  withr::defer(kg_disconnect(reopened))
  kg_init(reopened)

  expect_equal(nrow(DBI::dbReadTable(reopened$connection, "entity")), 1L)
  expect_identical(
    reticulate::py_available(initialize = FALSE),
    python_before
  )
})
