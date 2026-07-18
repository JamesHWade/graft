test_that("Tempest artifact-store construction requires Tempest", {
  store <- local_ingest_store()
  local_mocked_bindings(tempest_public_api = \() NULL)

  condition <- tryCatch(
    tempest_artifact_store_graft(store),
    graft_error = identity
  )

  expect_s3_class(condition, "graft_tempest_dependency_error")
  expect_identical(condition$package, "tempest")
})

test_that("current Tempest API is rejected with actionable requirements", {
  store <- local_ingest_store()
  exports <- c(
    "tempest_artifact",
    "tempest_artifact_catalog",
    "tempest_artifact_catalog_restore",
    "tempest_artifact_store"
  )
  local_mocked_bindings(
    tempest_public_api = \() {
      list(
        version = "0.1.0",
        exports = exports
      )
    }
  )
  before <- vapply(
    DBI::dbListTables(store$connection),
    \(.x) nrow(DBI::dbReadTable(store$connection, .x)),
    integer(1)
  )

  condition <- tryCatch(
    tempest_artifact_store_graft(store),
    graft_error = identity
  )
  after <- vapply(
    DBI::dbListTables(store$connection),
    \(.x) nrow(DBI::dbReadTable(store$connection, .x)),
    integer(1)
  )

  expect_s3_class(
    condition,
    "graft_tempest_artifact_store_unsupported"
  )
  expect_identical(condition$tempest_version, "0.1.0")
  expect_identical(condition$tempest_exports, exports)
  expect_length(condition$upstream_requirements, 3L)
  expect_match(
    conditionMessage(condition),
    "complete `TempestDeliverableSpec`",
    fixed = TRUE
  )
  expect_identical(after, before)
})

test_that("Tempest handoff commits one stable run batch", {
  store <- local_ingest_store()
  records <- valid_atomic_records()

  result <- kg_ingest_tempest_records(
    store,
    run_id = "run-001",
    records = records,
    producer_version = "0.1.0"
  )
  batches <- DBI::dbReadTable(store$connection, "_graft_batches")
  metadata <- jsonlite::fromJSON(
    batches$metadata_json[[1L]],
    simplifyVector = FALSE
  )

  expect_s3_class(result, "kg_ingest_result")
  expect_identical(batches$producer, "tempest")
  expect_identical(batches$producer_version, "0.1.0")
  expect_identical(batches$source_run_id, "run-001")
  expect_identical(batches$idempotency_key, "run-001")
  expect_identical(
    metadata$metadata$graft_tempest$run_id,
    "run-001"
  )
  expect_null(metadata$metadata$graft_tempest$stage)
})

test_that("Tempest run and stage replay is idempotent", {
  store <- local_ingest_store()
  records <- list(Entity = valid_atomic_records()$Entity)

  first <- kg_ingest_tempest_records(
    store,
    run_id = "run-replay",
    records = records,
    stage = "search"
  )
  before <- vapply(
    DBI::dbListTables(store$connection),
    \(.x) nrow(DBI::dbReadTable(store$connection, .x)),
    integer(1)
  )
  replay_condition <- NULL
  replay <- withCallingHandlers(
    kg_ingest_tempest_records(
      store,
      run_id = "run-replay",
      records = records,
      stage = "search"
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
  batches <- DBI::dbReadTable(store$connection, "_graft_batches")

  expect_s3_class(replay_condition, "graft_batch_replay")
  expect_identical(replay$batch_id, first$batch_id)
  expect_identical(replay$replay, TRUE)
  expect_identical(batches$idempotency_key, "run-replay:search")
  expect_identical(after, before)
})

test_that("Tempest stages have independent idempotency boundaries", {
  store <- local_ingest_store()
  records <- list(Entity = valid_atomic_records()$Entity)

  kg_ingest_tempest_records(
    store,
    run_id = "run-stages",
    records = records,
    stage = "search"
  )
  kg_ingest_tempest_records(
    store,
    run_id = "run-stages",
    records = records,
    stage = "synthesize"
  )
  batches <- DBI::dbReadTable(store$connection, "_graft_batches")

  expect_setequal(
    batches$idempotency_key,
    c("run-stages:search", "run-stages:synthesize")
  )
  expect_identical(batches$source_run_id, rep("run-stages", 2L))
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_record_observations")),
    2L
  )
})

test_that("Tempest handoff validates run and stage identifiers", {
  store <- local_ingest_store()
  records <- list(Entity = valid_atomic_records()$Entity)

  run_condition <- tryCatch(
    kg_ingest_tempest_records(store, "", records),
    graft_error = identity
  )
  stage_condition <- tryCatch(
    kg_ingest_tempest_records(store, "run", records, stage = ""),
    graft_error = identity
  )

  expect_s3_class(run_condition, "graft_validation_error")
  expect_identical(run_condition$field, "run_id")
  expect_s3_class(stage_condition, "graft_validation_error")
  expect_identical(stage_condition$field, "stage")
})
