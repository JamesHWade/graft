test_that("planning is read-only and exposes reviewed changes", {
  store <- local_ingest_store()
  records <- list(Entity = valid_atomic_records()$Entity)
  before <- lapply(DBI::dbListTables(store$connection), function(table) {
    DBI::dbReadTable(store$connection, table)
  })
  names(before) <- DBI::dbListTables(store$connection)

  plan <- graft_plan(
    store,
    records,
    graft_provenance("workflow", idempotency_key = "plan-only")
  )

  after <- lapply(names(before), function(table) {
    DBI::dbReadTable(store$connection, table)
  })
  names(after) <- names(before)
  expect_s7_class(plan, graft:::GraftCommitPlan)
  expect_identical(plan@valid, TRUE)
  expect_identical(plan@source, "records")
  expect_identical(plan@changes$action, "insert")
  expect_identical(plan@changes$class, "Entity")
  expect_match(plan@plan_digest, "^sha256:[0-9a-f]{64}$")
  expect_identical(after, before)
})

test_that("planning is deterministic for an unchanged store snapshot", {
  store <- local_ingest_store()
  records <- list(Entity = valid_atomic_records()$Entity)
  provenance <- graft_provenance(
    "workflow",
    idempotency_key = "deterministic-plan"
  )
  clock <- 0L
  local_mocked_bindings(
    ingest_now = function() {
      clock <<- clock + 1L
      as.POSIXct("2030-01-01", tz = "UTC") + clock * 3600
    }
  )

  first <- graft_plan(store, records, provenance)
  second <- graft_plan(store, records, provenance)

  expect_identical(first@planned_at, second@planned_at)
  expect_identical(first@execution_digest, second@execution_digest)
  expect_identical(first@plan_digest, second@plan_digest)
  expect_identical(first@plan_id, second@plan_id)
})

test_that("planning assigns match and update from one current-head snapshot", {
  store <- local_ingest_store()
  records <- list(
    Entity = data.frame(
      id = test_graft_id("head-snapshot"),
      preferred_name = "Snapshot entity"
    )
  )
  provenance <- graft_provenance("head-test")
  inserted <- graft_plan(store, records, provenance)
  staged_row <- graft:::commit_plan_execution(inserted)$staged$rows[1L, ]
  prior_created <- "2025-01-02T12:34:56.123456Z"
  prior_updated <- "2025-02-03T21:43:54.654321Z"
  prior_payload <- jsonlite::fromJSON(
    staged_row$payload_json,
    simplifyVector = FALSE
  )
  prior_payload$created_at <- prior_created
  prior_payload$updated_at <- prior_updated
  staged_row$payload_json <- canonical_json(prior_payload)
  revision_id <- test_graft_id("head-snapshot-revision")
  DBI::dbAppendTable(
    store$connection,
    "_graft_record_revisions",
    data.frame(
      revision_id = revision_id,
      record_id = staged_row$record_id,
      class = staged_row$class,
      batch_id = test_graft_id("head-snapshot-batch"),
      schema_build_digest = inserted@schema_build_digest,
      revision_number = 1,
      operation = "insert",
      payload_json = staged_row$payload_json,
      content_digest = staged_row$content_digest,
      changed_fields_json = staged_row$changed_fields_json,
      prior_revision_id = NA_character_,
      recorded_at = inserted@planned_at,
      commit_order = 1,
      stringsAsFactors = FALSE
    )
  )
  DBI::dbAppendTable(
    store$connection,
    "_graft_record_heads",
    data.frame(
      record_id = staged_row$record_id,
      class = staged_row$class,
      revision_id = revision_id,
      revision_number = 1,
      updated_at = inserted@planned_at,
      stringsAsFactors = FALSE
    )
  )

  matched <- graft_plan(store, records, provenance)
  changed <- records
  changed$Entity$preferred_name <- "Updated snapshot entity"
  updated <- graft_plan(store, changed, provenance)
  matched_execution <- graft:::commit_plan_execution(matched)$staged
  updated_execution <- graft:::commit_plan_execution(updated)$staged
  matched_payload <- jsonlite::fromJSON(
    matched_execution$rows$payload_json,
    simplifyVector = FALSE
  )
  updated_payload <- jsonlite::fromJSON(
    updated_execution$rows$payload_json,
    simplifyVector = FALSE
  )
  expected_created <- projection_coerce_timestamps(prior_created)[[1L]]
  expected_updated <- projection_coerce_timestamps(prior_updated)[[1L]]

  expect_identical(matched@changes$action, "match")
  expect_identical(updated@changes$action, "update")
  expect_identical(matched@changes$expected_revision_id, revision_id)
  expect_identical(updated@changes$expected_revision_id, revision_id)
  expect_identical(matched@changes$expected_revision_number, 1)
  expect_identical(updated@changes$expected_revision_number, 1)
  expect_identical(
    updated@changes$expected_content_digest,
    staged_row$content_digest
  )
  expect_equal(
    as.numeric(matched_execution$records$Entity$created_at),
    as.numeric(expected_created),
    tolerance = 1e-6
  )
  expect_equal(
    as.numeric(matched_execution$records$Entity$updated_at),
    as.numeric(expected_updated),
    tolerance = 1e-6
  )
  expect_equal(
    as.numeric(updated_execution$records$Entity$created_at),
    as.numeric(expected_created),
    tolerance = 1e-6
  )
  expect_identical(matched_payload$created_at, prior_created)
  expect_identical(matched_payload$updated_at, prior_updated)
  expect_identical(updated_payload$created_at, prior_created)
})

