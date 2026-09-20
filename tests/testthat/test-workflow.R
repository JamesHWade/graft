test_that("workflow saves exact revisions and reopens them", {
  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  source <- graft_save(store, "source café", "source")
  binary <- graft_save(store, as.raw(c(0L, 1L, 255L)), "binary")
  original <- graft_save(
    store,
    "original report",
    "report",
    dependencies = source
  )
  corrected <- graft_save(
    store,
    "corrected report",
    "report",
    dependencies = source
  )

  reopened <- graft_store(path)
  expect_identical(graft_read(reopened, source)@data, "source café")
  expect_identical(graft_read(reopened, original)@data, "original report")
  expect_identical(graft_read(reopened, corrected)@data, "corrected report")
  expect_identical(graft_read(reopened, binary)@data, as.raw(c(0L, 1L, 255L)))
  expect_length(unique(c(original@revision, corrected@revision)), 2L)
  expect_identical(graft_read(reopened, original)@dependencies[[1L]], source)
})

test_that("workflow accepts, corrects, recalls, withdraws, and retains history", {
  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  original <- graft_save(store, "original", "report")
  corrected <- graft_save(store, "corrected", "report")

  first <- graft_accept(
    store,
    original,
    "project-memory",
    expected = NULL,
    key = "review-1",
    actor = "reviewer",
    reason = "reviewed",
    purpose = "research"
  )
  expect_identical(first@action, "accept")
  expect_identical(
    graft_accept(
      store,
      original,
      "project-memory",
      expected = NULL,
      key = "review-1",
      actor = "reviewer",
      reason = "reviewed",
      purpose = "research"
    )@id,
    first@id
  )

  second <- graft_accept(
    store,
    corrected,
    "project-memory",
    expected = first,
    key = "review-2",
    actor = "reviewer",
    reason = "corrected",
    purpose = "research"
  )
  recalled <- graft_recall(store, "project-memory", "research", TRUE)
  expect_identical(recalled@status, "accepted")
  expect_identical(recalled@decision@id, second@id)
  expect_identical(recalled@roots[[1L]]@data, "corrected")

  expect_error(
    graft_accept(
      store,
      original,
      "project-memory",
      expected = first,
      key = "review-stale",
      actor = "reviewer",
      reason = "stale",
      purpose = "research"
    ),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_accept(
      store,
      original,
      "project-memory",
      expected = NULL,
      key = "review-1",
      actor = "reviewer",
      reason = "reviewed",
      purpose = "research"
    ),
    class = "graft_stale_review_error"
  )

  altered <- second
  altered@selection <- first@selection
  altered@purpose <- "changed-in-memory"
  withdrawn <- graft_withdraw(
    store,
    "project-memory",
    expected = altered,
    key = "withdraw-1",
    actor = "reviewer",
    reason = "withdrawn"
  )
  expect_identical(withdrawn@action, "withdraw")
  after <- graft_recall(store, "project-memory", "research", TRUE)
  expect_identical(after@status, "withdrawn")
  expect_identical(after@decision@id, withdrawn@id)
  expect_null(after@selection)
  expect_length(after@artifacts, 0L)
  expect_error(
    graft_recall(store, "project-memory", "other-purpose", TRUE),
    class = "graft_purpose_error"
  )

  history <- graft_history(store, "project-memory")
  expect_length(history, 3L)
  expect_identical(
    vapply(history, \(x) x@action, character(1)),
    c(
      "accept",
      "accept",
      "withdraw"
    )
  )
  expect_error(
    graft_withdraw(
      store,
      "project-memory",
      expected = NULL,
      key = "withdraw-missing",
      actor = "reviewer",
      reason = "withdrawn"
    ),
    class = "graft_value_error"
  )
})

test_that("recall checks eligibility before lookup and rejects corrupt payloads", {
  expect_error(
    graft_recall(
      list(),
      "missing-stream",
      "research",
      eligible = FALSE
    ),
    class = "graft_ineligible_error"
  )

  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  ref <- graft_save(store, "retained", "note")
  graft_accept(
    store,
    ref,
    "corrupt-stream",
    expected = NULL,
    key = "review-1",
    actor = "reviewer",
    reason = "reviewed",
    purpose = "research"
  )
  artifact <- graft_read(store, ref)
  payload <- graft:::artifact_path(
    store,
    "content",
    graft:::artifact_sha(artifact@bytes)
  )
  writeBin(charToRaw("tampered"), payload)
  expect_error(
    graft_recall(store, "corrupt-stream", "research", TRUE),
    class = "graft_artifact_error"
  )
  expect_length(graft_history(store, "corrupt-stream"), 1L)
})

test_that("exact reads do not publish new objects and strings are content", {
  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  file <- tempfile(fileext = ".bin")
  writeBin(as.raw(c(1L, 2L, 3L)), file)
  file_ref <- graft_save_file(store, file, id = "file")
  expect_identical(graft_read(store, file_ref)@bytes, as.raw(c(1L, 2L, 3L)))
  ref <- graft_save(store, "a path-looking string", "literal")
  before <- sort(list.files(path, recursive = TRUE, all.files = TRUE))
  value <- graft_read(store, ref)
  after <- sort(list.files(path, recursive = TRUE, all.files = TRUE))
  expect_identical(value@data, "a path-looking string")
  expect_identical(after, before)
  expect_error(
    graft_save(store, list(value = 1), "bad"),
    class = "graft_input_error"
  )
})

test_that("recall rejects a head that changes after materialization", {
  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  ref <- graft_save(store, "retained", "note")
  accepted <- graft_accept(
    store,
    ref,
    "changing-stream",
    expected = NULL,
    key = "review-1",
    actor = "reviewer",
    reason = "reviewed",
    purpose = "research"
  )
  original_materialize <- graft:::artifact_materialize
  local_mocked_bindings(
    artifact_materialize = function(store, refs) {
      values <- original_materialize(store, refs)
      graft_withdraw(
        store,
        "changing-stream",
        expected = accepted,
        key = "withdraw-during-read",
        actor = "reviewer",
        reason = "changed"
      )
      values
    }
  )
  expect_error(
    graft_recall(store, "changing-stream", "research", TRUE),
    class = "graft_stale_review_error"
  )
})

test_that("text decoding rejects invalid UTF-8 and embedded NUL bytes", {
  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  invalid <- graft_save(store, as.raw(255L), "invalid", "text/plain")
  nul <- graft_save(store, as.raw(c(97L, 0L, 98L)), "nul", "text/plain")
  expect_error(
    graft_read(store, invalid),
    class = "graft_artifact_decode_error"
  )
  expect_error(graft_read(store, nul), class = "graft_artifact_decode_error")
})
