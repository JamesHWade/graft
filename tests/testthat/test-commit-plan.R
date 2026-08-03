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
