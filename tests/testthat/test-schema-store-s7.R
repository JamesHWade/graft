test_that("GraftSchema exposes immutable semantic contracts", {
  schema <- graft_schema(tempest_manifest_path())

  expect_identical(S7::S7_inherits(schema, GraftSchema), TRUE)
  expect_identical(schema@name, "tempest-artifacts")
  expect_identical(schema@version, "0.1.0")
  expect_identical(
    schema@path,
    normalizePath(tempest_manifest_path(), winslash = "/", mustWork = TRUE)
  )
  expect_named(
    schema@digests,
    c("build_digest", "source_digest", "structural_digest"),
    ignore.order = TRUE
  )
  expect_identical(schema@build_digest, schema@digests$build_digest)
  expect_named(schema@classes)
  expect_identical(
    S7::S7_inherits(schema@classes$Entity, ClassContract),
    TRUE
  )
  expect_identical(
    S7::S7_inherits(schema@classes$Entity@slots$id, SlotContract),
    TRUE
  )
  expect_identical(schema@classes$Entity@slots$id@identifier, TRUE)

  manifest <- schema@manifest
  manifest$schema$name <- "tampered"
  expect_identical(schema@name, "tempest-artifacts")

  mutate_schema_name <- function() {
    schema@name <- "tampered"
  }
  setter <- rlang::catch_cnd(mutate_schema_name())
  expect_s3_class(setter, "error")
  expect_match(conditionMessage(setter), "read-only")
})

test_that("schema and store displays stay concise", {
  schema <- graft_schema(tempest_manifest_path())
  schema_output <- capture.output(print(schema))

  expect_length(schema_output, 3L)
  expect_match(schema_output[[1L]], "^<GraftSchema> tempest-artifacts")
  expect_match(schema_output[[2L]], "classes:")
  expect_match(schema_output[[3L]], "digest:")
  expect_length(grep("manifest|slots|relations", schema_output), 0L)

  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))
  store_output <- capture.output(print(store))

  expect_length(store_output, 4L)
  expect_match(store_output[[1L]], "^<GraftStore>")
  expect_match(store_output[[2L]], "schema: tempest-artifacts")
  expect_match(store_output[[3L]], "path:")
  expect_match(store_output[[4L]], "mode:.*writable, open")
  expect_length(grep("connection|capabilities|environment", store_output), 0L)
})

test_that("GraftSchema rejects malformed construction and tampering", {
  compiled <- load_schema_manifest(tempest_manifest_path())
  expect_identical(is.object(compiled), FALSE)
  internal_error <- rlang::catch_cnd(as_graft_schema_internal(compiled))
  expect_s3_class(internal_error, "graft_schema_error")

  malformed <- new.env(parent = emptyenv())
  condition <- rlang::catch_cnd(GraftSchema(malformed))
  expect_s3_class(condition, "error")
  expect_match(conditionMessage(condition), "invalid")

  schema <- graft_schema(tempest_manifest_path())
  state <- attr(schema, ".state", exact = TRUE)
  state$classes <- list()
  condition <- rlang::catch_cnd(as_graft_schema_internal(schema))
  expect_s3_class(condition, "graft_schema_integrity_error")
})

test_that("graft_open initializes and reopens one store identity", {
  schema <- graft_schema(tempest_manifest_path())
  path <- withr::local_tempfile(fileext = ".duckdb")
  first <- graft_open(schema, path, okf = "disabled")
  first_id <- first@id

  expect_identical(S7::S7_inherits(first, GraftStore), TRUE)
  expect_identical(first@schema, schema)
  expect_identical(first@read_only, FALSE)
  expect_identical(first@closed, FALSE)
  expect_identical(first@capabilities$writable, TRUE)
  backend <- as_graft_store_internal(first)
  expect_identical(first@path, backend$path)
  expect_identical(is.object(backend), FALSE)
  internal_error <- rlang::catch_cnd(as_graft_store_internal(backend))
  expect_s3_class(internal_error, "graft_backend_error")

  expect_invisible(graft_close(first))
  expect_identical(first@closed, TRUE)
  expect_invisible(graft_close(first))

  reopened <- graft_open(schema, path, okf = "disabled")
  withr::defer(graft_close(reopened))
  expect_identical(reopened@id, first_id)
  expect_identical(reopened@closed, FALSE)
})