test_that("deleted heads retain identity ownership and require resurrection", {
  store <- local_ingest_store()
  records <- list(
    Entity = data.frame(
      id = test_graft_id("deleted-head"),
      preferred_name = "Deleted entity"
    )
  )
  provenance <- graft_provenance("deleted-head-test")
  initial <- graft_plan(store, records, provenance)
  row <- graft:::commit_plan_execution(initial)$staged$rows[1L, ]
  revision_id <- test_graft_id("deleted-head-revision")
  DBI::dbAppendTable(
    store$connection,
    "_graft_record_revisions",
    data.frame(
      revision_id = revision_id,
      record_id = row$record_id,
      class = row$class,
      batch_id = test_graft_id("deleted-head-batch"),
      schema_build_digest = initial@schema_build_digest,
      revision_number = 1,
      operation = "delete",
      payload_json = row$payload_json,
      content_digest = row$content_digest,
      changed_fields_json = row$changed_fields_json,
      prior_revision_id = NA_character_,
      recorded_at = initial@planned_at,
      commit_order = 1,
      stringsAsFactors = FALSE
    )
  )
  DBI::dbAppendTable(
    store$connection,
    "_graft_record_heads",
    data.frame(
      record_id = row$record_id,
      class = row$class,
      revision_id = revision_id,
      revision_number = 1,
      updated_at = initial@planned_at,
      stringsAsFactors = FALSE
    )
  )

  resurrection <- graft_plan(store, records, provenance)
  wrong_class <- graft_plan(
    store,
    list(Source = data.frame(id = row$record_id, title = "Wrong class")),
    provenance
  )
  missing_reference <- graft_plan(
    store,
    list(
      Claim = data.frame(
        id = test_graft_id("deleted-reference"),
        statement_text = "Deleted target",
        about = I(list(row$record_id))
      )
    ),
    provenance
  )

  expect_identical(resurrection@changes$action, "update")
  expect_identical(resurrection@changes$expected_revision_id, revision_id)
  expect_identical(resurrection@changes$expected_revision_number, 1)
  expect_setequal(wrong_class@issues$rule, "class_compatible_id")
  expect_setequal(missing_reference@issues$rule, "reference_exists")
})

