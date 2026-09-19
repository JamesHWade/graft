test_that("PostgreSQL isolates exact artifacts and all selected dependencies", {
  connection <- local_artifact_postgres()
  DBI::dbWithTransaction(connection, {
    first <- graft_artifact_store_postgres(connection, "first", create = TRUE)
    second <- graft_artifact_store_postgres(connection, "second", create = TRUE)
    local <- graft_artifact_store(withr::local_tempdir(), create = TRUE)
    bytes <- as.raw(c(0, 255, 13))
    ref <- graft_artifact_save(
      first,
      "source",
      bytes,
      "application/octet-stream"
    )
    expect_identical(
      ref,
      graft_artifact_save(local, "source", bytes, "application/octet-stream")
    )
    expect_error(
      graft_artifact_read(second, ref),
      class = "graft_artifact_error"
    )
    expect_error(
      graft_artifact_save(
        second,
        "derived",
        charToRaw("text"),
        "text/plain",
        dependencies = list(ref)
      ),
      class = "graft_artifact_error"
    )
    derived <- graft_artifact_save(
      first,
      "derived",
      charToRaw("text"),
      "text/plain",
      dependencies = list(ref)
    )
    selection <- graft_artifact_select(first, list(derived))
    expect_error(
      graft_artifact_read_selection(second, selection),
      class = "graft_artifact_error"
    )
    decision <- graft_artifact_decide(
      first,
      "subject",
      "review",
      NULL,
      selection,
      "accept",
      "reader",
      "explicit approval",
      "context"
    )
    expect_null(graft_artifact_read_decision(second, "subject"))
    expect_error(
      graft_artifact_read_decision(second, "subject", decision$id),
      class = "graft_artifact_error"
    )
    expect_length(
      graft_artifact_reuse(
        first,
        "subject",
        decision$id,
        "context",
        TRUE
      )$selection$artifacts,
      2L
    )
    expect_identical(graft_artifact_read(first, ref)$bytes, bytes)
  })
  DBI::dbWithTransaction(connection, {
    reopened <- graft_artifact_store_postgres(connection, "first")
    expect_identical(graft_artifact_read(reopened, ref)$bytes, bytes)
    expect_identical(
      graft_artifact_read_decision(reopened, "subject"),
      decision
    )
  })
  expect_error(
    graft_artifact_read(reopened, ref),
    class = "graft_artifact_error"
  )
})

test_that("PostgreSQL acceptance is atomic and retries retain historical identity", {
  connection <- local_artifact_postgres()
  DBI::dbWithTransaction(connection, {
    store <- graft_artifact_store_postgres(connection, "reader", create = TRUE)
    ref <- graft_artifact_save(
      store,
      "memory",
      charToRaw("first"),
      "text/plain"
    )
    selected <- graft_artifact_select(store, list(ref))
    first <- graft_artifact_decide(
      store,
      "memory",
      "a",
      NULL,
      selected,
      "accept",
      "reader",
      "request",
      "context"
    )
  })
  DBI::dbBegin(connection)
  store <- graft_artifact_store_postgres(connection, "reader")
  other <- graft_artifact_save(
    store,
    "memory",
    charToRaw("correction"),
    "text/plain"
  )
  other_selection <- graft_artifact_select(store, list(other))
  correction <- graft_artifact_decide(
    store,
    "memory",
    "b",
    first$id,
    other_selection,
    "accept",
    "reader",
    "correction",
    "context"
  )
  DBI::dbRollback(connection)
  DBI::dbWithTransaction(connection, {
    store <- graft_artifact_store_postgres(connection, "reader")
    expect_error(
      graft_artifact_read(store, other),
      class = "graft_artifact_error"
    )
    expect_identical(graft_artifact_read_decision(store, "memory"), first)
    expect_error(
      graft_artifact_decide(
        store,
        "memory",
        "stale",
        NULL,
        selected,
        "accept",
        "reader",
        "request",
        "context"
      ),
      class = "graft_artifact_error"
    )
    withdrawal <- graft_artifact_decide(
      store,
      "memory",
      "withdraw",
      first$id,
      selected,
      "withdraw",
      "reader",
      "archive",
      "context"
    )
    expect_identical(
      graft_artifact_decide(
        store,
        "memory",
        "a",
        NULL,
        selected,
        "accept",
        "reader",
        "request",
        "context"
      ),
      first
    )
    expect_error(
      graft_artifact_reuse(store, "memory", first$id, "context", TRUE),
      class = "graft_artifact_error"
    )
    expect_identical(graft_artifact_read_decision(store, "memory"), withdrawal)
    expect_identical(graft_artifact_read(store, ref)$bytes, charToRaw("first"))
  })
})

