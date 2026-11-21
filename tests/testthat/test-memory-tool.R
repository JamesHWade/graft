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

test_that("graft_tool bounds UTF-8 text and retains omitted references", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft::graft_store(path, create = TRUE)
  text_ref <- graft::graft_save(
    store,
    "éclair and more text",
    id = "text",
    media_type = "text/plain"
  )
  binary_ref <- graft::graft_save(
    store,
    as.raw(0:7),
    id = "figure",
    media_type = "image/png"
  )
  root <- graft::graft_save(
    store,
    "The reviewed note.",
    id = "topic",
    media_type = "text/plain",
    dependencies = list(text_ref, binary_ref)
  )
  graft::graft_accept(
    store,
    x = root,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )

  tool <- graft::graft_tool(
    store,
    stream = "topic",
    purpose = "test",
    eligible = function() TRUE,
    max_text_bytes = 5L
  )
  payload <- jsonlite::fromJSON(tool()@value, simplifyVector = FALSE)
  artifacts <- payload$artifacts
  text_bytes <- sum(vapply(
    c(artifacts, payload$roots),
    function(artifact) {
      if (is.null(artifact$data)) 0L else nchar(artifact$data, type = "bytes")
    },
    integer(1)
  ))

  expect_lte(text_bytes, 5L)
  expect_identical(
    any(vapply(artifacts, `[[`, logical(1), "truncated")),
    TRUE
  )
  expect_identical(
    any(vapply(artifacts, `[[`, logical(1), "omitted")),
    TRUE
  )
  expect_identical(artifacts[[1L]]$ref$id, "topic")
  expect_null(payload$roots[[1L]]$data)
  expect_identical(payload$roots[[1L]]$ref$id, "topic")
  expect_identical(
    sort(vapply(payload$omitted, `[[`, character(1), "id")),
    sort(vapply(
      artifacts[vapply(artifacts, `[[`, logical(1), "omitted")],
      function(artifact) artifact$ref$id,
      character(1)
    ))
  )
  figure <- artifacts[[which(vapply(
    artifacts,
    function(artifact) identical(artifact$ref$id, "figure"),
    logical(1)
  ))]]
  expect_null(figure$data)
  expect_identical(figure$media_type, "image/png")
  expect_identical(figure$size, 8L)
})

test_that("graft_tool truncates on UTF-8 boundaries", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft::graft_store(path, create = TRUE)
  ref <- graft::graft_save(store, "é🙂z", id = "topic")
  graft::graft_accept(
    store,
    x = ref,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )
  tool <- graft::graft_tool(
    store,
    stream = "topic",
    purpose = "test",
    eligible = function() TRUE,
    max_text_bytes = 3L
  )

  artifact <- jsonlite::fromJSON(
    tool()@value,
    simplifyVector = FALSE
  )$artifacts[[1L]]
  expect_identical(artifact$data, "é")
  expect_identical(nchar(artifact$data, type = "bytes"), 2L)
  expect_identical(artifact$truncated, TRUE)
})

test_that("graft_tool can return metadata without text", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft::graft_store(path, create = TRUE)
  ref <- graft::graft_save(store, "Reviewed note", id = "topic")
  graft::graft_accept(
    store,
    x = ref,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )
  tool <- graft::graft_tool(
    store,
    stream = "topic",
    purpose = "test",
    eligible = function() TRUE,
    max_text_bytes = 0L
  )
  payload <- jsonlite::fromJSON(tool()@value, simplifyVector = FALSE)

  expect_identical(payload$text_bytes, 0L)
  expect_identical(payload$max_text_bytes, 0L)
  expect_identical(payload$artifacts[[1L]]$data, "")
  expect_identical(payload$artifacts[[1L]]$truncated, TRUE)
  expect_identical(payload$artifacts[[1L]]$omitted, TRUE)
  expect_identical(payload$omitted[[1L]]$id, "topic")
})

test_that("graft_tool validates its text limit", {
  skip_if_not_installed("ellmer")

  store <- graft::graft_store(withr::local_tempdir(), create = TRUE)
  expect_error(
    graft::graft_tool(
      store,
      stream = "topic",
      purpose = "test",
      eligible = function() TRUE,
      max_text_bytes = -1
    ),
    class = "graft_artifact_error"
  )
  expect_error(
    graft::graft_tool(
      store,
      stream = "topic",
      purpose = "test",
      eligible = function() TRUE,
      max_text_bytes = 1.5
    ),
    class = "graft_artifact_error"
  )
})

test_that("graft_tool distinguishes missing and withdrawn memory", {
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

  ref <- graft::graft_save(store, "Secret reviewed note", id = "topic")
  accepted <- graft::graft_accept(
    store,
    x = ref,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )
  graft::graft_withdraw(
    store,
    stream = "topic",
    expected = accepted,
    key = "withdraw-1",
    actor = "test-reviewer",
    reason = "Withdrawn"
  )
  withdrawn <- jsonlite::fromJSON(tool()@value, simplifyVector = FALSE)

  expect_identical(missing$status, "missing")
  expect_identical(withdrawn$status, "withdrawn")
  expect_identical(identical(missing$message, withdrawn$message), FALSE)
  expect_match(missing$message, "has been saved", fixed = TRUE)
  expect_match(withdrawn$message, "withdrawn", fixed = TRUE)
  expect_identical(
    grepl("Secret reviewed note", withdrawn$message, fixed = TRUE),
    FALSE
  )
})

test_that("graft_tool denies access before revealing retained content", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft::graft_store(path, create = TRUE)
  ref <- graft::graft_save(store, "Secret reviewed note", id = "topic")
  graft::graft_accept(
    store,
    x = ref,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )
  tool <- graft::graft_tool(
    store,
    stream = "topic",
    purpose = "test",
    eligible = function() FALSE
  )

  error <- tryCatch(tool(), error = identity)
  expect_s3_class(error, "graft_error")
  expect_identical(
    grepl("Secret reviewed note", conditionMessage(error), fixed = TRUE),
    FALSE
  )
  expect_identical(
    grepl(path, conditionMessage(error), fixed = TRUE),
    FALSE
  )
})

test_that("graft_tool display describes a past consultation", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  path <- withr::local_tempdir()
  store <- graft::graft_store(path, create = TRUE)
  ref <- graft::graft_save(store, "Reviewed note", id = "topic")
  graft::graft_accept(
    store,
    x = ref,
    stream = "topic",
    expected = NULL,
    key = "review-1",
    actor = "test-reviewer",
    reason = "Reviewed",
    purpose = "test"
  )
  tool <- graft::graft_tool(
    store,
    stream = "topic",
    purpose = "test",
    eligible = function() TRUE
  )

  display <- tool()@extra$display
  expect_s3_class(display, "shinychat_tool_result_display")
  expect_identical(display$label, "Project memory consulted")
  expect_match(display$value_preview, "consulted", fixed = TRUE)
})
