test_that("batch and revision history is bounded, filtered, and sensitivity-safe", {
  schema <- modified_ingest_schema(kg_schema(tempest_manifest_path()))
  schema$manifest$classes$Entity$slots$description$sensitive <- TRUE
  schema <- refresh_schema_structural_digest(schema)
  store <- local_ingest_store(schema = schema)
  clock <- 0L
  local_mocked_bindings(
    ingest_now = function() {
      clock <<- clock + 1L
      as.POSIXct("2026-01-01 00:00:00", tz = "UTC") + clock * 60
    }
  )
  first <- kg_write(
    store,
    kg_batch(
      "producer-a",
      source_run_id = "run-1",
      idempotency_key = "history-1",
      metadata = list(note = "first")
    ),
    "Entity",
    data.frame(
      preferred_name = "First name",
      description = "first secret",
      .graft_origin_key = "history-entity",
      check.names = FALSE
    )
  )
  record_id <- DBI::dbReadTable(store$connection, "entity")$id[[1L]]
  matched <- kg_write(
    store,
    kg_batch(
      "producer-a",
      source_run_id = "run-2",
      idempotency_key = "history-2"
    ),
    "Entity",
    data.frame(
      preferred_name = "First name",
      description = "first secret",
      .graft_origin_key = "history-entity",
      check.names = FALSE
    )
  )
  updated <- kg_write(
    store,
    kg_batch(
      "producer-a",
      source_run_id = "run-3",
      idempotency_key = "history-3"
    ),
    "Entity",
    data.frame(
      preferred_name = "Current name",
      description = "current secret",
      .graft_origin_key = "history-entity",
      check.names = FALSE
    )
  )

  batches <- kg_batches(store)
  expect_identical(batches$commit_order, c(3, 2, 1))
  expect_equal(
    batches$started_at,
    as.POSIXct(
      c(
        "2026-01-01 00:05:00",
        "2026-01-01 00:03:00",
        "2026-01-01 00:01:00"
      ),
      tz = "UTC"
    )
  )
  expect_equal(
    batches$committed_at,
    as.POSIXct(
      c(
        "2026-01-01 00:06:00",
        "2026-01-01 00:04:00",
        "2026-01-01 00:02:00"
      ),
      tz = "UTC"
    )
  )
  expect_identical(
    batches$batch_id,
    c(
      updated$batch_id,
      matched$batch_id,
      first$batch_id
    )
  )
  expect_identical(batches$metadata[[3L]]$note, "first")
  expect_identical(batches$result[[2L]]$matched$Entity, 1L)
  expect_identical(
    kg_batches(store, producer = "producer-a")$batch_id,
    c(updated$batch_id, matched$batch_id, first$batch_id)
  )
  expect_identical(
    kg_batches(store, source_run_id = "run-2")$batch_id,
    matched$batch_id
  )
  expect_identical(
    kg_batches(
      store,
      from = as.POSIXct("2026-01-01 00:04:00", tz = "UTC"),
      to = as.POSIXct("2026-01-01 00:04:00", tz = "UTC")
    )$batch_id,
    matched$batch_id
  )
  expect_equal(
    nrow(kg_batches(
      store,
      from = as.POSIXct("2026-01-01 00:03:00", tz = "UTC"),
      to = as.POSIXct("2026-01-01 00:03:00", tz = "UTC")
    )),
    0L
  )
  one_batch <- kg_batches(store, limit = 1)
  expect_identical(attr(one_batch, "truncated"), TRUE)
  expect_identical(attr(one_batch, "limit"), 1L)
  expect_identical(attr(one_batch, "newest_first"), TRUE)
  expect_identical(
    attr(one_batch, "store_schema_digest"),
    store_schema_digest(store)
  )

  changes <- kg_changes(store, record_id = record_id)
  expect_identical(changes$revision_number, c(2, 1))
  expect_identical(changes$operation, c("update", "insert"))
  expect_setequal(
    intersect(names(changes), c("changed_fields", "record")),
    c("changed_fields", "record")
  )
  expect_identical("payload_json" %in% names(changes), FALSE)
  expect_identical("content_digest" %in% names(changes), FALSE)
  expect_identical("changed_fields_json" %in% names(changes), FALSE)
  expect_identical("description" %in% names(changes$record[[1L]]), FALSE)
  expect_identical("description" %in% changes$changed_fields[[1L]], FALSE)
  expect_identical(changes$record[[1L]]$preferred_name, "Current name")
  expect_identical(
    kg_changes(store, batch_id = first$batch_id)$revision_number,
    1
  )
  expect_identical(
    kg_changes(store, class = "Entity")$record_id,
    rep(record_id, 2L)
  )
  one_change <- kg_changes(store, limit = 1)
  expect_identical(attr(one_change, "truncated"), TRUE)
  expect_identical(
    kg_changes(
      store,
      from = as.POSIXct("2026-01-01 00:06:00", tz = "UTC")
    )$revision_number,
    2
  )

  history <- kg_history(store, record_id)
  expect_identical(history$revision_number, c(2, 1))
  at_first <- kg_history(store, record_id, as_of = first$batch_id, limit = 1)
  expect_identical(at_first$record[[1L]]$preferred_name, "First name")
  expect_identical(attr(at_first, "as_of_commit_order"), 1)
  at_match <- kg_history(store, record_id, as_of = matched$batch_id, limit = 1)
  expect_identical(at_match$record[[1L]]$preferred_name, "First name")
  at_time <- kg_history(
    store,
    record_id,
    as_of = as.POSIXct("2026-01-01 00:02:00", tz = "UTC"),
    limit = 1
  )
  expect_identical(at_time$record[[1L]]$preferred_name, "First name")
  during_matched <- kg_history(
    store,
    record_id,
    as_of = as.POSIXct("2026-01-01 00:03:00", tz = "UTC"),
    limit = 1
  )
  expect_identical(
    during_matched$record[[1L]]$preferred_name,
    "First name"
  )
  expect_identical(attr(during_matched, "as_of_commit_order"), 1)
  expect_error(
    kg_history(store, record_id, as_of = "missing-batch"),
    class = "graft_history_boundary_error"
  )
  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_batches SET status = 'started' WHERE batch_id = ?",
    params = list(matched$batch_id)
  )
  expect_error(
    kg_history(store, record_id, as_of = matched$batch_id),
    class = "graft_history_boundary_error"
  )
  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_batches SET status = 'committed' WHERE batch_id = ?",
    params = list(matched$batch_id)
  )
  expect_error(
    kg_history(
      store,
      record_id,
      as_of = as.POSIXct("2026-01-01 00:01:00", tz = "UTC")
    ),
    class = "graft_history_boundary_error"
  )
})

