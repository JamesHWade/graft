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
  expect_identical(
    records$support$knowledge_id %in% "knowledge:preference",
    c(FALSE, FALSE)
  )
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
  definitions <- data.frame(
    name = "record_count",
    target = "knowledge",
    expr = "ROW_COUNT()"
  )
  graft_ingest(
    store,
    list(GraftDefinition = definitions),
    graft_provenance("host", idempotency_key = "definition")
  )
  expect_equal(nrow(graft_definitions(store)), 1L)
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

test_that("serialized selections rebind after close and in a fresh worker", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema_path <- system.file(
    "extdata/narrative-knowledge.data-dict.json",
    package = "graft"
  )
  store <- local_narrative_store(path)
  snapshot <- graft_snapshot(store)
  ids <- c("knowledge:conclusion", "support:conclusion", "source:trial-v1")
  # App-owned exact selection: include evidence, not just the last change batch.
  basis <- list(
    snapshot = snapshot,
    ids = ids,
    revisions = vapply(
      ids,
      function(id) graft_history(store, id)$revision_id[[1]],
      character(1)
    )
  )
  selected <- lapply(ids, function(id) graft_get(graft_at(store, snapshot), id))
  checkpoint <- withr::local_tempfile(fileext = ".rds")
  saveRDS(basis, checkpoint)
  graft_close(store)
  result <- callr::r(
    function(checkout, schema_path, path, checkpoint) {
      pkgload::load_all(checkout, quiet = TRUE)
      basis <- readRDS(checkpoint)
      store <- graft::graft_open(
        graft::graft_schema(schema_path),
        path,
        read_only = TRUE,
        okf = "disabled"
      )
      on.exit(graft::graft_close(store))
      view <- graft::graft_at(store, basis$snapshot)
      list(
        records = lapply(basis$ids, function(id) graft::graft_get(view, id)),
        revisions = vapply(
          basis$ids,
          function(id) graft::graft_history(view, id)$revision_id[[1]],
          character(1)
        )
      )
    },
    args = list(
      checkout = normalizePath(test_path("..", "..")),
      schema_path = schema_path,
      path = path,
      checkpoint = checkpoint
    )
  )
  expect_identical(result$records, selected)
  expect_identical(result$revisions, basis$revisions)
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