test_that("replay checks static binding and exact plan identity", {
  store <- local_ingest_store()
  other_store <- local_ingest_store()
  provenance <- graft_provenance(
    "workflow",
    idempotency_key = "replay-boundary"
  )
  make_plan <- function(target_store, candidate) {
    metadata <- read_store_metadata(target_store$connection)
    heads <- empty_plan_changes()[
      c(
        "class",
        "record_id",
        "expected_revision_id",
        "expected_content_digest"
      )
    ]
    new_graft_commit_plan(
      source = "records",
      store_id = scalar_character(metadata$store_id),
      store_format_version = scalar_character(
        metadata$store_format_version
      ),
      schema_build_digest = scalar_character(metadata$active_build_digest),
      schema_structural_digest = scalar_character(
        metadata$active_structural_digest
      ),
      planned_at = commit_plan_snapshot_time(
        target_store$connection,
        metadata
      ),
      provenance = provenance,
      records = list(candidate = candidate),
      changes = empty_plan_changes(),
      issues = empty_plan_issues(),
      preconditions = list(heads = heads, source = list()),
      input_digest = graft_sha256(candidate, serialize = TRUE),
      execution = list(staged = list())
    )
  }
  seed_replay <- function(target_store, plan) {
    batch <- provenance_batch(plan@provenance, plan@plan_id)
    commit_order <- next_metadata_order(
      target_store$connection,
      "_graft_batches",
      "commit_order"
    )
    insert_started_batch(
      target_store$connection,
      batch,
      plan@planned_at,
      plan@schema_build_digest,
      commit_order
    )
    empty_counts <- stats::setNames(integer(), character())
    result <- new_kg_ingest_result(
      batch_id = plan@plan_id,
      inserted = empty_counts,
      updated = empty_counts,
      matched = empty_counts,
      observed = empty_counts
    )
    commit_batch(
      target_store$connection,
      batch,
      result,
      plan@planned_at
    )
  }
  plan <- make_plan(store, "accepted")
  seed_replay(store, plan)
  other_plan <- make_plan(other_store, "accepted elsewhere")
  seed_replay(other_store, other_plan)
  replay_condition <- NULL

  replay <- withCallingHandlers(
    graft_commit(store, plan),
    graft_batch_replay = function(condition) {
      replay_condition <<- condition
    }
  )
  collision <- catch_graft_ingest_condition(
    graft_commit(store, make_plan(store, "different"))
  )
  cross_store <- catch_graft_ingest_condition(
    graft_commit(other_store, plan)
  )
  time_tampered <- plan
  time_data <- commit_plan_data(time_tampered)
  time_data$planned_at <- time_data$planned_at + 1
  attr(time_tampered, ".data") <- time_data
  time_tamper <- catch_graft_ingest_condition(
    graft_commit(store, time_tampered)
  )

  expect_s3_class(replay_condition, "graft_batch_replay")
  expect_identical(replay$batch_id, plan@plan_id)
  expect_s3_class(collision, "graft_commit_plan_replay_conflict")
  expect_s3_class(cross_store, "graft_commit_plan_stale")
  expect_s3_class(time_tamper, "graft_commit_plan_tampered")
})

test_that("invalid input returns a non-committable plan", {
  store <- local_ingest_store()
  records <- list(Entity = valid_atomic_records()$Entity)
  records$Entity$preferred_name <- NA_character_

  plan <- graft_plan(
    store,
    records,
    graft_provenance("workflow")
  )
  condition <- catch_graft_ingest_condition(graft_commit(store, plan))

  expect_identical(plan@valid, FALSE)
  expect_identical(plan@issues$rule, "required")
  expect_s3_class(condition, "graft_commit_plan_invalid")
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_batches")),
    0L
  )
})

