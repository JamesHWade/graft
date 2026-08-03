test_that("graft_plan reports detailed source-row validation issues", {
  store <- local_graft_ingest_store()
  id <- \(index) sprintf("graft:%026d", index)
  records <- list(
    Source = data.frame(id = id(8L), title = 123),
    Entity = data.frame(
      id = c(id(1L), id(2L)),
      preferred_name = c(NA_character_, "Valid entity"),
      inchikey = c("invalid", NA_character_)
    ),
    Claim = data.frame(
      id = c(id(3L), id(4L)),
      statement_text = c("Invalid bound", "Invalid semantics"),
      claim_type = c("finding", "not-a-type"),
      confidence = c(-0.1, 0.5),
      valid_from = c(
        "2026-01-01T00:00:00Z",
        "2026-02-02T00:00:00Z"
      ),
      valid_to = c(
        "2026-01-02T00:00:00Z",
        "2026-02-01T00:00:00Z"
      ),
      about = I(list(id(2L), id(9L)))
    ),
    SemanticClaim = data.frame(
      id = id(5L),
      subject = id(2L),
      predicate = "schema:relatedTo"
    )
  )

  plan <- graft_plan(store, records, graft_provenance("validation"))
  issues <- plan@issues

  expect_identical(plan@valid, FALSE)
  expect_setequal(
    issues$rule,
    c(
      "required",
      "type_varchar",
      "pattern",
      "enum_membership",
      "minimum_value",
      "valid_time_order",
      "reference_exists",
      "exactly_one_semantic_object"
    )
  )
  expect_identical(nrow(issues), 8L)
  expect_identical(anyNA(issues$input_row), FALSE)
  expect_identical(
    issues$input_row[issues$rule == "minimum_value"],
    1L
  )
  expect_identical(
    issues$input_row[issues$rule == "enum_membership"],
    2L
  )
  expect_identical(
    issues$class[issues$rule == "type_varchar"],
    "Source"
  )
  expect_identical(
    issues$condition_class[issues$rule == "reference_exists"],
    "graft_reference_error"
  )
})

test_that("exact identifiers and origins reconcile through public operations", {
  store <- local_graft_ingest_store()
  first <- graft_ingest(
    store,
    list(
      Entity = data.frame(
        preferred_name = "Water",
        inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
      ),
      Source = data.frame(
        title = "Paper",
        doi = "https://doi.org/10.1000/GRAFT"
      )
    ),
    graft_provenance("exact-a", idempotency_key = "exact-a")
  )
  entity_id <- graft_query(
    store,
    "lookup",
    list(
      namespace = "inchikey",
      value = "xlyofnoqvpjjnp-uhfffaoysa-n"
    )
  )$record_id
  source_id <- graft_query(
    store,
    "lookup",
    list(namespace = "doi", value = "DOI:10.1000/graft")
  )$record_id
  second <- graft_ingest(
    store,
    list(
      Entity = data.frame(
        preferred_name = "Water updated",
        inchikey = "xlyofnoqvpjjnp-uhfffaoysa-n"
      ),
      Source = data.frame(
        title = "Paper updated",
        doi = "DOI:10.1000/graft"
      )
    ),
    graft_provenance("exact-b", idempotency_key = "exact-b")
  )
  identifier <- graft_query(
    store,
    "identifiers",
    list(id = entity_id)
  )

  origin_first <- graft_ingest(
    store,
    list(
      Entity = data.frame(
        preferred_name = "Origin one",
        .graft_origin_key = "entity-1",
        check.names = FALSE
      )
    ),
    graft_provenance("origin", idempotency_key = "origin-1")
  )
  origin_id <- graft_find(store, "Origin one", class = "Entity")$id
  origin_second <- graft_ingest(
    store,
    list(
      Entity = data.frame(
        preferred_name = "Origin updated",
        .graft_origin_key = "entity-1",
        check.names = FALSE
      )
    ),
    graft_provenance("origin", idempotency_key = "origin-2")
  )

  expect_identical(first$inserted, c(Entity = 1L, Source = 1L))
  expect_identical(second$updated, c(Entity = 1L, Source = 1L))
  expect_identical(
    graft_get(store, entity_id, include = character())$record$preferred_name,
    "Water updated"
  )
  expect_identical(
    graft_get(store, source_id, include = character())$record$title,
    "Paper updated"
  )
  expect_identical(
    identifier$normalized_value,
    "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
  )
  expect_identical(origin_first$inserted, c(Entity = 1L))
  expect_identical(origin_second$updated, c(Entity = 1L))
  expect_identical(
    graft_get(store, origin_id, include = character())$record$preferred_name,
    "Origin updated"
  )
})

