test_that("references resolve across staged and existing records", {
  store <- local_ingest_store()
  records <- valid_atomic_records()
  reordered <- records[c(
    "ClaimEvidence",
    "Claim",
    "SemanticClaim",
    "EntityMention",
    "Source",
    "Entity"
  )]

  result <- kg_ingest(
    store,
    kg_batch("tempest", idempotency_key = "refs-staged"),
    reordered
  )
  expect_identical(sum(result$inserted), 6L)

  entity_id <- records$Entity$id
  claim <- data.frame(
    statement_text = "An existing reference",
    about = I(list(entity_id))
  )
  existing <- kg_write(
    store,
    kg_batch("tempest", idempotency_key = "refs-existing"),
    "Claim",
    claim
  )
  expect_identical(existing$inserted[["Claim"]], 1L)
})

test_that("abstract LinkML reference ranges use descendant ID formats", {
  skip_if_no_linkml_runtime()
  schema <- kg_compile_schema(
    plain_linkml_schema_path("abstract-reference.linkml.yaml"),
    withr::local_tempfile(fileext = ".graft.json")
  )
  store <- kg_connect_duckdb(schema, ":memory:")
  withr::defer(kg_disconnect(store))
  kg_init(store)

  result <- kg_ingest(
    store,
    kg_batch("abstract-reference", idempotency_key = "activity-v1"),
    list(
      Person = data.frame(id = "person:ada", name = "Ada"),
      Activity = data.frame(
        id = "activity:review",
        name = "Schema review",
        participants = I(list("person:ada"))
      )
    )
  )

  expect_identical(sum(result$inserted), 2L)
  expect_identical(
    kg_get(store, "activity:review")$record$participants,
    "person:ada"
  )
})

test_that("wrong and missing reference targets are classed", {
  store <- local_ingest_store()
  records <- valid_atomic_records()
  records$Claim$about <- I(list(records$Source$id))

  wrong <- catch_graft_ingest_condition(
    kg_ingest(
      store,
      kg_batch("tempest", idempotency_key = "wrong-ref"),
      records
    )
  )
  expect_s3_class(wrong, "graft_reference_error")
  expect_identical(wrong$rule, "reference_class")

  invalid_id <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "invalid-reference-id"),
      "Claim",
      data.frame(
        statement_text = "Invalid reference ID",
        about = I(list("person:ada"))
      )
    )
  )
  expect_s3_class(invalid_id, "graft_reference_error")
  expect_identical(invalid_id$rule, "internal_reference_id")

  missing <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "missing-ref"),
      "Claim",
      data.frame(
        statement_text = "Missing",
        about = I(list(test_graft_id("absent")))
      )
    )
  )
  expect_s3_class(missing, "graft_reference_error")
  expect_identical(missing$rule, "reference_exists")
})

test_that("semantic claims require exactly one object", {
  store <- local_ingest_store()
  entity_id <- test_graft_id("semantic-entity")
  kg_write(
    store,
    kg_batch("tempest", idempotency_key = "semantic-entity"),
    "Entity",
    data.frame(id = entity_id, preferred_name = "Entity")
  )

  neither <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "semantic-neither"),
      "SemanticClaim",
      data.frame(subject = entity_id, predicate = "schema:relatedTo")
    )
  )
  expect_s3_class(neither, "graft_validation_error")
  expect_identical(neither$rule, "exactly_one_semantic_object")

  both <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "semantic-both"),
      "SemanticClaim",
      data.frame(
        subject = entity_id,
        predicate = "schema:relatedTo",
        object_entity = entity_id,
        object_value = "value",
        object_datatype = "xsd:string"
      )
    )
  )
  expect_s3_class(both, "graft_validation_error")
  expect_identical(both$rule, "exactly_one_semantic_object")
})