test_that("commit rejects stale identifier and origin registries", {
  identifier_store <- local_ingest_store()
  origin_store <- local_ingest_store()
  records <- list(
    Entity = data.frame(
      id = test_graft_id("registry-candidate"),
      preferred_name = "Registry candidate"
    )
  )
  provenance <- graft_provenance("registry-test")
  identifier_plan <- graft_plan(identifier_store, records, provenance)
  origin_plan <- graft_plan(origin_store, records, provenance)
  now <- as.POSIXct("2026-01-01", tz = "UTC")
  DBI::dbAppendTable(
    identifier_store$connection,
    "_graft_identifiers",
    data.frame(
      record_id = test_graft_id("registry-identifier"),
      class = "Entity",
      namespace = "cas",
      value = "50-00-0",
      normalized_value = "50-00-0",
      status = "primary",
      assigned_by = "fixture",
      confidence = 1,
      created_at = now,
      stringsAsFactors = FALSE
    )
  )
  DBI::dbAppendTable(
    origin_store$connection,
    "_graft_origins",
    data.frame(
      record_id = test_graft_id("registry-origin"),
      class = "Entity",
      producer = "registry-test",
      origin_key = "changed-origin",
      first_batch_id = test_graft_id("registry-origin-batch"),
      created_at = now,
      stringsAsFactors = FALSE
    )
  )

  identifier_condition <- catch_graft_ingest_condition(
    graft_commit(identifier_store, identifier_plan)
  )
  origin_condition <- catch_graft_ingest_condition(
    graft_commit(origin_store, origin_plan)
  )

  expect_s3_class(identifier_condition, "graft_commit_plan_stale")
  expect_s3_class(origin_condition, "graft_commit_plan_stale")
  expect_equal(
    nrow(DBI::dbReadTable(identifier_store$connection, "_graft_batches")),
    0L
  )
  expect_equal(
    nrow(DBI::dbReadTable(origin_store$connection, "_graft_batches")),
    0L
  )
})

test_that("commit head checks reject composite corruption", {
  cases <- c("revision_id", "class", "revision_number")
  conditions <- lapply(cases, function(case) {
    store <- local_ingest_store()
    records <- list(
      Entity = data.frame(
        id = test_graft_id(paste0("corrupt-", case)),
        preferred_name = "Original"
      )
    )
    initial <- graft_plan(store, records, graft_provenance("corruption-test"))
    row <- graft:::commit_plan_execution(initial)$staged$rows[1L, ]
    revision_id <- test_graft_id(paste0("corrupt-revision-", case))
    DBI::dbAppendTable(
      store$connection,
      "_graft_record_revisions",
      data.frame(
        revision_id = revision_id,
        record_id = row$record_id,
        class = row$class,
        batch_id = test_graft_id(paste0("corrupt-batch-", case)),
        schema_build_digest = initial@schema_build_digest,
        revision_number = 1,
        operation = "insert",
        payload_json = row$payload_json,
        content_digest = row$content_digest,
        changed_fields_json = row$changed_fields_json,
        prior_revision_id = NA_character_,
        recorded_at = initial@planned_at,
        commit_order = 1,
        stringsAsFactors = FALSE
      )
    )
    DBI::dbAppendTable(
      store$connection,
      "_graft_record_heads",
      data.frame(
        record_id = row$record_id,
        class = row$class,
        revision_id = revision_id,
        revision_number = 1,
        updated_at = initial@planned_at,
        stringsAsFactors = FALSE
      )
    )
    records$Entity$preferred_name <- "Reviewed"
    plan <- graft_plan(store, records, graft_provenance("corruption-test"))
    if (identical(case, "revision_id")) {
      DBI::dbExecute(
        store$connection,
        "UPDATE _graft_record_heads SET revision_id = ? WHERE record_id = ?",
        params = list(test_graft_id("dangling-revision"), row$record_id)
      )
    } else if (identical(case, "class")) {
      DBI::dbExecute(
        store$connection,
        "UPDATE _graft_record_heads SET class = ? WHERE record_id = ?",
        params = list("Source", row$record_id)
      )
    } else {
      DBI::dbExecute(
        store$connection,
        paste0(
          "UPDATE _graft_record_heads SET revision_number = ? ",
          "WHERE record_id = ?"
        ),
        params = list(2, row$record_id)
      )
    }
    catch_graft_ingest_condition(graft_commit(store, plan))
  })

  for (condition in conditions) {
    expect_s3_class(condition, "graft_commit_plan_stale")
  }
})

