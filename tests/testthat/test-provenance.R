test_that("graft provenance validates and freezes its public properties", {
  provenance <- graft_provenance(
    producer = "workflow",
    version = "1.2.0",
    run_id = "run-42",
    idempotency_key = "result-42",
    metadata = list(stage = "reviewed")
  )

  expect_s7_class(provenance, graft:::GraftProvenance)
  expect_identical(provenance@producer, "workflow")
  expect_identical(provenance@version, "1.2.0")
  expect_identical(provenance@run_id, "run-42")
  expect_identical(provenance@idempotency_key, "result-42")
  expect_identical(provenance@metadata, list(stage = "reviewed"))
  expect_snapshot(error = TRUE, provenance@producer <- "other")
})

test_that("graft provenance rejects malformed inputs", {
  expect_snapshot(error = TRUE, graft_provenance(""))
  expect_snapshot(error = TRUE, graft_provenance("workflow", run_id = ""))
  expect_snapshot(
    error = TRUE,
    graft_provenance("workflow", metadata = data.frame(x = 1))
  )
})

test_that("graft provenance is revalidated at API boundaries", {
  tampered <- graft_provenance("workflow")
  data <- graft:::provenance_data(tampered)
  data$producer <- ""
  attr(tampered, ".data") <- data

  expect_snapshot(
    error = TRUE,
    graft:::as_graft_provenance(tampered, "provenance")
  )
  expect_snapshot(
    error = TRUE,
    graft:::provenance_batch(tampered, "batch-id")
  )
})