test_that("enum, bounds, and temporal checks reject invalid records", {
  store <- local_ingest_store()
  entity_id <- test_graft_id("validation-entity")
  kg_write(
    store,
    kg_batch("tempest", idempotency_key = "validation-entity"),
    "Entity",
    data.frame(id = entity_id, preferred_name = "Entity")
  )

  invalid_enum <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "enum"),
      "Claim",
      data.frame(
        statement_text = "Invalid enum",
        claim_type = "not-a-type",
        about = I(list(entity_id))
      )
    )
  )
  expect_s3_class(invalid_enum, "graft_validation_error")
  expect_identical(invalid_enum$rule, "enum_membership")

  invalid_bound <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "bound"),
      "Claim",
      data.frame(
        statement_text = "Invalid confidence",
        confidence = -0.1,
        about = I(list(entity_id))
      )
    )
  )
  expect_s3_class(invalid_bound, "graft_validation_error")
  expect_identical(invalid_bound$rule, "minimum_value")

  invalid_time <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "time"),
      "Claim",
      data.frame(
        statement_text = "Invalid time",
        valid_from = "2026-02-02T00:00:00Z",
        valid_to = "2026-02-01T00:00:00Z",
        about = I(list(entity_id))
      )
    )
  )
  expect_s3_class(invalid_time, "graft_validation_error")
  expect_identical(invalid_time$rule, "valid_time_order")
})

test_that("duplicate IDs, origins, and generated targets fail early", {
  store <- local_ingest_store()
  duplicate_id <- test_graft_id("duplicate")

  ids <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "duplicate-id"),
      "Entity",
      data.frame(
        id = c(duplicate_id, duplicate_id),
        preferred_name = c("One", "Two")
      )
    )
  )
  expect_s3_class(ids, "graft_validation_error")
  expect_identical(ids$rule, "unique_batch_id")

  origins <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "duplicate-origin"),
      "Entity",
      data.frame(
        preferred_name = c("One", "Two"),
        .graft_origin_key = c("same", "same"),
        check.names = FALSE
      )
    )
  )
  expect_s3_class(origins, "graft_validation_error")
  expect_identical(origins$rule, "unique_batch_origin")

  entity_id <- test_graft_id("relation-target")
  relation <- catch_graft_ingest_condition(
    kg_ingest(
      store,
      kg_batch("tempest", idempotency_key = "duplicate-relation"),
      list(
        Entity = data.frame(id = entity_id, preferred_name = "Entity"),
        Claim = data.frame(
          statement_text = "Duplicate target",
          about = I(list(c(entity_id, entity_id)))
        )
      )
    )
  )
  expect_s3_class(relation, "graft_validation_error")
  expect_identical(relation$rule, "unique_relation_target")
})

test_that("planning aggregates independent row and field issues", {
  store <- local_ingest_store()
  records <- list(
    Entity = data.frame(
      id = c(test_graft_id("issue-one"), test_graft_id("issue-two")),
      preferred_name = c(NA_character_, NA_character_),
      inchikey = c("invalid-one", "invalid-two")
    ),
    Claim = data.frame(
      id = test_graft_id("issue-claim"),
      statement_text = "Missing target",
      about = I(list(test_graft_id("issue-absent")))
    )
  )

  plan <- graft_plan(store, records, graft_provenance("validation-test"))

  expect_identical(plan@valid, FALSE)
  expect_equal(sum(plan@issues$rule == "required"), 2L)
  expect_equal(sum(plan@issues$rule == "pattern"), 2L)
  expect_equal(sum(plan@issues$rule == "reference_exists"), 1L)
  expect_setequal(
    plan@issues$condition_class,
    c(
      "graft_reference_error",
      "graft_validation_error"
    )
  )
})

test_that("planning resolves references against the complete candidate set", {
  store <- local_ingest_store()
  records <- valid_atomic_records()
  records <- records[c(
    "ClaimEvidence",
    "Claim",
    "SemanticClaim",
    "EntityMention",
    "Source",
    "Entity"
  )]

  plan <- graft_plan(
    store,
    records,
    graft_provenance("validation-test")
  )
  execution <- graft:::commit_plan_execution(plan)$staged

  expect_identical(plan@valid, TRUE)
  expect_equal(nrow(execution$references), 7L)
  expect_setequal(
    execution$references$target_id,
    c(
      records$Entity$id,
      records$Source$id,
      records$Claim$id
    )
  )
})

