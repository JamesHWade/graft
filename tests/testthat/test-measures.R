test_that("every compiled schema carries the GraftMeasure system class", {
  schema <- graft_schema(tempest_manifest_path())
  contract <- schema@manifest$classes$GraftMeasure
  expect_identical(contract$role, "metadata")
  expect_identical(contract$view, "graft_measure")
  expect_identical(contract$id_policy, "require")
  expect_contains(
    names(contract$slots),
    c(
      "id",
      "name",
      "title",
      "description",
      "target_class",
      "expr",
      "parameters",
      "dimensions"
    )
  )
})

test_that("a proposed measure commits like any record and is retrievable", {
  store <- local_graft_ingest_store()
  records <- list(
    GraftMeasure = data.frame(
      id = "measure:entity-count",
      name = "entity-count",
      title = "Entity count",
      description = "Number of accepted entities.",
      target_class = "Entity",
      expr = "COUNT(*)",
      parameters = "[]",
      dimensions = "[]"
    )
  )
  plan <- graft_plan(
    store,
    records,
    graft_provenance(producer = "test", idempotency_key = "measure-v1")
  )
  expect_identical(nrow(plan@issues), 0L)
  graft_commit(store, plan)

  fetched <- graft_get(store, "measure:entity-count")
  expect_identical(fetched$class, "GraftMeasure")
  expect_identical(fetched$record$expr, "COUNT(*)")
})
