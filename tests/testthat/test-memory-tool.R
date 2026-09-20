test_that("graft_tool returns a native JSON ContentToolResult", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft::graft_store(path, create = TRUE)
  source <- graft::graft_save(
    store,
    "The handbook source excerpt.",
    id = "metrics.md",
    media_type = "text/markdown"
  )
  note <- graft::graft_save(
    store,
    "An active customer has ordered within 30 days.",
    id = "metric:active-customer",
    media_type = "text/plain",
    dependencies = source
  )
  source_artifact <- graft::graft_read(store, source)
  note_artifact <- graft::graft_read(store, note)
  decision <- graft::graft_accept(
    store,
    x = note,
    stream = "metric:active-customer",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "project-assistance"
  )
  tool <- graft::graft_tool(
    store,
    stream = "metric:active-customer",
    purpose = "project-assistance",
    eligible = function() TRUE
  )

  expect_identical(tool@name, "recall_project_memory")
  expect_identical(tool@annotations$read_only_hint, TRUE)
  result <- tool()
  expect_identical(
    S7::S7_inherits(result, ellmer::ContentToolResult),
    TRUE
  )
  expect_s3_class(result@value, "json")
  payload <- jsonlite::fromJSON(result@value, simplifyVector = FALSE)
  expect_identical(payload$status, "accepted")
  expect_identical(payload$decision_id, decision@id)
  expect_identical(payload$stream, "metric:active-customer")
  expect_identical(payload$purpose, "project-assistance")
  expect_identical(payload$artifacts[[1L]]$data, note_artifact@data)
  expect_identical(payload$artifacts[[2L]]$data, source_artifact@data)
  expect_identical(
    payload$artifacts[[1L]]$ref$id,
    "metric:active-customer"
  )
  expect_identical(
    payload$artifacts[[1L]]$ref$revision,
    note@revision
  )
})

test_that("graft_tool checks eligibility afresh and does not write", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft::graft_store(path, create = TRUE)
  note <- graft::graft_save(
    store,
    "Reviewed content",
    id = "topic",
    media_type = "text/plain"
  )
  decision <- graft::graft_accept(
    store,
    x = note,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )
  allowed <- TRUE
  calls <- 0L
  eligible <- function() {
    calls <<- calls + 1L
    allowed
  }
  tool <- graft::graft_tool(
    store,
    stream = "topic",
    purpose = "test",
    eligible = eligible
  )
  before <- graft::graft_history(store, "topic")
  expect_s3_class(tool()@value, "json")
  allowed <- FALSE
  expect_error(tool(), class = "graft_error")
  allowed <- TRUE
  result <- tool()
  expect_identical(calls, 3L)
  expect_identical(
    jsonlite::fromJSON(result@value, simplifyVector = FALSE)$decision_id,
    decision@id
  )
  after <- graft::graft_history(store, "topic")
  expect_identical(
    vapply(before, \(item) item@id, character(1)),
    vapply(after, \(item) item@id, character(1))
  )
})

test_that("graft_tool returns current content without leaking store metadata", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft::graft_store(path, create = TRUE)
  first <- graft::graft_save(
    store,
    "First reviewed content",
    id = "topic",
    media_type = "text/plain"
  )
  first_decision <- graft::graft_accept(
    store,
    x = first,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )
  second <- graft::graft_save(
    store,
    "Corrected reviewed content",
    id = "topic",
    media_type = "text/plain"
  )
  second_artifact <- graft::graft_read(store, second)
  second_decision <- graft::graft_accept(
    store,
    x = second,
    stream = "topic",
    expected = first_decision,
    key = "review-2",
    actor = "test-reviewer",
    reason = "Corrected",
    purpose = "test"
  )
  tool <- graft::graft_tool(
    store,
    stream = "topic",
    purpose = "test",
    eligible = function() TRUE
  )
  payload <- jsonlite::fromJSON(tool()@value, simplifyVector = FALSE)
  expect_identical(payload$decision_id, second_decision@id)
  expect_identical(payload$artifacts[[1L]]$data, second_artifact@data)
  expect_match(
    tool()@value,
    "Corrected reviewed content",
    fixed = TRUE
  )
  expect_identical(grepl(path, tool()@value, fixed = TRUE), FALSE)
  expect_identical(grepl("connection", tool()@value, fixed = TRUE), FALSE)
  expect_identical(grepl("max_bytes", tool()@value, fixed = TRUE), FALSE)
  expect_identical(grepl("path", tool()@value, fixed = TRUE), FALSE)
})

test_that("graft_tool fixes the store handle at construction", {
  skip_if_not_installed("ellmer")

  first_path <- withr::local_tempdir("graft-tool-first-")
  first_store <- graft::graft_store(first_path, create = TRUE)
  first_ref <- graft::graft_save(first_store, "First store", id = "topic")
  graft::graft_accept(
    first_store,
    x = first_ref,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )

  second_path <- withr::local_tempdir("graft-tool-second-")
  second_store <- graft::graft_store(second_path, create = TRUE)
  second_ref <- graft::graft_save(second_store, "Second store", id = "topic")
  graft::graft_accept(
    second_store,
    x = second_ref,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )

  store <- first_store
  tool <- graft::graft_tool(
    store,
    stream = "topic",
    purpose = "test",
    eligible = function() TRUE
  )
  store <- second_store
  payload <- jsonlite::fromJSON(tool()@value, simplifyVector = FALSE)
  expect_identical(payload$artifacts[[1L]]$data, "First store")
})

test_that("graft_tool reports missing and withdrawn memory explicitly", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft::graft_store(path, create = TRUE)
  tool <- graft::graft_tool(
    store,
    stream = "topic",
    purpose = "test",
    eligible = function() TRUE
  )
  missing <- jsonlite::fromJSON(tool()@value, simplifyVector = FALSE)
  expect_identical(missing$status, "missing")
  expect_null(missing$decision_id)

  note <- graft::graft_save(store, "Reviewed", id = "topic")
  accepted <- graft::graft_accept(
    store,
    x = note,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )
  withdrawn <- graft::graft_withdraw(
    store,
    stream = "topic",
    expected = accepted,
    key = "withdraw-1",
    actor = "test-reviewer",
    reason = "Withdrawn"
  )
  result <- jsonlite::fromJSON(tool()@value, simplifyVector = FALSE)
  expect_identical(result$status, "withdrawn")
  expect_identical(result$decision_id, withdrawn@id)
  expect_null(result$roots)
  expect_null(result$artifacts)
})