test_that("planning preserves exact integer payloads as strings", {
  store <- local_ingest_store()
  records <- valid_atomic_records()
  records$ClaimEvidence$page_start <- "9007199254740993"
  records$ClaimEvidence$page_end <- "9007199254740994"

  plan <- graft_plan(
    store,
    records,
    graft_provenance("validation-test")
  )
  execution <- graft:::commit_plan_execution(plan)$staged
  row <- execution$rows[
    execution$rows$class == "ClaimEvidence",
    ,
    drop = FALSE
  ]
  payload <- jsonlite::fromJSON(row$payload_json[[1L]], simplifyVector = FALSE)

  expect_identical(plan@valid, TRUE)
  expect_identical(payload$page_start, "9007199254740993")
  expect_identical(payload$page_end, "9007199254740994")
})

test_that("planning snapshot query count is independent of candidate rows", {
  store <- local_ingest_store()
  original_query <- planning_query
  query_count <- 0L
  local_mocked_bindings(
    planning_query = function(...) {
      query_count <<- query_count + 1L
      original_query(...)
    }
  )
  provenance <- graft_provenance("query-count")
  graft_plan(
    store,
    list(
      Entity = data.frame(
        id = test_graft_id("bounded-one"),
        preferred_name = "One"
      )
    ),
    provenance
  )
  one_row_queries <- query_count
  query_count <- 0L
  count <- 1000L
  graft_plan(
    store,
    list(
      Entity = data.frame(
        id = vapply(
          seq_len(count),
          \(.x) test_graft_id(paste0("bounded-", .x)),
          character(1)
        ),
        preferred_name = paste("Entity", seq_len(count))
      )
    ),
    provenance
  )
  many_row_queries <- query_count

  expect_identical(one_row_queries, 4L)
  expect_identical(many_row_queries, one_row_queries)
})

test_that("exact numeric coercion rejects lossy doubles and canonicalizes text", {
  expect_null(coerce_exact_numeric(2^53, integer = TRUE))
  expect_null(coerce_exact_numeric(1.25, integer = FALSE))
  expect_identical(
    coerce_exact_numeric(
      c("+001.2300", "1.23", "-0.000", ".5000", "1."),
      integer = FALSE
    ),
    c("1.23", "1.23", "0", "0.5", "1")
  )
  expect_identical(
    coerce_exact_numeric(c("+01", "001", "-0"), integer = TRUE),
    c("1", "1", "0")
  )
  expect_identical(
    coerce_exact_numeric(c(1L, 2L), integer = FALSE),
    c("1", "2")
  )
})

test_that("exact integer lexemes share payload digests", {
  store <- local_ingest_store()
  first <- valid_atomic_records()
  second <- first
  first$ClaimEvidence$page_start <- "+001"
  first$ClaimEvidence$page_end <- "0002"
  second$ClaimEvidence$page_start <- "1"
  second$ClaimEvidence$page_end <- "2"
  provenance <- graft_provenance("numeric-canonicalization")

  first_plan <- graft_plan(store, first, provenance)
  second_plan <- graft_plan(store, second, provenance)
  first_row <- first_plan@changes$class == "ClaimEvidence"
  second_row <- second_plan@changes$class == "ClaimEvidence"

  expect_identical(first_plan@valid, TRUE)
  expect_identical(second_plan@valid, TRUE)
  expect_identical(
    first_plan@changes$proposed_content_digest[first_row],
    second_plan@changes$proposed_content_digest[second_row]
  )
})

test_that("planning rejects already-lossy BIGINT doubles", {
  store <- local_ingest_store()
  records <- valid_atomic_records()
  records$ClaimEvidence$page_start <- 2^53

  plan <- graft_plan(
    store,
    records,
    graft_provenance("numeric-loss")
  )

  expect_identical(plan@valid, FALSE)
  expect_setequal(plan@issues$rule, "type_bigint")
})
