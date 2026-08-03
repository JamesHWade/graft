test_that("BR-21 current retrieval uses the ledger and active sensitivity", {
  schema <- modified_ingest_schema(
    as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  )
  schema$manifest$classes$Entity$slots$description$sensitive <- TRUE
  schema <- refresh_schema_structural_digest(schema)
  fixture <- retrieval_fixture_records()
  store <- local_graft_ingest_store(schema = schema)
  connection <- as_graft_store_internal(store)$connection
  graft_ingest(
    store,
    fixture$records,
    graft_provenance(
      "retrieval-sensitive",
      idempotency_key = "retrieval-sensitive"
    )
  )

  current <- graft_get(store, fixture$ids$entity, include = character())
  history <- graft_history(store, fixture$ids$entity, limit = 1L)

  expect_type(current, "list")
  expect_identical(current$class, "Entity")
  expect_identical(current$record$preferred_name, "Polyethylene")
  expect_length(intersect("description", names(current$record)), 0L)
  expect_length(intersect("description", names(history$record[[1L]])), 0L)

  DBI::dbExecute(
    connection,
    paste0(
      "UPDATE ",
      quote_identifier(connection, "_graft_projection_entity"),
      " SET preferred_name = 'Projection lie'"
    )
  )

  authoritative <- graft_get(
    store,
    fixture$ids$entity,
    include = character()
  )
  expect_identical(authoritative$record$preferred_name, "Polyethylene")
})

test_that("BR-22 history respects deterministic commit boundaries", {
  fixture <- retrieval_fixture_records()
  local <- local_retrieval_store()
  first <- graft_history(local$store, local$ids$entity, limit = 1L)
  update <- fixture$records$Entity[1L, , drop = FALSE]
  update$preferred_name <- "Polyethylene revised"
  graft_ingest(
    local$store,
    list(Entity = update),
    graft_provenance(
      "retrieval-update",
      idempotency_key = "retrieval-update"
    )
  )

  current <- graft_get(local$store, local$ids$entity, include = character())
  historical <- graft_history(
    local$store,
    local$ids$entity,
    as_of = first$batch_id[[1L]],
    limit = 1L
  )
  latest <- graft_history(local$store, local$ids$entity, limit = 1L)

  expect_identical(current$record$preferred_name, "Polyethylene revised")
  expect_identical(historical$record[[1L]]$preferred_name, "Polyethylene")
  expect_identical(latest$record[[1L]]$preferred_name, "Polyethylene revised")
  expect_identical(attr(historical, "as_of_batch_id"), first$batch_id[[1L]])

  original_schemas <- historical_schemas
  schema_queries <- 0L
  local_mocked_bindings(
    historical_schemas = function(...) {
      schema_queries <<- schema_queries + 1L
      original_schemas(...)
    }
  )
  full <- graft_history(local$store, local$ids$entity, limit = 100L)
  expect_equal(nrow(full), 2L)
  expect_identical(schema_queries, 1L)
})

test_that("BR-23 retrieval is bounded, deterministic, and not row-wise", {
  local <- local_retrieval_store()
  first <- graft_find(local$store, "poly", limit = 1L)
  second <- graft_find(local$store, "poly", limit = 1L)

  expect_identical(first, second)
  expect_equal(nrow(first), 1L)
  expect_identical(attr(first, "truncated"), TRUE)
  expect_identical(attr(first, "limit"), 1L)

  original_query <- retrieval_query
  query_count <- 0L
  local_mocked_bindings(
    retrieval_query = function(...) {
      query_count <<- query_count + 1L
      original_query(...)
    }
  )
  graft_find(local$store, "poly", limit = 100L)
  expect_identical(query_count, 2L)

  cap <- catch_graft_ingest_condition(
    graft_find(local$store, "poly", limit = 1001L)
  )
  arbitrary <- catch_graft_ingest_condition(
    graft_query(local$store, "claims", list(id = local$ids$entity, sql = "x"))
  )
  expect_s3_class(cap, "graft_limit_error")
  expect_s3_class(arbitrary, "graft_validation_error")
})

