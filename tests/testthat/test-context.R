test_that("kg_context is manifest-generated and suppresses sensitive fields", {
  schema <- kg_schema(tempest_manifest_path())
  schema$manifest$classes$Entity$slots$description$sensitive <- TRUE
  store <- local_ingest_store(schema = schema)

  context <- kg_context(store, class = "Entity")

  expect_s3_class(context, "kg_context")
  expect_match(context$text, "Entity")
  expect_match(context$text, "inchikey")
  expect_match(context$text, "single-owning-process")
  expect_false(grepl("description", context$text, fixed = TRUE))
  entity <- context$classes[context$classes$class == "Entity", , drop = FALSE]
  expect_false("description" %in% entity$public_fields[[1L]])
  expect_true(context$query_limits$select_rows <= 1000L)
  expect_identical(
    context$store_schema_digest,
    store_schema_digest(store)
  )
})

test_that("kg_context respects its text token budget", {
  store <- local_ingest_store()

  context <- kg_context(store, token_budget = 40)

  expect_lte(context$estimated_tokens, 40L)
  expect_lte(nchar(context$text, type = "chars"), 160L)
  expect_identical(context$token_budget, 40L)
  expect_identical(context$truncated, TRUE)

  condition <- catch_graft_ingest_condition(
    kg_context(store, token_budget = 10001)
  )
  expect_s3_class(condition, "graft_limit_error")
})

test_that("class-scoped context restricts relationship owners", {
  store <- local_ingest_store()

  context <- kg_context(store, class = "Claim")

  expect_true(nrow(context$relationships) > 0L)
  expect_identical(unique(context$relationships$owner_class), "Claim")
  expect_setequal(
    context$relationships$field,
    c("primary_subject", "superseded_by", "about")
  )
  expect_identical(
    context$evidence_expectations$class,
    "ClaimEvidence"
  )
})
