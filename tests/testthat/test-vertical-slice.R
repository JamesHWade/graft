test_that("two deterministic Tempest runs accumulate and replay safely", {
  fixture <- local_vertical_slice_store()
  store <- fixture$store
  ids <- fixture$ids
  expected_counts <- c(
    Entity = 4L,
    Source = 2L,
    Claim = 4L,
    SemanticClaim = 2L,
    ClaimEvidence = 7L,
    EntityMention = 2L,
    Run = 2L,
    Activity = 2L,
    Question = 2L,
    Section = 2L
  )
  observed_counts <- vapply(
    names(expected_counts),
    function(record_class) {
      nrow(dplyr::collect(kg_records(store, record_class)))
    },
    integer(1)
  )

  expect_identical(observed_counts, expected_counts)
  expect_s3_class(fixture$replay_condition, "graft_batch_replay")
  expect_identical(fixture$replay$replay, TRUE)
  expect_identical(
    fixture$replay$batch_id,
    fixture$result_two$batch_id
  )
  expect_identical(fixture$after_replay, fixture$before_replay)

  review_lookup <- kg_lookup(
    store,
    "canonical_url",
    "https://www.example.org:443/lldpe/review/#another-fragment"
  )
  expect_identical(review_lookup$record_id, ids$source_review)
  expect_identical(
    nrow(dplyr::collect(kg_records(store, "Source"))),
    2L
  )

  observations <- DBI::dbGetQuery(
    store$connection,
    paste(
      "SELECT COUNT(*) AS n FROM _graft_record_observations",
      "WHERE record_id = ?"
    ),
    params = list(ids$source_review)
  )
  expect_equal(observations$n, 2)

  lineage <- kg_select(
    store,
    "Claim",
    fields = c("id", "status", "superseded_by"),
    filters = list(list(
      field = "id",
      operator = "eq",
      value = ids$claim_range_old
    ))
  )
  expect_identical(lineage$status, "superseded")
  expect_identical(lineage$superseded_by, ids$claim_range_new)
})

test_that("six tool-equivalent calls return bounded LLDPE answer material", {
  fixture <- local_vertical_slice_store()
  evaluation <- vertical_slice_tool_evaluation(
    fixture$store,
    fixture$ids
  )
  calls <- evaluation$calls
  answer <- vertical_slice_answer_material(evaluation)
  ids <- fixture$ids

  expect_identical(
    names(calls),
    c(
      "kg_describe",
      "kg_find",
      "kg_get",
      "kg_neighbors",
      "kg_claims",
      "kg_select"
    )
  )
  expect_match(evaluation$question, "LLDPE crystallinity")
  expect_s3_class(calls$kg_describe, "kg_context")
  expect_identical(calls$kg_describe$token_budget, 80L)
  expect_identical(calls$kg_describe$truncated, TRUE)
  expect_identical(nrow(calls$kg_find), 1L)
  expect_identical(attr(calls$kg_find, "truncated"), TRUE)
  expect_identical(calls$kg_get$id, ids$lldpe)
  expect_s3_class(calls$kg_get, "kg_record")
  expect_s3_class(calls$kg_neighbors, "kg_subgraph")
  expect_identical(calls$kg_neighbors$limits$max_nodes, 3L)
  expect_identical(calls$kg_neighbors$limits$max_edges, 2L)
  expect_identical(calls$kg_neighbors$truncated, TRUE)
  expect_identical(attr(calls$kg_claims, "limit"), 20L)
  expect_identical(attr(calls$kg_select, "limit"), 10L)

  digest <- graft:::store_schema_digest(fixture$store)
  expect_identical(calls$kg_describe$store_schema_digest, digest)
  expect_identical(attr(calls$kg_find, "store_schema_digest"), digest)
  expect_identical(calls$kg_get$store_schema_digest, digest)
  expect_identical(calls$kg_neighbors$store_schema_digest, digest)
  expect_identical(attr(calls$kg_claims, "store_schema_digest"), digest)
  expect_identical(attr(calls$kg_select, "store_schema_digest"), digest)

  expect_setequal(
    calls$kg_claims$id,
    c(
      ids$claim_branching,
      ids$claim_range_old,
      ids$claim_range_new,
      ids$claim_competing,
      ids$semantic_branching,
      ids$semantic_crystallinity
    )
  )
  narrative <- calls$kg_claims[
    calls$kg_claims$statement_shape == "narrative",
    ,
    drop = FALSE
  ]
  expect_true(all(is.na(narrative$predicate)))
  expect_in("positive", answer$active_narrative$polarity)
  expect_in("negative", answer$active_narrative$polarity)
  expect_identical(answer$superseded$id, ids$claim_range_old)
  expect_setequal(
    answer$semantic$predicate,
    c("graft:branchingLowers", "graft:crystallinityPercent")
  )
  expect_identical(
    answer$unresolved_mentions$id,
    ids$mention_unresolved
  )
  expect_identical(
    answer$unresolved_mentions$locator_value,
    "para. 9"
  )
})

