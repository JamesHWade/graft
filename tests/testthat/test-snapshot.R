test_that("graft_snapshot captures stable serializable boundaries", {
  fields <- c(
    "schema_version",
    "snapshot_id",
    "store_id",
    "store_format_version",
    "schema_build_digest",
    "commit_order",
    "batch_id",
    "committed_at",
    "history_complete"
  )
  schema <- graft_schema(tempest_manifest_path())
  store <- local_graft_ingest_store(schema = schema)

  empty <- graft_snapshot(store)

  expect_s7_class(empty, graft:::GraftSnapshot)
  expect_identical(S7::prop_names(empty), fields)
  expect_identical(names(graft:::snapshot_data(empty)), fields)
  expect_identical(empty@schema_version, 1L)
  expect_identical(empty@store_id, store@id)
  expect_identical(empty@store_format_version, graft_store_format_version)
  expect_identical(empty@schema_build_digest, schema@build_digest)
  expect_identical(empty@commit_order, 0)
  expect_identical(empty@batch_id, NA_character_)
  expect_identical(empty@committed_at, NA_character_)
  expect_identical(empty@history_complete, TRUE)
  expect_match(empty@snapshot_id, "^sha256:[0-9a-f]{64}$")
  expect_s7_class(graft_at(store, empty), graft:::GraftView)

  fixture <- retrieval_fixture_records()
  committed <- graft_ingest(
    store,
    fixture$records,
    graft_provenance(
      "snapshot-fixture",
      idempotency_key = "snapshot-fixture"
    )
  )
  latest <- DBI::dbGetQuery(
    graft_test_connection(store),
    paste(
      "SELECT batch_id, schema_build_digest, commit_order,",
      "strftime(committed_at, '%Y-%m-%dT%H:%M:%S.%fZ') AS committed_at",
      "FROM _graft_batches WHERE status = 'committed'",
      "ORDER BY commit_order DESC LIMIT 1"
    )
  )
  snapshot <- graft_snapshot(store)

  expect_identical(S7::prop_names(snapshot), fields)
  expect_identical(snapshot@schema_version, 1L)
  expect_identical(snapshot@store_id, store@id)
  expect_identical(snapshot@store_format_version, graft_store_format_version)
  expect_identical(
    snapshot@schema_build_digest,
    latest$schema_build_digest[[1L]]
  )
  expect_identical(snapshot@commit_order, as.numeric(latest$commit_order[[1L]]))
  expect_identical(snapshot@batch_id, committed$batch_id)
  expect_identical(snapshot@committed_at, latest$committed_at[[1L]])
  expect_identical(snapshot@history_complete, TRUE)
  expect_match(snapshot@snapshot_id, "^sha256:[0-9a-f]{64}$")
  expect_identical(
    graft_snapshot(store)@snapshot_id,
    snapshot@snapshot_id
  )
  expect_identical(
    intersect(S7::prop_names(snapshot), c("path", "connection")),
    character()
  )

  restored <- unserialize(serialize(snapshot, NULL))
  expect_s7_class(restored, graft:::GraftSnapshot)
  expect_identical(S7::props(restored), S7::props(snapshot))
  expect_s7_class(graft_at(store, restored), graft:::GraftView)
})

test_that("snapshot timestamps preserve exact DuckDB microseconds", {
  local <- local_retrieval_store()
  DBI::dbExecute(
    local$connection,
    paste(
      "UPDATE _graft_batches SET committed_at = CAST(? AS TIMESTAMP)",
      "WHERE status = 'committed'"
    ),
    params = list("2026-01-01 00:00:59.000001")
  )
  snapshot <- graft_snapshot(local$store)

  expect_identical(
    snapshot@committed_at,
    "2026-01-01T00:00:59.000001Z"
  )

  DBI::dbExecute(
    local$connection,
    paste(
      "UPDATE _graft_batches SET committed_at = CAST(? AS TIMESTAMP)",
      "WHERE status = 'committed'"
    ),
    params = list("2026-01-01 00:00:59.000002")
  )
  condition <- catch_graft_ingest_condition(graft_at(local$store, snapshot))

  expect_s3_class(condition, "graft_snapshot_boundary_error")
  expect_s3_class(condition, "graft_snapshot_error")
})