test_that("BR-24 graph queries preserve semantic and provenance meaning", {
  local <- local_retrieval_store()
  semantic <- graft_query(
    local$store,
    "neighbors",
    list(
      id = local$ids$entity,
      predicate = "schema:relatedTo",
      direction = "out",
      projection = "semantic"
    )
  )
  provenance <- graft_query(
    local$store,
    "neighbors",
    list(
      id = local$ids$active_claim,
      predicate = "https://w3id.org/graft/about",
      direction = "out",
      projection = "provenance"
    )
  )
  path <- graft_query(
    local$store,
    "traverse",
    list(
      from = local$ids$active_claim,
      via = c(
        "https://w3id.org/graft/evidence",
        "https://w3id.org/graft/source_id"
      ),
      projection = "provenance"
    )
  )

  expect_type(semantic, "list")
  expect_identical(semantic$edges$subject, local$ids$entity)
  expect_identical(semantic$edges$object, local$ids$other_entity)
  expect_identical(semantic$edges$predicate, "schema:relatedTo")
  expect_identical(provenance$edges$object, local$ids$entity)
  expect_in(local$ids$source, path$nodes$id)
})

test_that("BR-25 evidence preserves exact source and locator details", {
  local <- local_retrieval_store()
  evidence <- graft_query(
    local$store,
    "evidence",
    list(statement_id = local$ids$active_claim),
    limit = 10L
  )

  expect_equal(nrow(evidence), 1L)
  expect_identical(evidence$source_id, local$ids$source)
  expect_identical(
    evidence$source_uri,
    "https://example.com/reports/Result?Study=ABC"
  )
  expect_identical(evidence$locator_type, "page")
  expect_identical(evidence$locator_value, "p. 4")
  expect_identical(evidence$page_start, 4)
  expect_identical(evidence$page_end, 4)
  expect_identical(
    evidence$excerpt,
    "Polyethylene retained its strength."
  )
})

test_that("BR-26 integrity distinguishes authority from stale projections", {
  local <- local_retrieval_store()
  DBI::dbExecute(
    local$connection,
    paste0(
      "UPDATE ",
      quote_identifier(local$connection, "_graft_projection_entity"),
      " SET preferred_name = 'Projection lie'"
    )
  )

  current <- graft_get(local$store, local$ids$entity, include = character())
  issues <- graft_query(
    local$store,
    "integrity",
    list(projections = TRUE),
    limit = 10L
  )
  graph_error <- catch_graft_ingest_condition(
    graft_query(
      local$store,
      "neighbors",
      list(id = local$ids$entity, projection = "semantic")
    )
  )

  expect_identical(current$record$preferred_name, "Polyethylene")
  expect_in("stale_projection", issues$issue)
  expect_s3_class(graph_error, "graft_backend_error")

  broken <- local_retrieval_store()
  DBI::dbExecute(
    broken$connection,
    paste0(
      "DELETE FROM ",
      quote_identifier(broken$connection, "_graft_schema_versions")
    )
  )
  missing_schema <- graft_query(
    broken$store,
    "integrity",
    list(projections = FALSE),
    limit = 10L
  )
  ledger_error <- catch_graft_ingest_condition(
    graft_get(broken$store, broken$ids$entity, include = character())
  )
  expect_in("orphan_revision_schema", missing_schema$issue)
  expect_s3_class(ledger_error, "graft_backend_error")
  expect_match(conditionMessage(ledger_error), "ledger|schema")

  identity <- local_retrieval_store()
  identifier <- DBI::dbGetQuery(
    identity$connection,
    "SELECT * FROM _graft_identifiers ORDER BY record_id LIMIT 1"
  )
  identifier$record_id <- test_graft_id("missing-identity")
  identifier$value <- "missing-identity"
  identifier$normalized_value <- "missing-identity"
  DBI::dbAppendTable(
    identity$connection,
    "_graft_identifiers",
    identifier
  )
  identity_issues <- graft_query(
    identity$store,
    "integrity",
    list(projections = FALSE),
    limit = 10L
  )
  expect_in("missing_identifier_record", identity_issues$issue)

  chain <- local_retrieval_store()
  update <- retrieval_fixture_records()$records$Entity[1L, , drop = FALSE]
  update$preferred_name <- "Chain update"
  graft_ingest(
    chain$store,
    list(Entity = update),
    graft_provenance("chain-update", idempotency_key = "chain-update")
  )
  DBI::dbExecute(
    chain$connection,
    paste0(
      "UPDATE _graft_record_revisions SET prior_revision_id = ",
      "'graft:00000000000000000000000000' ",
      "WHERE record_id = ? AND revision_number = 2"
    ),
    params = list(chain$ids$entity)
  )
  chain_issues <- graft_query(
    chain$store,
    "integrity",
    list(projections = FALSE),
    limit = 10L
  )
  expect_in("revision_chain_mismatch", chain_issues$issue)
})