test_that("commit rejects a head created after an insert plan", {
  store <- local_ingest_store()
  records <- list(
    Entity = data.frame(
      id = test_graft_id("unexpected-head"),
      preferred_name = "Unexpected head"
    )
  )
  plan <- graft_plan(store, records, graft_provenance("unexpected-head"))
  row <- graft:::commit_plan_execution(plan)$staged$rows[1L, ]
  revision_id <- test_graft_id("unexpected-head-revision")
  DBI::dbAppendTable(
    store$connection,
    "_graft_record_revisions",
    data.frame(
      revision_id = revision_id,
      record_id = row$record_id,
      class = row$class,
      batch_id = test_graft_id("unexpected-head-batch"),
      schema_build_digest = plan@schema_build_digest,
      revision_number = 1,
      operation = "insert",
      payload_json = row$payload_json,
      content_digest = row$content_digest,
      changed_fields_json = row$changed_fields_json,
      prior_revision_id = NA_character_,
      recorded_at = plan@planned_at,
      commit_order = 1,
      stringsAsFactors = FALSE
    )
  )
  DBI::dbAppendTable(
    store$connection,
    "_graft_record_heads",
    data.frame(
      record_id = row$record_id,
      class = row$class,
      revision_id = revision_id,
      revision_number = 1,
      updated_at = plan@planned_at,
      stringsAsFactors = FALSE
    )
  )

  condition <- catch_graft_ingest_condition(graft_commit(store, plan))

  expect_s3_class(condition, "graft_commit_plan_stale")
})

test_that("commit accepts a prepared plan and preserves replay behavior", {
  store <- local_ingest_store()
  records <- list(Entity = valid_atomic_records()$Entity)
  provenance <- graft_provenance(
    "workflow",
    idempotency_key = "reviewed-change"
  )
  plan <- graft_plan(store, records, provenance)

  first <- graft_commit(store, plan)
  before <- nrow(DBI::dbReadTable(store$connection, "_graft_record_revisions"))
  replay_condition <- NULL
  replay <- withCallingHandlers(
    graft_commit(store, plan),
    graft_batch_replay = function(condition) {
      replay_condition <<- condition
    }
  )
  after <- nrow(DBI::dbReadTable(store$connection, "_graft_record_revisions"))

  expect_identical(first$inserted[["Entity"]], 1L)
  expect_s3_class(replay_condition, "graft_batch_replay")
  expect_identical(replay$batch_id, first$batch_id)
  expect_identical(replay$replay, TRUE)
  expect_identical(after, before)
})

test_that("commit rejects tampered and cross-store plans before writing", {
  first_store <- local_ingest_store()
  second_store <- local_ingest_store()
  records <- list(Entity = valid_atomic_records()$Entity)
  plan <- graft_plan(
    first_store,
    records,
    graft_provenance("workflow", idempotency_key = "guarded")
  )
  second_plan <- graft_plan(
    second_store,
    records,
    graft_provenance("workflow", idempotency_key = "guarded")
  )
  graft_commit(second_store, second_plan)

  tampered <- plan
  data <- graft:::commit_plan_data(tampered)
  data$source <- "okf"
  attr(tampered, ".data") <- data
  time_tampered <- plan
  time_data <- graft:::commit_plan_data(time_tampered)
  time_data$planned_at <- time_data$planned_at + 1
  attr(time_tampered, ".data") <- time_data
  tampered_condition <- catch_graft_ingest_condition(
    graft_commit(first_store, tampered)
  )
  time_tampered_condition <- catch_graft_ingest_condition(
    graft_commit(first_store, time_tampered)
  )
  cross_store_condition <- catch_graft_ingest_condition(
    graft_commit(second_store, plan)
  )

  expect_s3_class(tampered_condition, "graft_commit_plan_tampered")
  expect_s3_class(time_tampered_condition, "graft_commit_plan_tampered")
  expect_s3_class(cross_store_condition, "graft_commit_plan_stale")
  expect_equal(
    nrow(DBI::dbReadTable(first_store$connection, "_graft_batches")),
    0L
  )
  expect_equal(
    nrow(DBI::dbReadTable(second_store$connection, "_graft_batches")),
    1L
  )
})