test_that("snapshot tampering fails before store mapping", {
  local <- local_retrieval_store()
  tampered <- graft_snapshot(local$store)
  data <- snapshot_data(tampered)
  data$batch_id <- paste0(data$batch_id, "-tampered")
  attr(tampered, ".data") <- data

  condition <- catch_graft_ingest_condition(graft_at(local$store, tampered))

  expect_s3_class(condition, "graft_snapshot_tampered")
  expect_s3_class(condition, "graft_snapshot_error")
})

test_that("graft_at validates every persisted snapshot mapping field", {
  local <- local_retrieval_store()
  snapshot <- graft_snapshot(local$store)
  snapshot_with <- function(...) {
    data <- snapshot_data(snapshot)
    args <- data[c(
      "store_id",
      "store_format_version",
      "schema_build_digest",
      "commit_order",
      "batch_id",
      "committed_at",
      "history_complete"
    )]
    args <- utils::modifyList(args, list(...))
    do.call(new_graft_snapshot, args)
  }

  format_condition <- catch_graft_ingest_condition(graft_at(
    local$store,
    snapshot_with(store_format_version = "2.0.0")
  ))
  history_condition <- catch_graft_ingest_condition(graft_at(
    local$store,
    snapshot_with(history_complete = FALSE)
  ))
  batch_condition <- catch_graft_ingest_condition(graft_at(
    local$store,
    snapshot_with(batch_id = paste0(snapshot@batch_id, "-other"))
  ))
  time_condition <- catch_graft_ingest_condition(graft_at(
    local$store,
    snapshot_with(committed_at = "2000-01-01T00:00:00.000000Z")
  ))

  expect_s3_class(format_condition, "graft_snapshot_store_mismatch")
  expect_s3_class(history_condition, "graft_snapshot_store_mismatch")
  expect_s3_class(batch_condition, "graft_snapshot_boundary_error")
  expect_s3_class(time_condition, "graft_snapshot_boundary_error")
})

test_that("view and snapshot backend validators reject malformed state", {
  local <- local_retrieval_store()
  view <- graft_at(local$store, graft_snapshot(local$store))
  malformed_view <- view
  state <- graft_view_state(malformed_view)
  state$schema <- NULL
  attr(malformed_view, ".state") <- state

  view_condition <- catch_graft_ingest_condition(
    as_graft_view(malformed_view, "view")
  )
  backend <- as_graft_read_store_internal(view)
  expect_identical(is_graft_snapshot_backend(backend), TRUE)
  backend$owns_connection <- TRUE

  expect_s3_class(view_condition, "graft_snapshot_invalid")
  expect_s3_class(view_condition, "graft_snapshot_error")
  expect_identical(is_graft_snapshot_backend(backend), FALSE)
  expect_null(snapshot_backend_data(backend))
})

test_that("snapshot views follow source connection ownership", {
  local <- local_retrieval_store()
  owned_connection <- local$connection
  owned_view <- graft_at(local$store, graft_snapshot(local$store))
  graft_close(local$store)
  owned_condition <- catch_graft_ingest_condition(graft_get(
    owned_view,
    local$ids$entity,
    include = character()
  ))

  expect_s3_class(owned_condition, "graft_backend_error")
  expect_identical(DBI::dbIsValid(owned_connection), FALSE)

  connection <- DBI::dbConnect(
    duckdb::duckdb(shared_home = FALSE),
    dbdir = ":memory:"
  )
  withr::defer(DBI::dbDisconnect(connection, shutdown = TRUE))
  schema <- graft_schema(tempest_manifest_path())
  supplied <- graft_open(
    schema,
    connection = connection,
    okf = "disabled"
  )
  supplied_view <- graft_at(supplied, graft_snapshot(supplied))
  graft_close(supplied)
  supplied_condition <- catch_graft_ingest_condition(
    graft_find(supplied_view, "knowledge")
  )

  expect_s3_class(supplied_condition, "graft_backend_error")
  expect_identical(DBI::dbIsValid(connection), TRUE)
})