test_that("BR-26 authoritative ledger corruption blocks public reads", {
  local <- local_retrieval_store()
  revisions <- DBI::dbReadTable(
    local$connection,
    "_graft_record_revisions"
  )
  target <- revisions[revisions$record_id == local$ids$entity, , drop = FALSE]
  batch <- DBI::dbReadTable(local$connection, "_graft_batches")
  batch_id <- target$batch_id[[1L]]

  DBI::dbExecute(
    local$connection,
    "UPDATE _graft_batches SET status = 'started' WHERE batch_id = ?",
    params = list(batch_id)
  )
  uncommitted <- graft_query(
    local$store,
    "integrity",
    list(projections = FALSE),
    limit = 100L
  )
  expect_in("orphan_revision_batch", uncommitted$issue)
  DBI::dbExecute(
    local$connection,
    "UPDATE _graft_batches SET status = 'committed' WHERE batch_id = ?",
    params = list(batch_id)
  )

  DBI::dbExecute(
    local$connection,
    paste0(
      "UPDATE _graft_record_revisions SET commit_order = commit_order + 1 ",
      "WHERE revision_id = ?"
    ),
    params = list(target$revision_id[[1L]])
  )
  metadata <- graft_query(
    local$store,
    "integrity",
    list(projections = FALSE),
    limit = 100L
  )
  expect_in("revision_commit_order_mismatch", metadata$issue)
  DBI::dbExecute(
    local$connection,
    "UPDATE _graft_record_revisions SET commit_order = ? WHERE revision_id = ?",
    params = list(target$commit_order[[1L]], target$revision_id[[1L]])
  )

  DBI::dbExecute(
    local$connection,
    "UPDATE _graft_record_revisions SET operation = 'update' WHERE revision_id = ?",
    params = list(target$revision_id[[1L]])
  )
  operation <- graft_query(
    local$store,
    "integrity",
    list(projections = FALSE),
    limit = 100L
  )
  expect_in("revision_operation_mismatch", operation$issue)
  DBI::dbExecute(
    local$connection,
    "UPDATE _graft_record_revisions SET operation = 'insert' WHERE revision_id = ?",
    params = list(target$revision_id[[1L]])
  )

  DBI::dbExecute(
    local$connection,
    "UPDATE _graft_record_revisions SET content_digest = ? WHERE revision_id = ?",
    params = list(
      paste0("sha256:", strrep("0", 64L)),
      target$revision_id[[1L]]
    )
  )
  digest <- graft_query(
    local$store,
    "integrity",
    list(projections = FALSE),
    limit = 100L
  )
  selected_error <- catch_graft_ingest_condition(
    graft_get(local$store, local$ids$entity, include = character())
  )
  expect_in("revision_digest_mismatch", digest$issue)
  expect_s3_class(selected_error, "graft_backend_error")
  expect_match(conditionMessage(selected_error), "content digest")

  missing <- local_retrieval_store()
  missing_batch_id <- DBI::dbGetQuery(
    missing$connection,
    "SELECT batch_id FROM _graft_batches ORDER BY commit_order LIMIT 1"
  )$batch_id[[1L]]
  DBI::dbExecute(
    missing$connection,
    "DELETE FROM _graft_batches WHERE batch_id = ?",
    params = list(missing_batch_id)
  )
  missing_batch <- graft_query(
    missing$store,
    "integrity",
    list(projections = FALSE),
    limit = 100L
  )
  expect_in("orphan_revision_batch", missing_batch$issue)

  expect_identical(batch$status[batch$batch_id == batch_id], "committed")
})

test_that("BR-21 selected reads do not deep-scan unrelated history", {
  store <- local_graft_ingest_store()
  count <- 200L
  ids <- vapply(
    seq_len(count),
    function(index) {
      test_graft_id(paste0("unrelated-history-", index))
    },
    character(1)
  )
  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = ids,
        preferred_name = paste("Entity", seq_len(count))
      )
    ),
    graft_provenance(
      "unrelated-history",
      idempotency_key = "unrelated-history"
    )
  )
  original_validate <- validated_public_revision_record
  validated <- 0L
  local_mocked_bindings(
    deep_integrity_issues = function(...) {
      stop("normal reads must not deep-scan the ledger", call. = FALSE)
    },
    validated_public_revision_record = function(...) {
      validated <<- validated + 1L
      original_validate(...)
    }
  )

  current <- graft_get(store, ids[[1L]], include = character())
  expect_identical(current$id, ids[[1L]])
  expect_identical(validated, 1L)
  validated <- 0L
  history <- graft_history(store, ids[[1L]], limit = 1L)
  expect_equal(nrow(history), 1L)
  expect_identical(validated, 1L)
})

