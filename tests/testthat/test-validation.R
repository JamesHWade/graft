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
