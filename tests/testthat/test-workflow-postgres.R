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

test_that("two PostgreSQL scopes cannot observe each other through any public operation", {
  connection <- local_artifact_postgres()
  missing_digest <- paste(rep("0", 64L), collapse = "")
  missing_ref <- ArtifactRef(id = "missing:note", revision = missing_digest)

  DBI::dbWithTransaction(connection, {
    scope_a <- graft_store_postgres(connection, "scope-a", create = TRUE)
    scope_b <- graft_store_postgres(connection, "scope-b", create = TRUE)

    # Save distinct and identical content in both scopes.
    shared_a <- graft_save(scope_a, "Identical shared payload", "shared:note")
    shared_b <- graft_save(scope_b, "Identical shared payload", "shared:note")
    expect_identical(shared_a, shared_b)

    secret_source_b <- graft_save(scope_b, "Scope B secret source", "b:source")
    secret_note_b <- graft_save(
      scope_b,
      "Scope B confidential note",
      "b:note",
      dependencies = secret_source_b
    )
    selection_b <- graft_select(scope_b, secret_note_b)
    decision_b <- graft_accept(
      scope_b,
      selection_b,
      stream = "b:stream",
      expected = NULL,
      key = "b-accept-1",
      actor = "reviewer-b",
      reason = "Scope B review",
      purpose = "assist"
    )
    accept_shared_a <- graft_accept(
      scope_a,
      shared_a,
      stream = "shared:stream",
      expected = NULL,
      key = "a-shared-1",
      actor = "reviewer-a",
      reason = "Scope A review",
      purpose = "assist"
    )
    accept_shared_b <- graft_accept(
      scope_b,
      shared_b,
      stream = "shared:stream",
      expected = NULL,
      key = "b-shared-1",
      actor = "reviewer-b",
      reason = "Scope B review",
      purpose = "assist"
    )

    # 1. graft_read(): scope B's reference fails identically to a missing one.
    err_read_b <- tryCatch(graft_read(scope_a, secret_note_b), error = identity)
    err_read_missing <- tryCatch(
      graft_read(scope_a, missing_ref),
      error = identity
    )
    expect_s3_class(err_read_b, "graft_artifact_error")
    expect_identical(class(err_read_b), class(err_read_missing))
    expect_identical(
      conditionMessage(err_read_b),
      conditionMessage(err_read_missing)
    )

    # 2. graft_read_selection() & dependency traversal: invisible and indistinguishable.
    err_sel_b <- tryCatch(
      graft_read_selection(scope_a, selection_b@id),
      error = identity
    )
    err_sel_missing <- tryCatch(
      graft_read_selection(scope_a, missing_digest),
      error = identity
    )
    expect_s3_class(err_sel_b, "graft_artifact_error")
    expect_identical(class(err_sel_b), class(err_sel_missing))
    expect_identical(
      conditionMessage(err_sel_b),
      conditionMessage(err_sel_missing)
    )

    err_select_b <- tryCatch(
      graft_select(scope_a, secret_note_b),
      error = identity
    )
    err_select_missing <- tryCatch(
      graft_select(scope_a, missing_ref),
      error = identity
    )
    expect_s3_class(err_select_b, "graft_artifact_error")
    expect_identical(class(err_select_b), class(err_select_missing))
    expect_identical(
      conditionMessage(err_select_b),
      conditionMessage(err_select_missing)
    )

    err_dep_b <- tryCatch(
      graft_save(
        scope_a,
        "Derived in A",
        "a:derived",
        dependencies = secret_note_b
      ),
      error = identity
    )
    err_dep_missing <- tryCatch(
      graft_save(
        scope_a,
        "Derived in A",
        "a:derived",
        dependencies = missing_ref
      ),
      error = identity
    )
    expect_s3_class(err_dep_b, "graft_artifact_error")
    expect_identical(class(err_dep_b), class(err_dep_missing))
    expect_identical(
      conditionMessage(err_dep_b),
      conditionMessage(err_dep_missing)
    )

    # 3. graft_recall(), graft_history(), graft_streams(): scope B is invisible.
    recall_b_from_a <- graft_recall(
      scope_a,
      stream = "b:stream",
      purpose = "assist",
      eligible = TRUE
    )
    expect_identical(recall_b_from_a@status, "missing")
    expect_null(recall_b_from_a@decision)
    expect_identical(graft_history(scope_a, "b:stream"), list())

    streams_a <- graft_streams(scope_a)
    expect_identical(
      vapply(streams_a, \(x) x@stream, character(1)),
      "shared:stream"
    )
    expect_identical(streams_a[[1L]]@id, accept_shared_a@id)

    # 4. graft_tool() and graft_tools(): no content, display, or listing leakage.
    if (requireNamespace("ellmer", quietly = TRUE)) {
      single_tool <- graft_tool(
        scope_a,
        stream = "b:stream",
        purpose = "assist",
        eligible = function() TRUE
      )
      res_single <- single_tool()
      expect_identical(res_single@extra$graft$status, "missing")
      expect_identical(
        grepl("Scope B", res_single@value, fixed = TRUE),
        FALSE
      )
      if (!is.null(res_single@extra$display)) {
        expect_identical(
          grepl("Scope B", res_single@extra$display$text, fixed = TRUE),
          FALSE
        )
      }

      multi <- graft_tools(
        scope_a,
        purpose = "assist",
        eligible = function(stream) TRUE
      )
      listed <- multi$list_project_memory()
      expect_identical(listed@extra$graft$streams, "shared:stream")
      expect_identical(grepl("b:stream", listed@value, fixed = TRUE), FALSE)

      recalled_b <- multi$recall_project_memory(stream = "b:stream")
      expect_identical(recalled_b@extra$graft$status, "missing")
      expect_identical(
        grepl("Scope B", recalled_b@value, fixed = TRUE),
        FALSE
      )
    }

    # 5. Identical content stays independent across scopes.
    payload_digest <- digest::digest(
      graft_read(scope_a, shared_a)@bytes,
      algo = "sha256",
      serialize = FALSE
    )
    content_rows <- DBI::dbGetQuery(
      connection,
      "SELECT scope, COUNT(*) AS n FROM graft_artifact_objects WHERE kind = 'content' AND object_key = $1 GROUP BY scope ORDER BY scope",
      params = list(payload_digest)
    )
    expect_identical(content_rows$scope, c("scope-a", "scope-b"))
    expect_identical(as.integer(content_rows$n), c(1L, 1L))
    revision_rows <- DBI::dbGetQuery(
      connection,
      "SELECT scope, COUNT(*) AS n FROM graft_artifact_objects WHERE kind = 'revisions' AND object_key = $1 GROUP BY scope ORDER BY scope",
      params = list(shared_a@revision)
    )
    expect_identical(revision_rows$scope, c("scope-a", "scope-b"))
    expect_identical(as.integer(revision_rows$n), c(1L, 1L))
    graft_withdraw(
      scope_b,
      stream = "shared:stream",
      expected = accept_shared_b,
      key = "b-withdraw-1",
      actor = "reviewer-b",
      reason = "Withdrawn in B only"
    )
    expect_identical(
      graft_recall(scope_a, "shared:stream", "assist", eligible = TRUE)@status,
      "accepted"
    )
    expect_identical(
      graft_read(scope_a, shared_a)@data,
      "Identical shared payload"
    )

    # 6. Retained records never serialize store handles or scope keys.
    stored_payloads <- DBI::dbGetQuery(
      connection,
      "SELECT payload FROM graft_artifact_objects WHERE scope = 'scope-a'"
    )$payload
    for (raw_payload in stored_payloads) {
      text_payload <- rawToChar(raw_payload)
      expect_identical(grepl("PqConnection", text_payload, fixed = TRUE), FALSE)
      expect_identical(grepl("scope-a", text_payload, fixed = TRUE), FALSE)
    }
  })

  # 7. Reconnecting requires the host to rebind its scope explicitly.
  DBI::dbWithTransaction(connection, {
    rebound_a <- graft_store_postgres(connection, "scope-a")
    expect_identical(rebound_a@scope, "scope-a")
    expect_identical(
      graft_recall(
        rebound_a,
        "shared:stream",
        "assist",
        eligible = TRUE
      )@status,
      "accepted"
    )
    expect_error(
      graft_read(rebound_a, secret_note_b),
      class = "graft_artifact_error"
    )
  })
})

test_that("graft_read_vocabulary() isolates PostgreSQL scopes identically to missing", {
  fixture <- local_vocabulary()
  connection <- local_artifact_postgres()
  missing_digest <- paste(rep("0", 64L), collapse = "")

  DBI::dbWithTransaction(connection, {
    scope_a <- graft_store_postgres(connection, "vocab-a", create = TRUE)
    scope_b <- graft_store_postgres(connection, "vocab-b", create = TRUE)
    release_b <- graft_publish_vocabulary(scope_b, fixture$path)

    err_b <- tryCatch(
      graft_read_vocabulary(scope_a, release_b),
      error = identity
    )
    err_missing <- tryCatch(
      graft_read_vocabulary(scope_a, missing_digest),
      error = identity
    )
    expect_s3_class(err_b, "graft_artifact_error")
    expect_identical(class(err_b), class(err_missing))
    expect_identical(conditionMessage(err_b), conditionMessage(err_missing))
  })
})