test_that("graft_open verifies existing stores in read-only mode", {
  schema <- graft_schema(tempest_manifest_path())
  path <- withr::local_tempfile(fileext = ".duckdb")
  writable <- graft_open(schema, path, okf = "disabled")
  graft_close(writable)

  read_only <- graft_open(
    schema,
    path,
    read_only = TRUE,
    okf = "disabled"
  )
  withr::defer(graft_close(read_only))

  expect_identical(read_only@read_only, TRUE)
  expect_identical(read_only@capabilities$writable, FALSE)
  legacy <- as_graft_store_internal(read_only)
  condition <- rlang::catch_cnd(validate_store_writable(legacy, "test_write"))
  expect_s3_class(condition, "graft_backend_error")
})

test_that("GraftStore preserves owned and caller connection lifecycles", {
  schema <- graft_schema(tempest_manifest_path())
  owned <- graft_open(schema, okf = "disabled")
  owned_connection <- as_graft_store_internal(owned)$connection
  graft_close(owned)
  expect_identical(DBI::dbIsValid(owned_connection), FALSE)

  connection <- DBI::dbConnect(
    duckdb::duckdb(shared_home = FALSE),
    dbdir = ":memory:"
  )
  withr::defer(DBI::dbDisconnect(connection, shutdown = TRUE))
  supplied <- graft_open(
    schema,
    connection = connection,
    okf = "disabled"
  )
  expect_identical(supplied@capabilities$owns_connection, FALSE)
  graft_close(supplied)
  expect_identical(supplied@closed, TRUE)
  expect_identical(DBI::dbIsValid(connection), TRUE)
})

test_that("graft_open cleans up connections after initialization failure", {
  schema <- graft_schema(tempest_manifest_path())
  caller_connection <- DBI::dbConnect(
    duckdb::duckdb(shared_home = FALSE),
    dbdir = ":memory:"
  )
  withr::defer(DBI::dbDisconnect(caller_connection, shutdown = TRUE))
  DBI::dbExecute(caller_connection, "CREATE TABLE foreign_table (id INTEGER)")

  caller_error <- rlang::catch_cnd(graft_open(
    schema,
    connection = caller_connection,
    okf = "disabled"
  ))
  expect_s3_class(caller_error, "graft_backend_error")
  expect_identical(DBI::dbIsValid(caller_connection), TRUE)

  path <- withr::local_tempfile(fileext = ".duckdb")
  setup <- DBI::dbConnect(
    duckdb::duckdb(shared_home = FALSE),
    dbdir = path
  )
  DBI::dbExecute(setup, "CREATE TABLE foreign_table (id INTEGER)")
  DBI::dbDisconnect(setup, shutdown = TRUE)
  original_connect <- duckdb_connect
  owned_connection <- NULL
  local_mocked_bindings(
    duckdb_connect = function(...) {
      owned_connection <<- original_connect(...)
      owned_connection
    }
  )

  owned_error <- rlang::catch_cnd(graft_open(
    schema,
    path,
    okf = "disabled"
  ))
  expect_s3_class(owned_error, "graft_backend_error")
  expect_identical(DBI::dbIsValid(owned_connection), FALSE)
})

test_that("GraftStore rejects malformed state and property mutation", {
  schema <- graft_schema(tempest_manifest_path())
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))

  mutate_store_read_only <- function() {
    store@read_only <- TRUE
  }
  setter <- rlang::catch_cnd(mutate_store_read_only())
  expect_s3_class(setter, "error")
  expect_match(conditionMessage(setter), "read-only")

  state <- attr(store, ".state", exact = TRUE)
  store_id <- state$id
  state$id <- "tampered"
  condition <- rlang::catch_cnd(as_graft_store_internal(store))
  expect_s3_class(condition, "graft_backend_error")
  state$id <- store_id
})
