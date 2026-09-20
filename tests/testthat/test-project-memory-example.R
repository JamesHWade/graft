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
  expect_identical(saved$note_ref$id, "metric:active-customer")
  expect_identical(saved$source_ref$id, "metrics.md")
  expect_identical(saved$decision_id, saved$decision$id)
  expect_identical(
    helpers$read_project_memory(store)[c("note", "source")],
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
    class = "graft_artifact_error"
  )

  corrected <- helpers$save_project_memory(
    store,
    "An active customer has ordered within 60 days.",
    "metrics.md: active_customer = order_date >= today - 60 days",
    expected = first$decision_id
  )
  current <- helpers$read_project_memory(store)
  expect_identical(current$status, "accepted")
  expect_identical(current$note, corrected$note)
  expect_identical(current$source, corrected$source)
  expect_identical(current$decision_id, corrected$decision_id)
  expect_error(
    graft::graft_artifact_reuse(
      store,
      "metric:active-customer",
      first$decision_id,
      "project-assistance",
      eligible = TRUE
    ),
    class = "graft_artifact_error"
  )
  expect_error(
    helpers$save_project_memory(
      store,
      first$note,
      first$source,
      expected = NULL
    ),
    "already committed, but it is no longer current",
    class = "simpleError"
  )
  expect_identical(
    helpers$read_project_memory(store)$decision_id,
    corrected$decision_id
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
  withdrawn <- helpers$withdraw_project_memory(store, accepted$decision_id)
  expect_identical(withdrawn$status, "withdrawn")
  expect_identical(
    helpers$read_project_memory(store)[c("status", "note", "source")],
    list(status = "withdrawn", note = NULL, source = NULL)
  )
  expect_identical(
    graft::graft_artifact_read_decision(store, "metric:active-customer")$id,
    withdrawn$decision_id
  )
  expect_error(
    helpers$save_project_memory(store, accepted$note, accepted$source),
    "already committed, but it is no longer current",
    class = "simpleError"
  )
  expect_identical(
    helpers$read_project_memory(store)$status,
    "withdrawn"
  )
  expect_snapshot(cran = FALSE, error = TRUE, {
    helpers$withdraw_project_memory(store, accepted$decision_id)
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
  payload <- accepted$note_ref
  content_hash <- graft::graft_artifact_read(store, payload)$metadata$payload
  writeBin(
    charToRaw("tampered"),
    file.path(store$path, "content", content_hash)
  )
  expect_error(
    helpers$read_project_memory(store),
    class = "graft_artifact_error"
  )
})

test_that("the optional live tool is read-only and reports current state", {
  skip_if_not_installed("ellmer")
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
  tool <- helpers$project_memory_tool(store)
  expect_identical(tool@name, "recall_project_memory")
  expect_identical(tool@annotations$read_only_hint, TRUE)
  missing <- jsonlite::fromJSON(
    tool(question = "How do we count an active customer?"),
    simplifyVector = FALSE
  )
  expect_identical(missing$status, "missing")

  saved <- helpers$save_project_memory(
    store,
    "Reviewed note",
    "Reviewed source"
  )
  recalled <- jsonlite::fromJSON(
    tool(question = "How do we count an active customer?"),
    simplifyVector = FALSE
  )
  expect_identical(recalled$status, "accepted")
  expect_identical(recalled$note, saved$note)
  expect_identical(recalled$source, saved$source)

  helpers$withdraw_project_memory(store, saved$decision_id)
  withdrawn <- jsonlite::fromJSON(
    tool(question = "How do we count an active customer?"),
    simplifyVector = FALSE
  )
  expect_identical(withdrawn$status, "withdrawn")
  expect_identical(
    withdrawn$message,
    "There is no reviewed project memory to use. Ask the user to save one."
  )
})