test_that("store checks report bounded shallow and deep drift", {
  store <- local_ingest_store()
  first <- kg_write(
    store,
    kg_batch("producer", idempotency_key = "check-1"),
    "Entity",
    data.frame(
      preferred_name = "Accepted",
      .graft_origin_key = "check-entity",
      check.names = FALSE
    )
  )
  matched <- kg_write(
    store,
    kg_batch("producer", idempotency_key = "check-2"),
    "Entity",
    data.frame(
      preferred_name = "Accepted",
      .graft_origin_key = "check-entity",
      check.names = FALSE
    )
  )

  clean <- kg_check_store(store, deep = TRUE)
  expect_s3_class(clean, "kg_store_check")
  expect_identical(clean$valid, TRUE)
  expect_equal(nrow(clean$issues), 0L)
  printed <- capture.output(print(clean))
  expect_match(printed[[1L]], "<kg_store_check> valid \\(deep\\)")
  expect_match(printed[[2L]], "issues:    0")

  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_record_revisions SET commit_order = 99"
  )
  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_record_observations SET disposition = 'updated' WHERE batch_id = ?",
    params = list(matched$batch_id)
  )
  inconsistent <- kg_check_store(store)
  expect_in(
    "revision_commit_order_mismatch",
    inconsistent$issues$issue
  )
  expect_in(
    "observation_disposition_mismatch",
    inconsistent$issues$issue
  )
  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_record_revisions SET commit_order = 1"
  )
  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_record_observations SET disposition = 'matched' WHERE batch_id = ?",
    params = list(matched$batch_id)
  )

  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_record_heads SET revision_number = 99"
  )
  DBI::dbExecute(
    store$connection,
    paste0(
      "UPDATE _graft_record_observations SET revision_id = ",
      "'missing-revision'"
    )
  )
  shallow <- kg_check_store(store, limit = 1)
  expect_identical(shallow$valid, FALSE)
  expect_identical(shallow$truncated, TRUE)
  expect_equal(nrow(shallow$issues), 1L)
  expect_identical(attr(shallow$issues, "truncated"), TRUE)

  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_record_heads SET revision_number = 1"
  )
  revision <- DBI::dbReadTable(
    store$connection,
    "_graft_record_revisions"
  )$revision_id[[1L]]
  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_record_observations SET revision_id = ?",
    params = list(revision)
  )
  DBI::dbExecute(
    store$connection,
    "UPDATE entity SET preferred_name = 'Direct write'"
  )
  shallow_current <- kg_check_store(store)
  deep_current <- kg_check_store(store, deep = TRUE)
  expect_identical(shallow_current$valid, TRUE)
  expect_identical(deep_current$valid, FALSE)
  expect_in("current_payload_drift", deep_current$issues$issue)

  DBI::dbExecute(store$connection, "DELETE FROM entity")
  DBI::dbExecute(store$connection, "DELETE FROM _graft_record_heads")
  lost_projection <- kg_check_store(store, deep = TRUE)
  expect_identical(lost_projection$valid, FALSE)
  expect_in(
    "latest_revision_head_mismatch",
    lost_projection$issues$issue
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_revisions")),
    1L
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_observations")),
    2L
  )
  expect_identical(first$inserted[["Entity"]], 1L)
})

