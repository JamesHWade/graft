test_that("kg_find searches declared fields only and is deterministic", {
  fixture <- local_retrieval_store()

  label <- kg_find(fixture$store, "POLYETHYLENE")
  description <- kg_find(fixture$store, "thermoplastic")
  hidden_identifier <- kg_find(fixture$store, "9002-88-4")

  expect_identical(label$id[[1L]], fixture$ids$entity)
  expect_identical(label$label[[1L]], "Polyethylene")
  expect_identical(label$class[[1L]], "Entity")
  expect_gt(label$score[[1L]], 0)
  expect_identical(description$id, fixture$ids$entity)
  expect_identical(nrow(hidden_identifier), 0L)
})

test_that("kg_find enforces limits and reports truncation", {
  fixture <- local_retrieval_store()

  result <- kg_find(fixture$store, "polyethylene", limit = 1)

  expect_identical(nrow(result), 1L)
  expect_identical(attr(result, "limit"), 1L)
  expect_identical(attr(result, "truncated"), TRUE)
  expect_identical(
    attr(result, "store_schema_digest"),
    store_schema_digest(fixture$store)
  )

  condition <- catch_graft_ingest_condition(
    kg_find(fixture$store, "polyethylene", limit = 1001)
  )
  expect_s3_class(condition, "graft_limit_error")
})
