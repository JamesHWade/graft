test_that("graft_open initializes revision authority and projections", {
  schema <- graft_schema(tempest_manifest_path())
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))
  backend <- as_graft_store_internal(store)
  tables <- DBI::dbListTables(backend$connection)

  expect_setequal(
    intersect(tables, graft_authoritative_table_names),
    graft_authoritative_table_names
  )
  expect_in(graft_current_view_name, tables)
  expect_in("entity", tables)
  expect_in("claim__about", tables)

  metadata <- read_store_metadata(backend$connection)
  expect_identical(scalar_character(metadata$store_id), store@id)
  expect_identical(
    scalar_character(metadata$store_format_version),
    graft_store_format_version
  )
  expect_identical(
    scalar_character(metadata$active_structural_digest),
    schema@structural_digest
  )
  expect_identical(isTRUE(metadata$history_complete), TRUE)
  expect_identical(store@capabilities$writable, TRUE)
})

test_that("file stores reopen with one stable identity", {
  schema <- graft_schema(tempest_manifest_path())
  path <- withr::local_tempfile(fileext = ".duckdb")
  first <- graft_open(schema, path, okf = "disabled")
  store_id <- first@id
  graft_close(first)

  reopened <- graft_open(schema, path, okf = "disabled")
  withr::defer(graft_close(reopened))

  expect_identical(reopened@id, store_id)
  expect_identical(reopened@closed, FALSE)
  expect_identical(reopened@schema@structural_digest, schema@structural_digest)
})

test_that("read-only stores verify but never initialize", {
  schema <- graft_schema(tempest_manifest_path())
  blank_path <- withr::local_tempfile(fileext = ".duckdb")
  connection <- DBI::dbConnect(
    duckdb::duckdb(shared_home = FALSE),
    dbdir = blank_path
  )
  DBI::dbDisconnect(connection, shutdown = TRUE)

  blank_error <- rlang::catch_cnd(graft_open(
    schema,
    blank_path,
    read_only = TRUE,
    okf = "disabled"
  ))
  expect_s3_class(blank_error, "graft_backend_error")
  expect_match(conditionMessage(blank_error), "read-only")

  initialized_path <- withr::local_tempfile(fileext = ".duckdb")
  writable <- graft_open(schema, initialized_path, okf = "disabled")
  store_id <- writable@id
  graft_close(writable)

  read_only <- graft_open(
    schema,
    initialized_path,
    read_only = TRUE,
    okf = "disabled"
  )
  withr::defer(graft_close(read_only))

  expect_identical(read_only@id, store_id)
  expect_identical(read_only@read_only, TRUE)
  expect_identical(read_only@capabilities$writable, FALSE)
  backend <- as_graft_store_internal(read_only)
  mutation_error <- rlang::catch_cnd(
    validate_store_writable(backend, "test_write")
  )
  expect_s3_class(mutation_error, "graft_backend_error")
})

test_that("stores reject structural schema changes", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema <- graft_schema(tempest_manifest_path())
  store <- graft_open(schema, path, okf = "disabled")
  graft_close(store)

  changed <- as_graft_schema_internal(schema)
  changed$manifest$classes$Entity$slots$description$sensitive <- TRUE
  changed <- refresh_schema_structural_digest(changed)
  incompatible <- new_graft_schema(changed)

  condition <- rlang::catch_cnd(graft_open(
    incompatible,
    path,
    okf = "disabled"
  ))

  expect_s3_class(condition, "graft_schema_mismatch")
  expect_identical(is.object(condition$schema_compatibility), FALSE)
  expect_identical(condition$schema_compatibility$compatible, FALSE)
  expect_identical(
    condition$schema_compatibility$classification,
    "structural change"
  )
})

test_that("compiler-only rebuilds activate without changing store identity", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema <- graft_schema(tempest_manifest_path())
  store <- graft_open(schema, path, okf = "disabled")
  store_id <- store@id
  graft_close(store)

  rebuilt <- as_graft_schema_internal(schema)
  rebuilt$manifest$fingerprints$source_digest <- graft_sha256("new source")
  rebuilt$manifest$fingerprints$build_digest <- graft_sha256("new build")
  rebuilt <- new_graft_schema(rebuilt)
  reopened <- graft_open(rebuilt, path, okf = "disabled")
  withr::defer(graft_close(reopened))
  backend <- as_graft_store_internal(reopened)
  metadata <- read_store_metadata(backend$connection)
  versions <- DBI::dbReadTable(
    backend$connection,
    "_graft_schema_versions"
  )

  expect_identical(reopened@id, store_id)
  expect_identical(
    scalar_character(metadata$active_build_digest),
    rebuilt@build_digest
  )
  expect_equal(nrow(versions), 2L)
})

test_that("projections rebuild from the revision ledger", {
  schema <- graft_schema(tempest_manifest_path())
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))
  backend <- as_graft_store_internal(store)
  now <- as.POSIXct("2026-08-02 12:00:00", tz = "UTC")
  record_id <- "claim:projection-test"
  revision_id <- "revision:projection-test"
  payload <- list(
    about = list("entity:alpha", "entity:beta"),
    id = record_id,
    statement_text = "A revision-first claim"
  )
  DBI::dbAppendTable(
    backend$connection,
    "_graft_record_revisions",
    data.frame(
      revision_id = revision_id,
      record_id = record_id,
      class = "Claim",
      batch_id = "batch:projection-test",
      schema_build_digest = schema@build_digest,
      revision_number = 1,
      operation = "insert",
      payload_json = canonical_json(payload),
      content_digest = graft_sha256(canonical_json(payload)),
      changed_fields_json = "[]",
      prior_revision_id = NA_character_,
      recorded_at = now,
      commit_order = 1,
      stringsAsFactors = FALSE
    )
  )
  DBI::dbAppendTable(
    backend$connection,
    "_graft_record_heads",
    data.frame(
      record_id = record_id,
      class = "Claim",
      revision_id = revision_id,
      revision_number = 1,
      updated_at = now,
      stringsAsFactors = FALSE
    )
  )

  expect_invisible(rebuild_store_projections(backend))

  claim <- DBI::dbReadTable(backend$connection, "claim")
  about <- DBI::dbReadTable(backend$connection, "claim__about")
  expect_identical(claim$id, record_id)
  expect_identical(claim$statement_text, "A revision-first claim")
  expect_setequal(about$object, c("entity:alpha", "entity:beta"))
})