test_that("BR-21 retrieval JSON works with extension loading disabled", {
  schema <- graft_schema(tempest_manifest_path())
  connection <- DBI::dbConnect(
    duckdb::duckdb(shared_home = FALSE),
    dbdir = ":memory:",
    config = list(
      autoload_known_extensions = "false",
      autoinstall_known_extensions = "false"
    )
  )
  withr::defer(DBI::dbDisconnect(connection, shutdown = TRUE))
  store <- graft_open(schema, connection = connection, okf = "disabled")
  withr::defer(graft_close(store))
  fixture <- retrieval_fixture_records()
  graft_ingest(
    store,
    fixture$records,
    graft_provenance(
      "offline-retrieval",
      idempotency_key = "offline-retrieval"
    )
  )
  DBI::dbExecute(connection, "SET autoload_known_extensions = false")
  DBI::dbExecute(connection, "SET autoinstall_known_extensions = false")

  find <- graft_find(store, "poly", limit = 10L)
  claims <- graft_query(
    store,
    "claims",
    list(id = fixture$ids$entity),
    limit = 10L
  )
  settings <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT current_setting('autoload_known_extensions') AS autoload, ",
      "current_setting('autoinstall_known_extensions') AS autoinstall"
    )
  )

  expect_gt(nrow(find), 0L)
  expect_gt(nrow(claims), 0L)
  expect_identical(settings$autoload, FALSE)
  expect_identical(settings$autoinstall, FALSE)
})

test_that("BR-23 exact pagination cannot be starved by false payload hits", {
  withr::local_options(list(graft.retrieval_page_size = 2L))
  schema <- modified_ingest_schema(
    as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  )
  schema$manifest$classes$Entity$slots$description$sensitive <- TRUE
  schema <- refresh_schema_structural_digest(schema)
  store <- local_graft_ingest_store(schema = schema)
  connection <- as_graft_store_internal(store)$connection
  entity_ids <- sort(vapply(
    seq_len(8L),
    \(index) test_graft_id(paste0("pagination-entity-", index)),
    character(1)
  ))
  semantic_ids <- sort(vapply(
    seq_len(6L),
    \(index) test_graft_id(paste0("pagination-semantic-", index)),
    character(1)
  ))
  claim_ids <- sort(vapply(
    seq_len(6L),
    \(index) test_graft_id(paste0("pagination-claim-", index)),
    character(1)
  ))
  evidence_ids <- sort(vapply(
    seq_len(6L),
    \(index) test_graft_id(paste0("pagination-evidence-", index)),
    character(1)
  ))
  ids <- list(
    target = entity_ids[[6L]],
    other = entity_ids[[7L]],
    find_false = entity_ids[seq_len(5L)],
    find_true = entity_ids[[8L]],
    semantic_false = semantic_ids[seq_len(5L)],
    semantic_true = semantic_ids[[6L]],
    decoys = claim_ids[seq_len(5L)],
    evidenced_claim = claim_ids[[6L]],
    evidence_false = evidence_ids[seq_len(5L)],
    evidence_true = evidence_ids[[6L]],
    source = test_graft_id("pagination-source")
  )
  entity_ids <- c(ids$target, ids$other, ids$find_false, ids$find_true)
  entities <- data.frame(
    id = entity_ids,
    preferred_name = c(
      "Target",
      "Other",
      paste("False", seq_along(ids$find_false)),
      "Needle public"
    ),
    description = c(
      "private",
      "private",
      rep("needle private", length(ids$find_false)),
      "private"
    ),
    inchikey = c(
      "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
      rep(NA_character_, length(entity_ids) - 1L)
    )
  )
  semantic <- data.frame(
    id = c(ids$semantic_false, ids$semantic_true),
    subject = c(rep(ids$other, length(ids$semantic_false)), ids$target),
    predicate = c(
      paste0("schema:false", seq_along(ids$semantic_false)),
      "schema:genuine"
    ),
    object_entity = rep(ids$other, length(ids$semantic_false) + 1L),
    measurement_method = c(
      paste(ids$target, seq_along(ids$semantic_false)),
      "public"
    )
  )
  narrative_ids <- c(ids$decoys, ids$evidenced_claim)
  claims <- data.frame(
    id = narrative_ids,
    statement_text = c(
      paste("Decoy", seq_along(ids$decoys)),
      "Evidence-bearing claim"
    ),
    primary_subject = ids$target,
    status = "active",
    about = I(rep(list(ids$target), length(narrative_ids)))
  )
  evidence <- data.frame(
    id = c(ids$evidence_false, ids$evidence_true),
    statement_id = c(ids$semantic_false, ids$evidenced_claim),
    source_id = ids$source,
    support_type = "supports",
    excerpt = c(
      rep(ids$evidenced_claim, length(ids$evidence_false)),
      "Exact evidence"
    )
  )
  records <- list(
    Entity = entities,
    Source = data.frame(
      id = ids$source,
      title = "Pagination source",
      uri = "https://example.com/pagination"
    ),
    Claim = claims,
    SemanticClaim = semantic,
    ClaimEvidence = evidence
  )
  graft_ingest(
    store,
    records,
    graft_provenance("pagination", idempotency_key = "pagination")
  )
  private_identifiers <- data.frame(
    record_id = ids$target,
    class = "Entity",
    namespace = paste0("aaa_private_", 1:5),
    value = paste0("private-", 1:5),
    normalized_value = paste0("private-", 1:5),
    status = "equivalent",
    assigned_by = "test",
    confidence = NA_real_,
    created_at = as.POSIXct(Sys.time(), tz = "UTC")
  )
  DBI::dbAppendTable(
    connection,
    "_graft_identifiers",
    private_identifiers
  )

  found <- graft_find(store, "needle", class = "Entity", limit = 1L)
  claim <- graft_query(
    store,
    "claims",
    list(id = ids$target, predicate = "schema:genuine"),
    limit = 1L
  )
  citation <- graft_query(
    store,
    "evidence",
    list(statement_id = ids$evidenced_claim),
    limit = 1L
  )
  hydrated <- graft_get(
    store,
    ids$target,
    include = c("claims", "evidence"),
    limits = list(claims = 1L, evidence = 1L)
  )
  identifiers <- graft_query(
    store,
    "identifiers",
    list(id = ids$target),
    limit = 1L
  )

  expect_identical(found$id, ids$find_true)
  expect_identical(attr(found, "truncated"), FALSE)
  expect_length(intersect("description", names(found$record[[1L]])), 0L)
  expect_identical(claim$id, ids$semantic_true)
  expect_identical(attr(claim, "truncated"), FALSE)
  expect_identical(citation$id, ids$evidence_true)
  expect_identical(attr(citation, "truncated"), FALSE)
  expect_identical(hydrated$related$evidence$id, ids$evidence_true)
  expect_identical(hydrated$truncated$claims, TRUE)
  expect_identical(hydrated$truncated$evidence, FALSE)
  expect_identical(identifiers$namespace, "inchikey")
  expect_identical(attr(identifiers, "truncated"), FALSE)
})