test_that("historical hydration preserves DuckDB scalar types", {
  slots <- list(
    event_date = list(relational_type = "DATE", multivalued = FALSE),
    event_time = list(relational_type = "TIME", multivalued = FALSE),
    amount = list(relational_type = "DECIMAL", multivalued = FALSE),
    dates = list(relational_type = "DATE", multivalued = TRUE),
    times = list(relational_type = "TIME", multivalued = TRUE),
    amounts = list(relational_type = "DECIMAL", multivalued = TRUE),
    empty_dates = list(relational_type = "DATE", multivalued = TRUE),
    empty_times = list(relational_type = "TIME", multivalued = TRUE),
    empty_amounts = list(relational_type = "DECIMAL", multivalued = TRUE)
  )
  slots <- lapply(slots, function(slot) {
    slot$sensitive <- FALSE
    slot
  })
  payload <- list(
    event_date = "2026-07-21",
    event_time = "12:34:56",
    amount = 12.34,
    dates = list("2026-07-20", "2026-07-21"),
    times = list("01:02:03", "23:59:59"),
    amounts = list(1.25, 2.5),
    empty_dates = list(),
    empty_times = list(),
    empty_amounts = list()
  )

  record <- public_revision_record(
    canonical_json(payload),
    list(slots = slots)
  )

  expect_s3_class(record$event_date, "Date")
  expect_s3_class(record$event_time, "difftime")
  expect_type(record$amount, "double")
  expect_s3_class(record$dates, "Date")
  expect_s3_class(record$times, "difftime")
  expect_type(record$amounts, "double")
  expect_s3_class(record$empty_dates, "Date")
  expect_s3_class(record$empty_times, "difftime")
  expect_type(record$empty_amounts, "double")
  expect_length(record$empty_dates, 0L)
  expect_length(record$empty_times, 0L)
  expect_length(record$empty_amounts, 0L)
  expect_equal(as.numeric(record$event_time, units = "secs"), 45296)
})

test_that("object references remain exact character identifiers", {
  scalar_slot <- list(
    name = "subject",
    relational_type = "VARCHAR",
    object_reference = TRUE,
    multivalued = FALSE,
    ordered = FALSE,
    sensitive = FALSE
  )
  multivalue_slot <- scalar_slot
  multivalue_slot$name <- "about"
  multivalue_slot$multivalued <- TRUE
  multivalue_slot$ordered <- TRUE
  identifiers <- c("000123", "9007199254740993")

  expect_identical(
    canonical_slot_value(identifiers[[1L]], scalar_slot),
    identifiers[[1L]]
  )
  expect_identical(
    coerce_slot_vector(identifiers, scalar_slot, "Claim"),
    identifiers
  )
  expect_identical(
    canonical_slot_value(identifiers, multivalue_slot),
    as.list(identifiers)
  )
  expect_identical(
    coerce_historical_value(identifiers[[1L]], scalar_slot),
    identifiers[[1L]]
  )
  expect_identical(
    coerce_historical_value(as.list(identifiers), multivalue_slot),
    identifiers
  )

  numeric_payload <- list(subject = 123, about = list(456, 789))
  canonical_payload <- canonical_manifest_payload(
    numeric_payload,
    list(slots = list(subject = scalar_slot, about = multivalue_slot))
  )
  expect_identical(canonical_payload$subject, "123")
  expect_identical(canonical_payload$about, list("456", "789"))
  expect_identical(
    identical(
      logical_record_content_digest(numeric_payload),
      logical_record_content_digest(canonical_payload)
    ),
    FALSE
  )

  relation <- list(
    kind = "object",
    slot = "about",
    ordered = TRUE,
    columns = list(
      list(name = "subject", type = "VARCHAR"),
      list(name = "object", type = "VARCHAR")
    )
  )
  relation_slot <- relation_value_slot(relation)
  expect_identical(relation_slot$object_reference, TRUE)
  expect_identical(
    relation_value_equal("000123", "123", relation_slot),
    FALSE
  )
})