test_that("commit rejects a reused idempotency key for a different plan", {
  store <- local_ingest_store()
  provenance <- graft_provenance(
    "workflow",
    idempotency_key = "collision"
  )
  records <- list(Entity = valid_atomic_records()$Entity)
  committed_plan <- graft_plan(store, records, provenance)
  graft_commit(store, committed_plan)
  changed <- records
  changed$Entity$preferred_name <- "Different candidate"
  colliding_plan <- graft_plan(store, changed, provenance)
  before_batches <- nrow(
    DBI::dbReadTable(store$connection, "_graft_batches")
  )
  before_revisions <- nrow(
    DBI::dbReadTable(store$connection, "_graft_record_revisions")
  )

  condition <- catch_graft_ingest_condition(
    graft_commit(store, colliding_plan)
  )

  expect_s3_class(condition, "graft_commit_plan_replay_conflict")
  expect_identical(condition$observed_batch_id, committed_plan@plan_id)
  expect_identical(condition$expected_batch_id, colliding_plan@plan_id)
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_batches")),
    before_batches
  )
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_revisions")),
    before_revisions
  )
})

test_that("commit rejects a stale expected record head", {
  store <- local_ingest_store()
  initial <- list(Entity = valid_atomic_records()$Entity)
  graft_ingest(
    store,
    initial,
    graft_provenance("workflow", idempotency_key = "initial")
  )
  proposed <- initial
  proposed$Entity$preferred_name <- "Reviewed name"
  stale_plan <- graft_plan(
    store,
    proposed,
    graft_provenance("workflow", idempotency_key = "stale")
  )
  intervening <- initial
  intervening$Entity$preferred_name <- "Intervening name"
  graft_ingest(
    store,
    intervening,
    graft_provenance("workflow", idempotency_key = "intervening")
  )
  before <- nrow(DBI::dbReadTable(store$connection, "_graft_batches"))

  condition <- catch_graft_ingest_condition(graft_commit(store, stale_plan))

  expect_s3_class(condition, "graft_commit_plan_stale")
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_batches")),
    before
  )
})

test_that("OKF review produces the ordinary commit-plan type", {
  fixture <- local_okf_store()
  bundle <- kg_sync_okf(fixture$store)
  entity_path <- okf_fixture_concept(
    bundle,
    "Entity",
    fixture$records$Entity$id
  )
  replace_okf_line(
    entity_path,
    "preferred_name: Polyethylene",
    "preferred_name: Reviewed polyethylene"
  )

  plan <- graft_review(
    fixture$store,
    provenance = graft_provenance(
      "human:reviewer",
      idempotency_key = "okf-reviewed"
    )
  )
  result <- graft_commit(fixture$store, plan)

  expect_s7_class(plan, graft:::GraftCommitPlan)
  expect_identical(plan@source, "okf")
  expect_identical(plan@changes$action, "update")
  expect_s3_class(result, "kg_ingest_result")
  expect_identical(
    kg_get(
      fixture$store,
      fixture$records$Entity$id
    )$record$preferred_name,
    "Reviewed polyethylene"
  )
})
