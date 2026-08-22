local_measure_store <- function(env = parent.frame()) {
  store <- local_graft_ingest_store(env = env)
  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = c(
          test_graft_id("measure-entity-a"),
          test_graft_id("measure-entity-b"),
          test_graft_id("measure-entity-c")
        ),
        label = c("solvent", "solvent", "acid"),
        preferred_name = c("Acetone", "Benzene", "Citric acid")
      )
    ),
    graft_provenance(producer = "fixture", idempotency_key = "entities-v1")
  )
  graft_ingest(
    store,
    list(
      GraftMeasure = data.frame(
        id = "measure:entity-count",
        name = "entity-count",
        title = "Entity count",
        description = "Number of accepted entities.",
        target_class = "Entity",
        expr = "COUNT(*)",
        parameters = paste0(
          "[{\"name\":\"label\",\"type\":\"string\",",
          "\"description\":\"Entity label.\",\"column\":\"label\"}]"
        ),
        dimensions = "[\"label\",\"preferred_name\"]"
      )
    ),
    graft_provenance(producer = "fixture", idempotency_key = "measure-v1")
  )
  store
}

test_that("graft_measures() lists accepted measures", {
  store <- local_measure_store()
  measures <- graft_measures(store)
  expect_identical(measures$name, "entity-count")
  expect_identical(measures$target_class, "Entity")
  expect_identical(measures$dimensions[[1L]], c("label", "preferred_name"))
  expect_identical(
    measures$parameters[[1L]]$column,
    "label"
  )
  expect_match(attr(measures, "store_schema_digest"), "^sha256:")
})

test_that("graft_measure() evaluates totals, arguments, and dimensions", {
  store <- local_measure_store()

  total <- graft_measure(store, "entity-count")
  expect_identical(total$value, 3)

  filtered <- graft_measure(
    store,
    "entity-count",
    arguments = list(label = "solvent")
  )
  expect_identical(filtered$value, 2)

  grouped <- graft_measure(store, "entity-count", by = "label")
  expect_identical(grouped$label, c("acid", "solvent"))
  expect_identical(grouped$value, c(1, 2))

  expect_identical(attr(total, "measure_id"), "measure:entity-count")
  expect_match(attr(total, "revision_id"), ".")
  expect_match(attr(total, "store_schema_digest"), "^sha256:")
})

test_that("graft_measure() over a pinned view ignores later commits", {
  store <- local_measure_store()
  snapshot <- graft_snapshot(store)
  view <- graft_at(store, snapshot)

  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = test_graft_id("measure-entity-d"),
        label = "acid",
        preferred_name = "Formic acid"
      )
    ),
    graft_provenance(producer = "fixture", idempotency_key = "entities-v2")
  )

  expect_identical(graft_measure(store, "entity-count")$value, 4)
  expect_identical(graft_measure(view, "entity-count")$value, 3)
})

test_that("graft_measure() rejects unknown names, arguments, and dimensions", {
  store <- local_measure_store()
  expect_snapshot(error = TRUE, graft_measure(store, "nope"))
  expect_snapshot(
    error = TRUE,
    graft_measure(store, "entity-count", arguments = list(nope = 1))
  )
  expect_snapshot(
    error = TRUE,
    graft_measure(store, "entity-count", by = "nope")
  )
})
