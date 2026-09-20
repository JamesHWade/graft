test_that("project memory starts missing and persists accepted note and source", {
  path <- system.file(
    "examples",
    "project-memory",
    "memory.R",
    package = "graft"
  )
  if (path == "") {
    path <- test_path(
      "..",
      "..",
      "inst",
      "examples",
      "project-memory",
      "memory.R"
    )
  }
  expect_identical(file.exists(path), TRUE)
  helpers <- new.env(parent = baseenv())
  sys.source(path, envir = helpers)

  store_path <- withr::local_tempdir()
  store <- helpers$open_project_memory(store_path)
  expect_identical(helpers$read_project_memory(store)$status, "missing")

  note <- "An active customer has ordered within 30 days."
  source <- "metrics.md: active_customer = order_date >= today - 30 days"
  saved <- helpers$save_project_memory(store, note, source)
  expect_identical(saved$status, "accepted")
  expect_identical(saved$note, note)
  expect_identical(saved$source, source)
  expect_identical(S7::prop(saved$note_ref, "id"), "metric:active-customer")
  expect_identical(S7::prop(saved$source_ref, "id"), "metrics.md")
  expect_identical(saved$decision_id, saved$decision@id)
  reread <- helpers$read_project_memory(store)
  expect_identical(
    reread[c("note", "source")],
    list(note = note, source = source)
  )

  reopened <- helpers$open_project_memory(store_path)
  reread <- helpers$read_project_memory(reopened)
  expect_identical(reread$status, "accepted")
  expect_identical(reread$decision_id, saved$decision_id)
  expect_identical(reread$note, note)
  expect_identical(reread$source, source)
})

test_that("project-memory corrections require the current predecessor", {
  path <- system.file(
    "examples",
    "project-memory",
    "memory.R",
    package = "graft"
  )
  if (path == "") {
    path <- test_path(
      "..",
      "..",
      "inst",
      "examples",
      "project-memory",
      "memory.R"
    )
  }
  expect_identical(file.exists(path), TRUE)
  helpers <- new.env(parent = baseenv())
  sys.source(path, envir = helpers)

  store <- helpers$open_project_memory(withr::local_tempdir())
  first <- helpers$save_project_memory(
    store,
    "An active customer has ordered within 30 days.",
    "metrics.md: active_customer = order_date >= today - 30 days"
  )
  expect_error(
    helpers$save_project_memory(
      store,
      "A stale correction must not publish.",
      "metrics.md: stale",
      expected = NULL
    ),
    class = "graft_error"
  )

  corrected <- helpers$save_project_memory(
    store,
    "An active customer has ordered within 60 days.",
    "metrics.md: active_customer = order_date >= today - 60 days",
    expected = first$decision
  )
  current <- helpers$read_project_memory(store)
  expect_identical(current$status, "accepted")
  expect_identical(current$note, corrected$note)
  expect_identical(current$source, corrected$source)
  expect_identical(current$decision_id, corrected$decision_id)
  expect_error(
    helpers$save_project_memory(
      store,
      first$note,
      first$source,
      expected = NULL
    ),
    class = "graft_error"
  )
  history <- graft::graft_history(
    store,
    stream = "metric:active-customer"
  )
  expect_identical(
    vapply(history, \(decision) decision@id, character(1)),
    c(first$decision_id, corrected$decision_id)
  )
})

test_that("withdrawal invalidates consultation and does not erase history", {
  path <- system.file(
    "examples",
    "project-memory",
    "memory.R",
    package = "graft"
  )
  if (path == "") {
    path <- test_path(
      "..",
      "..",
      "inst",
      "examples",
      "project-memory",
      "memory.R"
    )
  }
  expect_identical(file.exists(path), TRUE)
  helpers <- new.env(parent = baseenv())
  sys.source(path, envir = helpers)

  store <- helpers$open_project_memory(withr::local_tempdir())
  accepted <- helpers$save_project_memory(
    store,
    "Reviewed note",
    "Reviewed source"
  )
  withdrawn <- helpers$withdraw_project_memory(store, accepted$decision)
  expect_identical(withdrawn$status, "withdrawn")
  expect_identical(
    helpers$read_project_memory(store)[c("status", "note", "source")],
    list(status = "withdrawn", note = NULL, source = NULL)
  )
  expect_identical(
    graft::graft_history(store, "metric:active-customer")[[2L]]@id,
    withdrawn$decision_id
  )
  expect_error(
    helpers$withdraw_project_memory(store, accepted$decision),
    "There is no current accepted project-memory note to withdraw.",
    class = "simpleError"
  )
  expect_error(
    helpers$save_project_memory(store, accepted$note, accepted$source),
    class = "graft_error"
  )
  expect_identical(helpers$read_project_memory(store)$status, "withdrawn")
  expect_snapshot(cran = FALSE, error = TRUE, {
    helpers$withdraw_project_memory(store, accepted$decision)
  })
})

test_that("project-memory reads fail closed when retained content is corrupt", {
  path <- system.file(
    "examples",
    "project-memory",
    "memory.R",
    package = "graft"
  )
  if (path == "") {
    path <- test_path(
      "..",
      "..",
      "inst",
      "examples",
      "project-memory",
      "memory.R"
    )
  }
  expect_identical(file.exists(path), TRUE)
  helpers <- new.env(parent = baseenv())
  sys.source(path, envir = helpers)

  store <- helpers$open_project_memory(withr::local_tempdir())
  accepted <- helpers$save_project_memory(
    store,
    "Reviewed note",
    "Reviewed source"
  )
  artifact <- graft::graft_read(store, accepted$note_ref)
  content_hash <- digest::digest(
    artifact@bytes,
    algo = "sha256",
    serialize = FALSE
  )
  writeBin(
    charToRaw("tampered"),
    file.path(store@path, "content", content_hash)
  )
  expect_error(helpers$read_project_memory(store), class = "graft_error")
})