test_that("PostgreSQL scope locks reject a competing writer until commit", {
  connection <- local_artifact_postgres()
  second <- DBI::dbConnect(RPostgres::Postgres())
  withr::defer(DBI::dbDisconnect(second))
  schema <- DBI::dbGetQuery(connection, "SELECT current_schema() AS name")$name
  DBI::dbExecute(
    second,
    paste("SET search_path TO", DBI::dbQuoteIdentifier(second, schema))
  )
  DBI::dbWithTransaction(connection, {
    graft_artifact_store_postgres(connection, "reader", create = TRUE)
  })
  DBI::dbBegin(connection)
  graft_artifact_store_postgres(connection, "reader")
  DBI::dbBegin(second)
  DBI::dbExecute(second, "SET LOCAL lock_timeout = '100ms'")
  expect_error(
    graft_artifact_store_postgres(second, "reader"),
    class = "simpleError"
  )
  DBI::dbRollback(second)
  DBI::dbCommit(connection)
  DBI::dbWithTransaction(second, {
    expect_s3_class(
      graft_artifact_store_postgres(second, "reader"),
      "graft_artifact_store"
    )
  })
})

test_that("PostgreSQL reads enforce byte bounds and reject corrupt metadata", {
  connection <- local_artifact_postgres()
  DBI::dbWithTransaction(connection, {
    store <- graft_artifact_store_postgres(connection, "reader", create = TRUE)
    ref <- graft_artifact_save(
      store,
      "text",
      charToRaw("bounded"),
      "text/plain"
    )
    bounded <- graft_artifact_store_postgres(
      connection,
      "reader",
      max_bytes = 1
    )
    expect_error(
      graft_artifact_read(bounded, ref),
      class = "graft_artifact_error"
    )
    DBI::dbExecute(
      connection,
      "UPDATE graft_artifact_objects SET payload = $1 WHERE scope = 'reader' AND kind = 'revisions'",
      params = list(list(charToRaw("{}")))
    )
    expect_error(
      graft_artifact_read(store, ref),
      class = "graft_artifact_error"
    )
  })
})

test_that("PostgreSQL vocabulary releases stay within their host scope", {
  fixture <- local_vocabulary()
  connection <- local_artifact_postgres()
  DBI::dbWithTransaction(connection, {
    first <- graft_artifact_store_postgres(connection, "first", create = TRUE)
    second <- graft_artifact_store_postgres(connection, "second", create = TRUE)
    selection <- graft_vocabulary_publish(first, fixture$path)
    retained <- graft_vocabulary_read(first, selection)
    expect_identical(
      selection,
      graft_vocabulary_publish(fixture$store, fixture$path)
    )
    expect_error(
      graft_vocabulary_read(second, selection),
      class = "graft_artifact_error"
    )
  })
  withr::local_envvar(DATA_DICT = "/missing/data-dict")
  DBI::dbWithTransaction(connection, {
    reopened <- graft_artifact_store_postgres(connection, "first")
    expect_identical(graft_vocabulary_read(reopened, selection), retained)
  })
})