test_that("snapshot views keep every read pinned after later changes", {
  local <- local_retrieval_store()
  fixture <- retrieval_fixture_records()
  snapshot <- graft_snapshot(local$store)
  view <- graft_at(local$store, snapshot)

  entity <- fixture$records$Entity[
    fixture$records$Entity$id == local$ids$entity,
    ,
    drop = FALSE
  ]
  entity$cas_number <- "9002-88-5"
  claim <- fixture$records$Claim[
    fixture$records$Claim$id == local$ids$active_claim,
    ,
    drop = FALSE
  ]
  claim$statement_text <- "Polyethylene remains flexible after aging."
  semantic <- fixture$records$SemanticClaim
  semantic$predicate <- "schema:connectedTo"

  graft_ingest(
    local$store,
    list(Entity = entity, Claim = claim, SemanticClaim = semantic),
    graft_provenance(
      "snapshot-update",
      idempotency_key = "snapshot-update"
    )
  )

  live <- graft_get(
    local$store,
    local$ids$active_claim,
    include = character()
  )
  pinned <- graft_get(view, local$ids$active_claim, include = character())
  live_find <- graft_find(local$store, "flexible after aging")
  pinned_find <- graft_find(view, "remains durable")
  pinned_new_find <- graft_find(view, "flexible after aging")
  live_claims <- graft_query(
    local$store,
    "claims",
    list(id = local$ids$entity)
  )
  pinned_claims <- graft_query(
    view,
    "claims",
    list(id = local$ids$entity)
  )
  live_history <- graft_history(local$store, local$ids$active_claim)
  pinned_history <- graft_history(view, local$ids$active_claim)
  live_alias <- graft_query(
    local$store,
    "lookup",
    list(namespace = "cas", value = "9002-88-5", class = "Entity")
  )
  pinned_alias <- graft_query(
    view,
    "lookup",
    list(namespace = "cas", value = "9002-88-5", class = "Entity")
  )
  live_graph <- graft_query(
    local$store,
    "neighbors",
    list(
      id = local$ids$entity,
      direction = "out",
      projection = "semantic"
    )
  )
  pinned_graph <- graft_query(
    view,
    "neighbors",
    list(
      id = local$ids$entity,
      direction = "out",
      projection = "semantic"
    )
  )
  tool_result <- graft_tools(view)$graft_get(
    id = local$ids$active_claim,
    include = character()
  )

  expect_identical(
    live$record$statement_text,
    "Polyethylene remains flexible after aging."
  )
  expect_identical(
    pinned$record$statement_text,
    "Polyethylene remains durable."
  )
  expect_in(local$ids$active_claim, live_find$id)
  expect_in(local$ids$active_claim, pinned_find$id)
  expect_equal(nrow(pinned_new_find), 0L)
  expect_identical(
    live_claims$record[[match(
      local$ids$active_claim,
      live_claims$id
    )]]$statement_text,
    "Polyethylene remains flexible after aging."
  )
  expect_identical(
    pinned_claims$record[[match(
      local$ids$active_claim,
      pinned_claims$id
    )]]$statement_text,
    "Polyethylene remains durable."
  )
  expect_equal(nrow(live_history), 2L)
  expect_equal(nrow(pinned_history), 1L)
  expect_identical(
    attr(pinned_history, "as_of_commit_order"),
    snapshot@commit_order
  )
  expect_identical(live_alias$record_id, local$ids$entity)
  expect_equal(nrow(pinned_alias), 0L)
  expect_identical(live_graph$edges$predicate, "schema:connectedTo")
  expect_identical(pinned_graph$edges$predicate, "schema:relatedTo")
  expect_identical(
    tool_result$result$record$statement_text,
    "Polyethylene remains durable."
  )
  expect_identical(
    identical(graft_snapshot(local$store)@snapshot_id, snapshot@snapshot_id),
    FALSE
  )
})