test_that("identity is deterministic and conflicts cannot mutate the store", {
  store <- local_graft_ingest_store()
  entity <- list(
    Entity = data.frame(
      preferred_name = "Water",
      inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
    )
  )
  run <- list(
    Run = data.frame(run_identifier = "stable-run", name = "Run")
  )
  entity_a <- graft_plan(store, entity, graft_provenance("producer-a"))
  entity_b <- graft_plan(store, entity, graft_provenance("producer-b"))
  run_a <- graft_plan(store, run, graft_provenance("producer-a"))
  run_b <- graft_plan(store, run, graft_provenance("producer-b"))

  id <- \(index) sprintf("graft:%026d", index)
  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = c(id(20L), id(21L)),
        preferred_name = c("InChIKey owner", "CAS owner"),
        inchikey = c(
          "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
          NA_character_
        ),
        cas_number = c(NA_character_, "50-00-0")
      )
    ),
    graft_provenance("seed", idempotency_key = "identity-seed")
  )
  connection <- as_graft_store_internal(store)$connection
  before <- lapply(
    c(
      "_graft_batches",
      "_graft_record_revisions",
      "_graft_identifiers",
      "_graft_origins"
    ),
    \(table) DBI::dbReadTable(connection, table)
  )
  conflict <- graft_plan(
    store,
    list(
      Entity = data.frame(
        preferred_name = "Conflict",
        inchikey = "xlyofnoqvpjjnp-uhfffaoysa-n",
        cas_number = "CAS: 50-00-0"
      )
    ),
    graft_provenance("conflict")
  )
  condition <- catch_graft_ingest_condition(graft_commit(store, conflict))
  after <- lapply(
    c(
      "_graft_batches",
      "_graft_record_revisions",
      "_graft_identifiers",
      "_graft_origins"
    ),
    \(table) DBI::dbReadTable(connection, table)
  )

  expect_identical(entity_a@changes$record_id, entity_b@changes$record_id)
  expect_identical(entity_a@changes$identity_reason, "exact_identifier_mint")
  expect_identical(run_a@changes$record_id, run_b@changes$record_id)
  expect_identical(run_a@changes$identity_reason, "deterministic_key")
  expect_match(run_a@changes$record_id, "^graft:[0-9A-HJKMNP-TV-Z]{26}$")
  expect_no_match(run_a@changes$identity_evidence, "stable-run|producer-a")
  expect_identical(conflict@valid, FALSE)
  expect_setequal(conflict@issues$rule, "consistent_exact_identity")
  expect_s3_class(condition, "graft_commit_plan_invalid")
  expect_identical(after, before)
})

test_that("public commits replay safely and roll back atomically", {
  store <- local_graft_ingest_store()
  records <- list(
    Entity = data.frame(
      id = "graft:00000000000000000000000030",
      preferred_name = "Replay entity"
    )
  )
  plan <- graft_plan(
    store,
    records,
    graft_provenance("replay", idempotency_key = "replay")
  )
  first <- graft_commit(store, plan)
  connection <- as_graft_store_internal(store)$connection
  revisions_before <- nrow(DBI::dbReadTable(
    connection,
    "_graft_record_revisions"
  ))
  replay_condition <- NULL
  replay <- withCallingHandlers(
    graft_commit(store, plan),
    graft_batch_replay = function(condition) {
      replay_condition <<- condition
    }
  )
  revisions_after <- nrow(DBI::dbReadTable(
    connection,
    "_graft_record_revisions"
  ))

  rollback_store <- local_graft_ingest_store()
  rollback_connection <- as_graft_store_internal(rollback_store)$connection
  rollback_plan <- graft_plan(
    rollback_store,
    list(
      Entity = data.frame(
        id = "graft:00000000000000000000000031",
        preferred_name = "Rollback entity"
      ),
      Source = data.frame(
        id = "graft:00000000000000000000000032",
        title = "Rollback source",
        doi = "10.1000/rollback"
      )
    ),
    graft_provenance("rollback", idempotency_key = "rollback")
  )
  projection_before <- DBI::dbReadTable(
    rollback_connection,
    "_graft_projection_state"
  )
  withr::local_options(graft.commit_executor_failure_stage = "projections")
  rollback <- catch_graft_ingest_condition(
    graft_commit(rollback_store, rollback_plan)
  )
  counts <- vapply(
    c(
      "_graft_batches",
      "_graft_record_revisions",
      "_graft_record_heads",
      "_graft_record_observations",
      "_graft_identifiers",
      "_graft_origins"
    ),
    \(table) nrow(DBI::dbReadTable(rollback_connection, table)),
    integer(1)
  )

  expect_s3_class(replay_condition, "graft_batch_replay")
  expect_identical(replay$batch_id, first$batch_id)
  expect_identical(replay$replay, TRUE)
  expect_identical(revisions_after, revisions_before)
  expect_s3_class(rollback, "graft_backend_error")
  expect_identical(rollback$stage, "projections")
  expect_identical(unname(counts), integer(length(counts)))
  expect_equal(nrow(graft_find(rollback_store, "Rollback")), 0L)
  expect_identical(
    DBI::dbReadTable(rollback_connection, "_graft_projection_state"),
    projection_before
  )
})