test_that("vertical-slice citations contain only stored IDs and locators", {
  fixture <- local_vertical_slice_store()
  evaluation <- vertical_slice_tool_evaluation(
    fixture$store,
    fixture$ids
  )
  answer <- vertical_slice_answer_material(evaluation)
  ids <- fixture$ids
  citations <- answer$citations
  stored_sources <- dplyr::collect(kg_records(fixture$store, "Source"))
  stored_claims <- c(
    dplyr::collect(kg_records(fixture$store, "Claim"))$id,
    dplyr::collect(kg_records(fixture$store, "SemanticClaim"))$id
  )
  expected_evidence <- c(
    ids$evidence_branching_support,
    ids$evidence_range_old,
    ids$evidence_semantic_branching,
    ids$evidence_branching_contradict,
    ids$evidence_range_new,
    ids$evidence_competing,
    ids$evidence_semantic_crystallinity
  )
  expected_locators <- c(
    "page|p. 12",
    "page|p. 13",
    "section|sec. 3.2",
    "page|p. 6",
    "other|table 1",
    "page|p. 7",
    "other|table 1"
  )

  expect_setequal(citations$id, expected_evidence)
  expect_true(all(citations$statement_id %in% stored_claims))
  expect_true(all(citations$source_id %in% stored_sources$id))
  expect_true(all(nzchar(citations$source_uri)))
  expect_true(all(nzchar(citations$source_title)))
  expect_true(all(nzchar(citations$excerpt)))
  expect_setequal(
    paste(citations$locator_type, citations$locator_value, sep = "|"),
    expected_locators
  )
  expect_setequal(citations$support_type, c("supports", "contradicts"))
})

test_that("actual ToolDefs execute the provider-free vertical slice", {
  testthat::skip_if_not_installed("ellmer")
  fixture <- local_vertical_slice_store()
  evaluation <- vertical_slice_tooldef_evaluation(
    fixture$store,
    fixture$ids
  )
  outputs <- evaluation$outputs
  digest <- graft:::store_schema_digest(fixture$store)

  expect_identical(
    names(outputs),
    c(
      "kg_describe",
      "kg_find",
      "kg_get",
      "kg_neighbors",
      "kg_claims",
      "kg_select"
    )
  )
  expect_identical(length(evaluation$tools), 6L)
  for (output in outputs) {
    expect_named(
      output,
      c("result", "truncated", "limit", "store_schema_digest")
    )
    expect_type(output$truncated, "logical")
    expect_length(output$truncated, 1L)
    expect_identical(output$store_schema_digest, digest)
    expect_identical(is.null(output$limit), FALSE)
  }

  expect_identical(outputs$kg_describe$limit, 80L)
  expect_identical(outputs$kg_describe$truncated, TRUE)
  expect_identical(outputs$kg_find$limit, 1L)
  expect_identical(outputs$kg_find$truncated, TRUE)
  expect_identical(
    outputs$kg_get$limit,
    list(identifiers = 10L, claims = 10L, evidence = 20L)
  )
  expect_identical(
    outputs$kg_neighbors$limit,
    list(nodes = 3L, edges = 2L, hops = 2L)
  )
  expect_identical(outputs$kg_neighbors$truncated, TRUE)
  expect_identical(outputs$kg_claims$limit, 20L)
  expect_identical(outputs$kg_select$limit, 10L)
  expect_lte(nrow(outputs$kg_find$result), outputs$kg_find$limit)
  expect_lte(
    nrow(outputs$kg_claims$result),
    outputs$kg_claims$limit
  )
  expect_lte(
    nrow(outputs$kg_select$result),
    outputs$kg_select$limit
  )
  expect_lte(
    nrow(outputs$kg_neighbors$result$nodes),
    outputs$kg_neighbors$limit$nodes
  )
  expect_lte(
    nrow(outputs$kg_neighbors$result$edges),
    outputs$kg_neighbors$limit$edges
  )

  claims <- outputs$kg_claims$result
  citation_parts <- Filter(\(.x) nrow(.x) > 0L, claims$evidence)
  citations <- do.call(rbind, citation_parts)
  rownames(citations) <- NULL
  stored <- as.data.frame(
    dplyr::collect(kg_records(fixture$store, "ClaimEvidence"))
  )
  actual <- citations[
    order(citations$id),
    c(
      "id",
      "statement_id",
      "source_id",
      "support_type",
      "locator_type",
      "locator_value"
    ),
    drop = FALSE
  ]
  expected <- stored[
    order(stored$id),
    names(actual),
    drop = FALSE
  ]
  rownames(actual) <- NULL
  rownames(expected) <- NULL

  expect_identical(actual, expected)
  expect_true(all(nzchar(citations$source_uri)))
  expect_true(all(nzchar(citations$excerpt)))
})
