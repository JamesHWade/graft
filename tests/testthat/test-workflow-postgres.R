test_that("public workflow values survive PostgreSQL commits and scope reopening", {
  connection <- local_artifact_postgres()
  DBI::dbWithTransaction(connection, {
    store <- graft_store_postgres(connection, "project", create = TRUE)
    source <- graft_save(store, "Source definition", "source")
    note <- graft_save(
      store,
      "Reviewed definition",
      "note",
      dependencies = source
    )
    accepted <- graft_accept(
      store,
      note,
      stream = "definition",
      expected = NULL,
      key = "first-review",
      actor = "reviewer",
      reason = "Checked against source",
      purpose = "chat"
    )
    local <- graft_store(withr::local_tempdir(), create = TRUE)
    expect_identical(graft_save(local, "Source definition", "source"), source)
  })
  DBI::dbWithTransaction(connection, {
    store <- graft_store_postgres(connection, "project")
    recalled <- graft_recall(store, "definition", "chat", eligible = TRUE)
    expect_identical(recalled@status, "accepted")
    expect_identical(recalled@decision, accepted)
    expect_identical(recalled@roots[[1L]]@data, "Reviewed definition")
    expect_identical(recalled@roots[[1L]]@dependencies, list(source))
    expect_length(recalled@artifacts, 2L)
    other <- graft_store_postgres(connection, "other-project", create = TRUE)
    expect_identical(
      graft_recall(other, "definition", "chat", eligible = TRUE)@status,
      "missing"
    )
    expect_error(graft_read(other, note), class = "graft_artifact_error")
  })

  DBI::dbBegin(connection)
  store <- graft_store_postgres(connection, "project")
  corrected <- graft_save(store, "Corrected definition", "note")
  graft_accept(
    store,
    corrected,
    stream = "definition",
    expected = accepted,
    key = "correction",
    actor = "reviewer",
    reason = "Checked correction",
    purpose = "chat"
  )
  DBI::dbRollback(connection)
  DBI::dbWithTransaction(connection, {
    store <- graft_store_postgres(connection, "project")
    expect_identical(
      graft_recall(store, "definition", "chat", eligible = TRUE)@decision,
      accepted
    )
    expect_error(graft_read(store, corrected), class = "graft_artifact_error")
    withdrawn <- graft_withdraw(
      store,
      "definition",
      expected = accepted,
      key = "withdrawal",
      actor = "reviewer",
      reason = "No longer current"
    )
  })
  DBI::dbWithTransaction(connection, {
    store <- graft_store_postgres(connection, "project")
    recalled <- graft_recall(store, "definition", "chat", eligible = TRUE)
    expect_identical(recalled@status, "withdrawn")
    expect_identical(recalled@decision, withdrawn)
    expect_null(recalled@selection)
    expect_length(recalled@artifacts, 0L)
    expect_identical(
      graft_history(store, "definition"),
      list(accepted, withdrawn)
    )
    expect_identical(graft_read(store, note)@data, "Reviewed definition")
  })
  expect_error(
    graft_history(store, "definition"),
    class = "graft_artifact_error"
  )
})

test_that("graft_streams() lists PostgreSQL streams within one scope", {
  connection <- local_artifact_postgres()
  DBI::dbWithTransaction(connection, {
    store <- graft_store_postgres(connection, "project", create = TRUE)
    expect_identical(graft_streams(store), list())
    ref <- graft_save(store, "report", "report")
    for (stream in c("project:b", "project:a")) {
      graft_accept(
        store,
        ref,
        stream,
        expected = NULL,
        key = stream,
        actor = "reviewer",
        reason = "reviewed",
        purpose = "kept"
      )
    }
    other <- graft_store_postgres(connection, "other", create = TRUE)
    graft_accept(
      other,
      graft_save(other, "report", "report"),
      "elsewhere",
      expected = NULL,
      key = "elsewhere",
      actor = "reviewer",
      reason = "reviewed",
      purpose = "kept"
    )
    expect_identical(
      vapply(graft_streams(store), \(x) x@stream, character(1)),
      c("project:a", "project:b")
    )
    expect_error(
      graft_streams(store, max_streams = 1L),
      class = "graft_artifact_error"
    )
  })
})

test_that("graft_streams() rejects a malformed PostgreSQL decision key", {
  connection <- local_artifact_postgres()
  DBI::dbWithTransaction(connection, {
    store <- graft_store_postgres(connection, "project", create = TRUE)
    graft_accept(
      store,
      graft_save(store, "report", "report"),
      "project:a",
      expected = NULL,
      key = "project:a",
      actor = "reviewer",
      reason = "reviewed",
      purpose = "kept"
    )
    DBI::dbExecute(
      connection,
      paste(
        "INSERT INTO graft_artifact_objects (scope, kind, object_key, payload)",
        "VALUES ($1, 'decisions', $2, $3)"
      ),
      params = list(
        "project",
        paste0(strrep("a", 64L), "x"),
        list(charToRaw("{}"))
      )
    )
    expect_error(graft_streams(store), class = "graft_artifact_error")
  })
})
