test_that("the offline narrative example preserves corrected and pinned meanings", {
  result <- narrative_fixture()$narrative_example()
  expect_gt(nrow(result$rejected), 0L)
  expect_match(result$pinned$body, "café")
  expect_match(result$current$body, "preliminary")
  expect_equal(nrow(result$history), 2L)
})

test_that("narrative types links and privacy are enforced separately from policy", {
  store <- local_narrative_store()
  records <- narrative_fixture()$narrative_records()
  read <- graft_get(store, "knowledge:preference")$record
  expect_identical(read$kind, "preference")
  expect_identical(read$purpose, "reading selection")
  expect_identical("owner_binding" %in% names(read), FALSE)
  invalid <- records$knowledge[1L, , drop = FALSE]
  invalid$kind <- "invented"
  plan <- graft_plan(
    store,
    list(knowledge = invalid),
    graft_provenance("test", idempotency_key = "bad-kind")
  )
  expect_identical(plan@valid, FALSE)
  invalid$kind <- "conclusion"
  invalid$body <- "short"
  invalid$lifecycle <- "archived"
  plan <- graft_plan(
    store,
    list(knowledge = invalid),
    graft_provenance("test", idempotency_key = "policy-is-not-assertion")
  )
  expect_identical(plan@valid, TRUE)
  graft_commit(store, plan)
  expect_identical(graft_get(store, invalid$id)$record$body, "short")
  expect_identical(graft_get(store, invalid$id)$record$lifecycle, "archived")
  expect_contains(graft_tools(store)$graft_find("short")$result$id, invalid$id)
})

test_that("flat tags and normalized evidence preserve their content", {
  store <- local_narrative_store()
  record <- graft_get(store, "knowledge:conclusion")$record
  expect_equal(unlist(record$tags), c("research", "synthetic"))
  link <- graft_get(store, "support:conclusion")$record
  source <- graft_get(store, link$source_id)$record
  expect_identical(
    source$document_revision,
    "document:synthetic-trial:version-1"
  )
  expect_identical(link$anchor, "paragraph:1")
  expect_identical(
    graft_get(store, "knowledge:question")$record$kind,
    "question"
  )
})

test_that("both frozen producer exports support the same narrative record shapes", {
  for (file in c(
    "narrative-knowledge.data-dict.json",
    "narrative-knowledge.data-dict-0.0.3.json"
  )) {
    schema <- graft_schema(system.file("extdata", file, package = "graft"))
    store <- graft_open(schema, okf = "disabled")
    withr::defer(graft_close(store))
    records <- narrative_fixture()$narrative_records()
    graft_ingest(
      store,
      records,
      graft_provenance("host", idempotency_key = "seed")
    )
    expect_identical(
      graft_get(store, "knowledge:interpretation")$record$body,
      records$knowledge$body[[2]]
    )
    expect_identical(
      graft_get(store, "support:conclusion")$record$source_id,
      "source:trial-v1"
    )
    graft_close(store)
  }
})