test_that("BR-22 exact BIGINT and DECIMAL history remains lossless", {
  schema <- modified_ingest_schema(
    as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  )
  schema$manifest$classes$SemanticClaim$slots$temperature$range <- "decimal"
  schema$manifest$classes$SemanticClaim$slots$temperature$duckdb_type <-
    "DECIMAL"
  schema$manifest$slots$temperature$range <- "decimal"
  schema$manifest$slots$temperature$duckdb_type <- "DECIMAL"
  schema <- refresh_schema_structural_digest(schema)
  fixture <- retrieval_fixture_records()
  exact_bigint <- "9223372036854775807"
  exact_decimal <- "12345678901234.567"
  fixture$records$ClaimEvidence$page_start <- exact_bigint
  fixture$records$ClaimEvidence$page_end <- exact_bigint
  fixture$records$SemanticClaim$temperature <- exact_decimal
  store <- local_graft_ingest_store(schema = schema)
  graft_ingest(
    store,
    fixture$records,
    graft_provenance(
      "exact-retrieval",
      idempotency_key = "exact-retrieval"
    )
  )

  bigint <- graft_get(
    store,
    fixture$ids$evidence,
    include = character()
  )
  decimal <- graft_get(
    store,
    fixture$ids$semantic_claim,
    include = character()
  )
  bigint_history <- graft_history(store, fixture$ids$evidence, limit = 1L)
  decimal_history <- graft_history(
    store,
    fixture$ids$semantic_claim,
    limit = 1L
  )

  expect_identical(bigint$record$page_start, exact_bigint)
  expect_identical(decimal$record$temperature, exact_decimal)
  expect_identical(bigint_history$record[[1L]]$page_start, exact_bigint)
  expect_identical(decimal_history$record[[1L]]$temperature, exact_decimal)
  expect_identical(
    coerce_historical_value(
      list(),
      list(duckdb_type = "BIGINT", multivalued = TRUE)
    ),
    character()
  )
  expect_identical(
    coerce_historical_value(
      list(),
      list(duckdb_type = "DECIMAL", multivalued = TRUE)
    ),
    character()
  )
})
