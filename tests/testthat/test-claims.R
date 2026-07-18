test_that("kg_claims discovers narrative and semantic statement shapes", {
  fixture <- local_retrieval_store()

  claims <- kg_claims(fixture$store, fixture$ids$entity)

  expect_setequal(
    claims$id,
    c(
      fixture$ids$active_claim,
      fixture$ids$competing_claim,
      fixture$ids$semantic_claim
    )
  )
  expect_setequal(claims$statement_shape, c("narrative", "semantic"))
  narrative <- claims[claims$statement_shape == "narrative", , drop = FALSE]
  expect_true(all(is.na(narrative$predicate)))
  expect_true(all(vapply(
    narrative$about,
    \(.x) fixture$ids$entity %in% .x,
    logical(1)
  )))

  semantic <- kg_claims(
    fixture$store,
    fixture$ids$entity,
    predicate = "schema:relatedTo"
  )
  expect_identical(semantic$id, fixture$ids$semantic_claim)
  expect_identical(semantic$predicate, "schema:relatedTo")
})

test_that("kg_claims filters superseded records by default", {
  fixture <- local_retrieval_store()

  active <- kg_claims(fixture$store, fixture$ids$entity)
  all <- kg_claims(
    fixture$store,
    fixture$ids$entity,
    include_superseded = TRUE
  )

  expect_false(fixture$ids$superseded_claim %in% active$id)
  expect_true(fixture$ids$superseded_claim %in% all$id)
})

test_that("evidence locators and qualifiers are hydrated from stored rows", {
  fixture <- local_retrieval_store()

  evidence <- kg_evidence(
    fixture$store,
    fixture$ids$active_claim,
    support_type = "supports"
  )
  claims <- kg_claims(fixture$store, fixture$ids$entity)
  semantic <- claims[claims$id == fixture$ids$semantic_claim, , drop = FALSE]
  narrative <- claims[claims$id == fixture$ids$active_claim, , drop = FALSE]

  expect_identical(evidence$source_id, fixture$ids$source)
  expect_identical(
    evidence$source_uri,
    paste0(
      "https://example.com/reports/Result?Study=ABC"
    )
  )
  expect_identical(evidence$locator_type, "page")
  expect_identical(evidence$locator_value, "p. 4")
  expect_identical(evidence$page_start, 4)
  expect_identical(
    evidence$excerpt,
    "Polyethylene retained its strength."
  )
  expect_identical(semantic$qualifiers[[1L]]$temperature, 23)
  expect_identical(
    semantic$qualifiers[[1L]]$measurement_method,
    "tensile test"
  )
  expect_named(semantic$attributes[[1L]], character())
  expect_identical(narrative$attributes[[1L]]$claim_type, "finding")
  expect_identical(narrative$attributes[[1L]]$importance, "high")
  expect_named(narrative$qualifiers[[1L]], character())
})

test_that("kg_competing_claims returns candidate groups without adjudication", {
  fixture <- local_retrieval_store()

  groups <- kg_competing_claims(fixture$store)

  expect_identical(nrow(groups), 1L)
  expect_identical(groups$candidate_count, 2L)
  candidates <- groups$claims[[1L]]
  expect_setequal(
    candidates$id,
    c(fixture$ids$active_claim, fixture$ids$competing_claim)
  )
  expect_setequal(candidates$polarity, c("positive", "uncertain"))
  expect_false("contradiction" %in% names(groups))
})

test_that("kg_competing_claims excludes missing grouping keys", {
  store <- local_ingest_store()
  entity_one <- test_graft_id("null-key-entity-one")
  entity_two <- test_graft_id("null-key-entity-two")

  kg_ingest(
    store,
    kg_batch("null-key-fixture", idempotency_key = "null-key-fixture"),
    list(
      Entity = data.frame(
        id = c(entity_one, entity_two),
        preferred_name = c("One", "Two")
      ),
      Claim = data.frame(
        statement_text = c("Claim about one.", "Claim about two."),
        status = c("active", "active"),
        about = I(list(entity_one, entity_two))
      )
    )
  )

  groups <- kg_competing_claims(store, key = "primary_subject")

  expect_identical(nrow(groups), 0L)
})