test_that("snapshot graph labels match live graph slot eligibility", {
  dictionary <- jsonlite::read_json(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  table_names <- vapply(dictionary$tables, \(table) table$name, character(1))
  organization <- match("organization", table_names)
  column_names <- vapply(
    dictionary$tables[[organization]]$columns,
    \(column) column$name,
    character(1)
  )
  name <- match("name", column_names)
  dictionary$tables[[organization]]$columns[[name]]$type <- "list(string)"
  path <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(
    dictionary,
    path,
    auto_unbox = TRUE,
    null = "null",
    pretty = TRUE
  )
  store <- local_graft_ingest_store(schema = graft_schema(path))
  record_id <- "org:graph-label"
  graft_ingest(
    store,
    list(
      organization = data.frame(
        id = record_id,
        name = I(list(c("Alpha", "Beta"))),
        check.names = FALSE
      )
    ),
    graft_provenance(
      "snapshot-graph-label",
      idempotency_key = "snapshot-graph-label"
    )
  )
  view <- graft_at(store, graft_snapshot(store))

  live <- graft_query(store, "neighbors", list(id = record_id))
  pinned <- graft_query(view, "neighbors", list(id = record_id))

  expect_identical(live$nodes$label, NA_character_)
  expect_identical(pinned$nodes, live$nodes)
})

test_that("snapshot graph labels use live DuckDB scalar casts", {
  graph_label_nodes <- function(type, value, example) {
    dictionary <- jsonlite::read_json(
      data_dict_personinfo_export_path(),
      simplifyVector = FALSE
    )
    table_names <- vapply(dictionary$tables, \(table) table$name, character(1))
    organization <- match("organization", table_names)
    column_names <- vapply(
      dictionary$tables[[organization]]$columns,
      \(column) column$name,
      character(1)
    )
    name <- match("name", column_names)
    dictionary$tables[[organization]]$columns[[name]]$type <- type
    dictionary$tables[[organization]]$columns[[name]]$examples <- list(
      example
    )
    path <- withr::local_tempfile(
      fileext = ".json",
      .local_envir = parent.frame()
    )
    jsonlite::write_json(
      dictionary,
      path,
      auto_unbox = TRUE,
      null = "null",
      pretty = TRUE
    )
    store <- local_graft_ingest_store(
      schema = graft_schema(path),
      env = parent.frame()
    )
    record_id <- paste0("org:", type, "-label")
    graft_ingest(
      store,
      list(organization = data.frame(id = record_id, name = value)),
      graft_provenance(
        paste0("snapshot-", type, "-label"),
        idempotency_key = paste0("snapshot-", type, "-label")
      )
    )
    view <- graft_at(store, graft_snapshot(store))
    list(
      live = graft_query(store, "neighbors", list(id = record_id))$nodes,
      pinned = graft_query(view, "neighbors", list(id = record_id))$nodes
    )
  }

  boolean <- graph_label_nodes("boolean", TRUE, TRUE)
  expect_identical(boolean$live$label, "true")
  expect_identical(boolean$pinned, boolean$live)

  double <- graph_label_nodes("number", 1234.5, 1234.5)
  expect_identical(double$live$label, "1234.5")
  expect_identical(double$pinned, double$live)

  timestamp <- graph_label_nodes(
    "datetime",
    as.POSIXct("2026-08-15 12:34:56.125", tz = "UTC"),
    "2026-08-15T12:34:56.125Z"
  )
  expect_identical(timestamp$live$label, "2026-08-15 12:34:56.125")
  expect_identical(timestamp$pinned, timestamp$live)
})

test_that("view history boundaries and integrity remain pinned", {
  store <- local_graft_ingest_store()
  record_id <- test_graft_id("snapshot-history-boundary")
  record <- data.frame(id = record_id, preferred_name = "First")
  first <- graft_ingest(
    store,
    list(Entity = record),
    graft_provenance("snapshot-history", idempotency_key = "history-first")
  )
  record$preferred_name <- "Second"
  second <- graft_ingest(
    store,
    list(Entity = record),
    graft_provenance("snapshot-history", idempotency_key = "history-second")
  )
  snapshot <- graft_snapshot(store)
  view <- graft_at(store, snapshot)
  record$preferred_name <- "Third"
  third <- graft_ingest(
    store,
    list(Entity = record),
    graft_provenance("snapshot-history", idempotency_key = "history-third")
  )

  earlier <- graft_history(view, record_id, as_of = first$batch_id)
  pinned <- graft_history(view, record_id, as_of = second$batch_id)
  later <- catch_graft_ingest_condition(
    graft_history(view, record_id, as_of = third$batch_id)
  )
  integrity <- catch_graft_ingest_condition(
    graft_query(view, "integrity")
  )

  expect_identical(earlier$record[[1L]]$preferred_name, "First")
  expect_identical(nrow(pinned), 2L)
  expect_identical(pinned$record[[1L]]$preferred_name, "Second")
  expect_s3_class(later, "graft_snapshot_boundary_error")
  expect_s3_class(later, "graft_history_boundary_error")
  expect_s3_class(integrity, "graft_snapshot_boundary_error")
})

test_that("mutation APIs reject GraftView", {
  local <- local_retrieval_store()
  view <- graft_at(local$store, graft_snapshot(local$store))
  records <- list(
    Entity = data.frame(
      id = test_graft_id("view-mutation"),
      preferred_name = "View mutation"
    )
  )
  provenance <- graft_provenance(
    "view-mutation",
    idempotency_key = "view-mutation"
  )
  plan <- graft_plan(local$store, records, provenance)
  before <- DBI::dbGetQuery(
    local$connection,
    "SELECT COUNT(*) AS batches FROM _graft_batches"
  )

  plan_error <- catch_graft_ingest_condition(
    graft_plan(view, records, provenance)
  )
  commit_error <- catch_graft_ingest_condition(graft_commit(view, plan))
  ingest_error <- catch_graft_ingest_condition(
    graft_ingest(view, records, provenance)
  )
  after <- DBI::dbGetQuery(
    local$connection,
    "SELECT COUNT(*) AS batches FROM _graft_batches"
  )

  expect_s3_class(plan_error, "graft_backend_error")
  expect_s3_class(commit_error, "graft_backend_error")
  expect_s3_class(ingest_error, "graft_backend_error")
  expect_identical(before, after)
})

test_that("graft_at rejects snapshots from another store", {
  first <- local_retrieval_store()
  second <- local_retrieval_store()
  snapshot <- graft_snapshot(first$store)

  condition <- catch_graft_ingest_condition(
    graft_at(second$store, snapshot)
  )

  expect_s3_class(condition, "graft_snapshot_store_mismatch")
  expect_s3_class(condition, "graft_snapshot_error")
  expect_snapshot(cat(conditionMessage(condition), "\n", sep = ""))
})

test_that("graft_at rejects a valid future boundary from the same store", {
  directory <- withr::local_tempdir()
  current_path <- file.path(directory, "current.duckdb")
  stale_path <- file.path(directory, "stale.duckdb")
  schema <- graft_schema(tempest_manifest_path())
  record_id <- test_graft_id("future-boundary")
  first <- graft_open(schema, current_path, okf = "disabled")
  withr::defer(if (!first@closed) graft_close(first))
  graft_ingest(
    first,
    list(
      Entity = data.frame(id = record_id, preferred_name = "Before")
    ),
    graft_provenance("future-boundary", idempotency_key = "future-before")
  )
  graft_close(first)
  expect_identical(file.copy(current_path, stale_path), TRUE)

  current <- graft_open(schema, current_path, okf = "disabled")
  withr::defer(if (!current@closed) graft_close(current))
  graft_ingest(
    current,
    list(
      Entity = data.frame(id = record_id, preferred_name = "After")
    ),
    graft_provenance("future-boundary", idempotency_key = "future-after")
  )
  future <- graft_snapshot(current)
  graft_close(current)

  stale <- graft_open(schema, stale_path, okf = "disabled")
  withr::defer(graft_close(stale))
  condition <- catch_graft_ingest_condition(graft_at(stale, future))

  expect_identical(stale@id, future@store_id)
  expect_s3_class(condition, "graft_snapshot_boundary_error")
  expect_s3_class(condition, "graft_snapshot_error")
  expect_snapshot(cat(conditionMessage(condition), "\n", sep = ""))
})

test_that("graft_at requires its historical schema metadata", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema <- graft_schema(tempest_manifest_path())
  record_id <- test_graft_id("historical-schema")
  store <- graft_open(schema, path, okf = "disabled")
  withr::defer(if (!store@closed) graft_close(store))
  graft_ingest(
    store,
    list(
      Entity = data.frame(id = record_id, preferred_name = "Schema one")
    ),
    graft_provenance("historical-schema", idempotency_key = "schema-one")
  )
  snapshot <- graft_snapshot(store)
  graft_close(store)

  rebuilt <- as_graft_schema_internal(schema)
  rebuilt$manifest$schema$source_files[[1L]]$content_digest <-
    graft_sha256("snapshot schema rebuild")
  rebuilt$manifest$fingerprints$source_digest <- graft_linkml_source_digest(
    rebuilt$manifest$schema$source_files
  )
  rebuilt$manifest$fingerprints$build_digest <- manifest_build_digest(
    rebuilt$manifest
  )
  rebuilt <- new_graft_schema(rebuilt)
  reopened <- graft_open(rebuilt, path, okf = "disabled")
  withr::defer(graft_close(reopened))
  connection <- graft_test_connection(reopened)
  DBI::dbExecute(
    connection,
    "DELETE FROM _graft_schema_versions WHERE build_digest = ?",
    params = list(snapshot@schema_build_digest)
  )

  condition <- catch_graft_ingest_condition(graft_at(reopened, snapshot))

  expect_s3_class(condition, "graft_snapshot_schema_error")
  expect_s3_class(condition, "graft_snapshot_error")
  expect_snapshot(cat(conditionMessage(condition), "\n", sep = ""))
})