test_that("non-character object-reference schemas fail canonicalization", {
  slot <- list(
    name = "subject",
    relational_type = "BIGINT",
    object_reference = TRUE,
    multivalued = FALSE
  )

  error <- tryCatch(
    canonical_slot_value("not-a-number", slot),
    error = identity
  )
  expect_s3_class(error, "graft_schema_error")
  expect_identical(error$field, "subject")
  expect_identical(error$relational_type, "BIGINT")
  expect_identical(error$rule, "object_reference_varchar")
  expect_identical(error$operation, "canonicalize_record")

  staging_error <- tryCatch(
    coerce_slot_vector("not-a-number", slot, "Claim"),
    error = identity
  )
  expect_s3_class(staging_error, "graft_schema_error")
  expect_identical(staging_error$operation, "stage_record")

  history_error <- tryCatch(
    coerce_historical_value(NULL, slot),
    error = identity
  )
  expect_s3_class(history_error, "graft_schema_error")
  expect_identical(history_error$operation, "record_history")
})

test_that("TIME values remain canonical across ingest, checks, and history", {
  store <- local_ingest_store(schema = time_ingest_schema())
  first_input <- data.frame(
    name = "Timed activity",
    event_time = "12:34",
    reminder_times = I(list(c("14:00", "08:30:00"))),
    .graft_origin_key = "timed-activity",
    check.names = FALSE
  )
  first <- kg_write(
    store,
    kg_batch("clock", idempotency_key = "time-1"),
    "Activity",
    first_input
  )
  record_id <- DBI::dbReadTable(store$connection, "activity")$id[[1L]]

  expect_identical(kg_check_store(store, deep = TRUE)$valid, TRUE)

  matched <- kg_write(
    store,
    kg_batch("clock", idempotency_key = "time-2"),
    "Activity",
    transform(
      first_input,
      event_time = "12:34:00",
      reminder_times = I(list(c("08:30", "14:00:00")))
    )
  )
  updated <- kg_write(
    store,
    kg_batch("clock", idempotency_key = "time-3"),
    "Activity",
    transform(
      first_input,
      event_time = "12:35",
      reminder_times = I(list(c("08:30", "15:00")))
    )
  )

  expect_identical(first$inserted[["Activity"]], 1L)
  expect_identical(matched$matched[["Activity"]], 1L)
  expect_identical(updated$updated[["Activity"]], 1L)
  expect_identical(kg_check_store(store, deep = TRUE)$valid, TRUE)

  revisions <- DBI::dbGetQuery(
    store$connection,
    paste0(
      "SELECT payload_json, changed_fields_json FROM ",
      "_graft_record_revisions ORDER BY revision_number"
    )
  )
  payloads <- lapply(
    revisions$payload_json,
    jsonlite::fromJSON,
    simplifyVector = FALSE
  )
  expect_equal(nrow(revisions), 2L)
  expect_identical(payloads[[1L]]$event_time, "12:34:00")
  expect_identical(
    unlist(payloads[[1L]]$reminder_times, use.names = FALSE),
    c("08:30:00", "14:00:00")
  )
  expect_setequal(
    unlist(
      jsonlite::fromJSON(
        revisions$changed_fields_json[[2L]],
        simplifyVector = FALSE
      ),
      use.names = FALSE
    ),
    c("event_time", "reminder_times")
  )

  history <- kg_history(store, record_id)
  expect_s3_class(history$record[[1L]]$event_time, "difftime")
  expect_s3_class(history$record[[1L]]$reminder_times, "difftime")
  expect_equal(
    as.numeric(history$record[[1L]]$event_time, units = "secs"),
    45300
  )
})

test_that("history rejects tampered inactive schema registry manifests", {
  schema <- modified_ingest_schema(kg_schema(tempest_manifest_path()))
  schema$manifest$classes$Entity$slots$description$sensitive <- TRUE
  schema <- refresh_schema_structural_digest(schema)
  store <- local_ingest_store(schema = schema)
  kg_write(
    store,
    kg_batch("history-cache", idempotency_key = "history-cache"),
    "Entity",
    data.frame(
      preferred_name = "Project Firefly",
      description = "TOP SECRET"
    )
  )
  record_id <- DBI::dbReadTable(store$connection, "entity")$id[[1L]]
  migrated <- migration_schema_copy(
    schema,
    "history-registry-v2",
    structural = FALSE
  )
  kg_apply_migration(store, kg_plan_migration(store, migrated))
  tampered <- modified_ingest_schema(schema)
  tampered$manifest$classes$Entity$slots$description$sensitive <- FALSE
  DBI::dbExecute(
    store$connection,
    paste(
      "UPDATE _graft_schema_versions SET manifest_json = ?",
      "WHERE build_digest = ?"
    ),
    params = list(
      canonical_manifest_json(tampered$manifest),
      schema$manifest$fingerprints$build_digest
    )
  )

  condition <- catch_graft_ingest_condition(kg_history(store, record_id))

  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "structural_digest_content_mismatch")
})
