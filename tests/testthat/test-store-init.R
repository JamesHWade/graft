metadata_table_names <- function() {
  c(
    "_graft_batches",
    "_graft_identifiers",
    "_graft_origins",
    "_graft_projection_state",
    "_graft_record_heads",
    "_graft_record_observations",
    "_graft_record_revisions",
    "_graft_schema_versions",
    "_graft_store"
  )
}

schema_projection_view_names <- function(schema) {
  generated_projection_view_names(schema)
}

store_object_types <- function(connection) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT table_name, table_type FROM information_schema.tables",
      "WHERE table_schema = 'main' ORDER BY table_name"
    )
  )
}

modified_schema <- function(schema) {
  unserialize(serialize(schema, NULL))
}

catch_graft_condition <- function(code) {
  tryCatch(code, graft_error = identity)
}

seed_claim_revision <- function(store) {
  record_id <- "claim:projection-test"
  payload <- list(
    about = list("entity:alpha", "entity:beta"),
    id = record_id,
    statement_text = "A revision-first claim"
  )
  seed_projection_revision(
    store,
    record_id = record_id,
    record_class = "Claim",
    payload_json = canonical_json(payload)
  )
}

seed_projection_revision <- function(
  store,
  record_id,
  record_class,
  payload_json,
  revision_id = paste0("revision:", record_id),
  now = as.POSIXct("2026-08-02 12:00:00", tz = "UTC")
) {
  DBI::dbAppendTable(
    store$connection,
    "_graft_record_revisions",
    data.frame(
      revision_id = revision_id,
      record_id = record_id,
      class = record_class,
      batch_id = "batch:projection-test",
      schema_build_digest = scalar_character(
        store$schema$manifest$fingerprints$build_digest
      ),
      revision_number = 1,
      operation = "insert",
      payload_json = payload_json,
      content_digest = paste0("sha256:", strrep("a", 64L)),
      changed_fields_json = "[]",
      prior_revision_id = NA_character_,
      recorded_at = now,
      commit_order = 1,
      stringsAsFactors = FALSE
    )
  )
  DBI::dbAppendTable(
    store$connection,
    "_graft_record_heads",
    data.frame(
      record_id = record_id,
      class = record_class,
      revision_id = revision_id,
      revision_number = 1,
      updated_at = now,
      stringsAsFactors = FALSE
    )
  )
  invisible(store)
}

claim_value_projection_schema <- function(schema, range, duckdb_type) {
  schema <- modified_schema(schema)
  slot <- schema$manifest$classes$Claim$slots$about
  slot$object_reference <- FALSE
  slot$range <- range
  slot$duckdb_type <- duckdb_type
  schema$manifest$classes$Claim$slots$about <- slot
  schema$manifest$relations[[1L]]$kind <- "value"
  refresh_schema_structural_digest(schema)
}

test_that("initialization creates v3 authority and generated projections", {
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema)
  withr::defer(kg_disconnect(store))

  expect_s3_class(store, "kg_store")
  expect_invisible(kg_init(store))

  expected <- c(
    metadata_table_names(),
    generated_projection_table_names(schema),
    schema_projection_view_names(schema)
  )
  expect_setequal(DBI::dbListTables(store$connection), expected)

  objects <- store_object_types(store$connection)
  authoritative <- subset(
    objects,
    table_name %in% graft_authoritative_table_names
  )
  derived <- subset(
    objects,
    table_name %in%
      c(
        graft_projection_metadata_table_names,
        generated_projection_table_names(schema)
      )
  )
  public <- subset(
    objects,
    table_name %in% schema_projection_view_names(schema)
  )
  expect_setequal(
    authoritative$table_name,
    graft_authoritative_table_names
  )
  expect_setequal(unique(authoritative$table_type), "BASE TABLE")
  expect_setequal(unique(derived$table_type), "BASE TABLE")
  expect_setequal(unique(public$table_type), "VIEW")
  expect_disjoint(authoritative$table_name, derived$table_name)
  expect_disjoint(
    vapply(
      schema$manifest$classes,
      \(.x) scalar_character(.x$view),
      character(1)
    ),
    subset(objects, table_type == "BASE TABLE")$table_name
  )

  store_row <- DBI::dbReadTable(store$connection, "_graft_store")
  expect_equal(nrow(store_row), 1L)
  expect_identical(
    store_row$active_structural_digest,
    schema$manifest$fingerprints$structural_digest
  )
  expect_identical(store_row$store_format_version, "3.0.0")
  info <- kg_store_info(store)
  expect_identical(info$store_format_version, "3.0.0")
  expect_identical(info$required_store_format_version, "3.0.0")
  expect_identical(
    store_row$active_build_digest,
    schema$manifest$fingerprints$build_digest
  )
  expect_identical(store_row$history_complete, TRUE)
  expect_identical(
    jsonlite::fromJSON(store_row$manifest_json, simplifyVector = FALSE),
    schema$manifest
  )

  metadata_columns <- lapply(
    metadata_table_names(),
    \(.x) DBI::dbListFields(store$connection, .x)
  )
  names(metadata_columns) <- metadata_table_names()
  expect_identical(
    metadata_columns$`_graft_store`,
    c(
      "store_id",
      "store_format_version",
      "active_structural_digest",
      "active_build_digest",
      "source_digest",
      "build_digest",
      "manifest_json",
      "history_started_at",
      "history_complete",
      "created_at",
      "updated_at"
    )
  )
  expect_identical(
    metadata_columns$`_graft_batches`,
    c(
      "batch_id",
      "schema_build_digest",
      "commit_order",
      "producer",
      "producer_version",
      "source_run_id",
      "idempotency_key",
      "metadata_json",
      "started_at",
      "committed_at",
      "status"
    )
  )
  expect_identical(
    metadata_columns$`_graft_origins`,
    c(
      "record_id",
      "class",
      "producer",
      "origin_key",
      "first_batch_id",
      "created_at"
    )
  )
  expect_identical(
    metadata_columns$`_graft_record_observations`,
    c(
      "record_id",
      "class",
      "batch_id",
      "disposition",
      "revision_id",
      "origin_key",
      "matched_by",
      "identity_evidence_json",
      "observed_at"
    )
  )
  expect_identical(
    metadata_columns$`_graft_schema_versions`,
    c(
      "build_digest",
      "structural_digest",
      "source_digest",
      "manifest_json",
      "compiler_json",
      "registered_at"
    )
  )
  expect_identical(
    metadata_columns$`_graft_record_revisions`,
    c(
      "revision_id",
      "record_id",
      "class",
      "batch_id",
      "schema_build_digest",
      "revision_number",
      "operation",
      "payload_json",
      "content_digest",
      "changed_fields_json",
      "prior_revision_id",
      "recorded_at",
      "commit_order"
    )
  )
  expect_identical(
    metadata_columns$`_graft_record_heads`,
    c(
      "record_id",
      "class",
      "revision_id",
      "revision_number",
      "updated_at"
    )
  )
  expect_identical(
    metadata_columns$`_graft_identifiers`,
    c(
      "record_id",
      "class",
      "namespace",
      "value",
      "normalized_value",
      "status",
      "assigned_by",
      "confidence",
      "created_at"
    )
  )
  expect_identical(
    metadata_columns$`_graft_projection_state`,
    c(
      "state_id",
      "schema_build_digest",
      "head_source_digest",
      "cache_digest",
      "object_digest",
      "rebuilt_at"
    )
  )

  expect_identical(
    DBI::dbListFields(store$connection, graft_current_view_name),
    c(
      "revision_id",
      "record_id",
      "class",
      "batch_id",
      "schema_build_digest",
      "revision_number",
      "operation",
      "payload_json",
      "content_digest",
      "changed_fields_json",
      "prior_revision_id",
      "recorded_at",
      "commit_order",
      "head_updated_at"
    )
  )
  expect_identical(
    DBI::dbListFields(store$connection, "entity"),
    c(
      "cas_number",
      "created_at",
      "description",
      "id",
      "inchikey",
      "label",
      "preferred_name",
      "updated_at"
    )
  )
  expect_identical(
    DBI::dbListFields(store$connection, "claim__about"),
    c("id", "subject", "object", "position", "created_at")
  )

  versions <- DBI::dbReadTable(store$connection, "_graft_schema_versions")
  expect_equal(nrow(versions), 1L)
  expect_identical(
    versions$build_digest,
    schema$manifest$fingerprints$build_digest
  )
  expect_identical(
    jsonlite::fromJSON(versions$compiler_json, simplifyVector = FALSE),
    schema$manifest$compiler
  )
})

test_that("initialization is idempotent", {
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema)
  withr::defer(kg_disconnect(store))

  kg_init(store)
  before <- DBI::dbReadTable(store$connection, "_graft_store")
  tables_before <- DBI::dbListTables(store$connection)

  expect_invisible(kg_init(store))

  after <- DBI::dbReadTable(store$connection, "_graft_store")
  expect_identical(after$store_id, before$store_id)
  expect_identical(after$created_at, before$created_at)
  expect_identical(DBI::dbListTables(store$connection), tables_before)
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_schema_versions")),
    1L
  )
})

test_that("projection initialization is offline from DuckDB extensions", {
  schema <- kg_schema(tempest_manifest_path())
  connection <- DBI::dbConnect(
    duckdb::duckdb(shared_home = FALSE),
    dbdir = ":memory:",
    config = list(
      autoload_known_extensions = "false",
      autoinstall_known_extensions = "false"
    )
  )
  withr::defer(DBI::dbDisconnect(connection, shutdown = TRUE))
  store <- kg_connect_duckdb(schema, connection = connection)

  expect_invisible(kg_init(store))
  expect_setequal(
    DBI::dbListFields(connection, "claim__about"),
    c("id", "subject", "object", "position", "created_at")
  )
})

test_that("projection rebuild is deterministic and preserves authority", {
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema)
  withr::defer(kg_disconnect(store))
  kg_init(store)
  seed_claim_revision(store)

  expect_invisible(rebuild_store_projections(store))
  ledger_before <- DBI::dbReadTable(
    store$connection,
    "_graft_record_revisions"
  )
  heads_before <- DBI::dbReadTable(store$connection, "_graft_record_heads")
  current_before <- DBI::dbReadTable(store$connection, "_graft_current_records")
  claim_before <- DBI::dbReadTable(store$connection, "claim")
  about_before <- DBI::dbReadTable(store$connection, "claim__about")
  nodes_before <- DBI::dbReadTable(store$connection, "_graft_nodes")

  expect_identical(current_before$record_id, "claim:projection-test")
  expect_identical(claim_before$id, "claim:projection-test")
  expect_identical(claim_before$statement_text, "A revision-first claim")
  expect_setequal(
    about_before$object,
    c("entity:alpha", "entity:beta")
  )
  expect_setequal(nodes_before$id, "claim:projection-test")

  drop_projection_views(store$connection, schema)
  drop_projection_cache_tables(store$connection, schema)
  expect_disjoint(
    DBI::dbListTables(store$connection),
    c(
      generated_projection_view_names(schema),
      generated_projection_table_names(schema)
    )
  )
  expect_identical(
    DBI::dbReadTable(store$connection, "_graft_record_revisions"),
    ledger_before
  )
  expect_identical(
    DBI::dbReadTable(store$connection, "_graft_record_heads"),
    heads_before
  )

  expect_invisible(rebuild_store_projections(store))
  expect_identical(
    DBI::dbReadTable(store$connection, "_graft_current_records"),
    current_before
  )
  expect_identical(DBI::dbReadTable(store$connection, "claim"), claim_before)
  expect_identical(
    DBI::dbReadTable(store$connection, "claim__about"),
    about_before
  )
  expect_identical(
    DBI::dbReadTable(store$connection, "_graft_nodes"),
    nodes_before
  )
})

test_that("projection rebuild preserves scalar and multivalue UTC timestamps", {
  schema <- claim_value_projection_schema(
    kg_schema(tempest_manifest_path()),
    range = "datetime",
    duckdb_type = "TIMESTAMP"
  )
  store <- kg_connect_duckdb(schema)
  withr::defer(kg_disconnect(store))
  kg_init(store)
  seed_projection_revision(
    store,
    record_id = "claim:temporal",
    record_class = "Claim",
    payload_json = paste0(
      '{"about":["2026-08-02T23:59:58.654321Z"],',
      '"asserted_at":"2026-08-02T12:34:56.123456Z",',
      '"id":"claim:temporal","statement_text":"Temporal"}'
    )
  )

  expect_invisible(rebuild_store_projections(store))

  scalar <- DBI::dbGetQuery(
    store$connection,
    "SELECT CAST(asserted_at AS VARCHAR) AS value FROM claim"
  )
  multivalue <- DBI::dbGetQuery(
    store$connection,
    "SELECT CAST(value AS VARCHAR) AS value FROM claim__about"
  )
  expect_identical(scalar$value, "2026-08-02 12:34:56.123456")
  expect_identical(multivalue$value, "2026-08-02 23:59:58.654321")
})

test_that("projection rebuild preserves exact BIGINT and DECIMAL values", {
  parsed <- projection_parse_payload('{"value":9223372036854775807}')
  expect_identical(parsed$value, "9223372036854775807")

  schema <- claim_value_projection_schema(
    kg_schema(tempest_manifest_path()),
    range = "decimal",
    duckdb_type = "DECIMAL"
  )
  schema$manifest$classes$Claim$slots$confidence$range <- "integer"
  schema$manifest$classes$Claim$slots$confidence$duckdb_type <- "BIGINT"
  schema <- refresh_schema_structural_digest(schema)
  store <- kg_connect_duckdb(schema)
  withr::defer(kg_disconnect(store))
  kg_init(store)
  seed_projection_revision(
    store,
    record_id = "claim:exact-numbers",
    record_class = "Claim",
    payload_json = paste0(
      '{"about":["12345678901234.567"],',
      '"confidence":"9223372036854775807",',
      '"id":"claim:exact-numbers","statement_text":"Exact"}'
    )
  )

  expect_invisible(rebuild_store_projections(store))

  bigint <- DBI::dbGetQuery(
    store$connection,
    "SELECT CAST(confidence AS VARCHAR) AS value FROM claim"
  )
  decimal <- DBI::dbGetQuery(
    store$connection,
    "SELECT CAST(value AS VARCHAR) AS value FROM claim__about"
  )
  expect_identical(bigint$value, "9223372036854775807")
  expect_identical(decimal$value, "12345678901234.567")
})

test_that("projection rebuild rejects JSON numbers with uncertain precision", {
  schema <- claim_value_projection_schema(
    kg_schema(tempest_manifest_path()),
    range = "decimal",
    duckdb_type = "DECIMAL"
  )
  store <- kg_connect_duckdb(schema)
  withr::defer(kg_disconnect(store))
  kg_init(store)
  seed_projection_revision(
    store,
    record_id = "claim:rounded-upstream",
    record_class = "Claim",
    payload_json = paste0(
      '{"about":[1234567890.123456789],',
      '"id":"claim:rounded-upstream","statement_text":"Unsafe"}'
    )
  )

  condition <- catch_graft_condition(rebuild_store_projections(store))

  expect_s3_class(condition, "graft_backend_error")
  expect_identical(condition$duckdb_type, "DECIMAL")
  expect_match(conditionMessage(condition), "already have lost precision")
})

test_that("read-only projection verification detects stale and mistyped objects", {
  schema <- kg_schema(tempest_manifest_path())
  corruptions <- c("stale_cache", "table_for_view")
  for (corruption in corruptions) {
    path <- withr::local_tempfile(fileext = ".duckdb")
    writable <- kg_connect_duckdb(schema, path)
    kg_init(writable)
    seed_claim_revision(writable)
    rebuild_store_projections(writable)
    if (identical(corruption, "stale_cache")) {
      DBI::dbExecute(
        writable$connection,
        paste(
          "UPDATE _graft_projection_claim",
          "SET statement_text = 'stale projection'"
        )
      )
    } else {
      DBI::dbExecute(writable$connection, "DROP VIEW claim")
      DBI::dbExecute(
        writable$connection,
        paste(
          "CREATE TABLE claim AS SELECT * FROM",
          "_graft_projection_claim"
        )
      )
    }
    kg_disconnect(writable)

    read_only <- kg_connect_duckdb(schema, path, read_only = TRUE)
    condition <- catch_graft_condition(kg_init(read_only))
    kg_disconnect(read_only)

    expect_s3_class(condition, "graft_backend_error")
    if (identical(corruption, "stale_cache")) {
      expect_in("cache_digest", condition$stale_fields)
    } else {
      expect_in("claim", condition$invalid_projections)
      expect_match(conditionMessage(condition), "expected VIEW")
    }
  }
})

test_that("projection rebuild rejects dangling and mismatched heads", {
  schema <- kg_schema(tempest_manifest_path())
  corruptions <- c("dangling", "mismatched")
  for (corruption in corruptions) {
    store <- kg_connect_duckdb(schema)
    withr::defer(kg_disconnect(store))
    kg_init(store)
    seed_claim_revision(store)
    rebuild_store_projections(store)
    claim_before <- DBI::dbReadTable(store$connection, "claim")
    if (identical(corruption, "dangling")) {
      DBI::dbExecute(
        store$connection,
        "UPDATE _graft_record_heads SET revision_id = 'revision:missing'"
      )
    } else {
      DBI::dbExecute(
        store$connection,
        "UPDATE _graft_record_heads SET revision_number = 2"
      )
    }

    condition <- catch_graft_condition(rebuild_store_projections(store))

    expect_s3_class(condition, "graft_backend_error")
    expect_identical(condition$operation, "validate_projection_heads")
    expect_equal(nrow(condition$invalid_heads), 1L)
    expect_match(conditionMessage(condition), "match exactly one revision")
    expect_identical(
      DBI::dbReadTable(store$connection, "claim"),
      claim_before
    )
  }
})

test_that("live stores reuse verified schemas for ordinary reads", {
  store <- local_ingest_store()
  verify <- verify_initialized_store
  calls <- 0L
  local_mocked_bindings(
    verify_initialized_store = function(...) {
      calls <<- calls + 1L
      verify(...)
    }
  )

  kg_records(store, "Entity")
  kg_records(store, "Source")

  expect_identical(calls, 0L)
  kg_check_store(store)
  expect_identical(calls, 1L)

  changed <- modified_ingest_schema(store$schema)
  changed$manifest$fingerprints$build_digest <- paste0(
    "sha256:",
    strrep("a", 64L)
  )
  store$schema <- changed
  expect_identical(store_schema_is_verified(store), FALSE)
})

test_that("cached reads reject mutable manifest tampering", {
  schema <- kg_schema(tempest_manifest_path())
  schema$manifest$classes$Entity$slots$description$sensitive <- TRUE
  schema <- refresh_schema_structural_digest(schema)
  store <- local_ingest_store(schema = schema)
  kg_write(
    store,
    kg_batch("cache-test", idempotency_key = "cache-test"),
    "Entity",
    data.frame(
      preferred_name = "Project Firefly",
      description = "TOP SECRET"
    )
  )

  public <- dplyr::collect(kg_records(store, "Entity"))
  expect_false("description" %in% names(public))
  store$schema$manifest$classes$Entity$slots$description$sensitive <- FALSE

  condition <- catch_graft_condition(kg_records(store, "Entity"))

  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "structural_digest_content_mismatch")
  expect_null(store$verification)
})

test_that("cached reads reject persistent metadata tampering", {
  store <- local_ingest_store()
  kg_records(store, "Entity")
  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_store SET store_format_version = '2.0.0'"
  )

  first <- catch_graft_condition(kg_records(store, "Entity"))
  audit <- catch_graft_condition(kg_check_store(store))
  second <- catch_graft_condition(kg_records(store, "Entity"))

  expect_s3_class(first, "graft_store_format_error")
  expect_s3_class(audit, "graft_store_format_error")
  expect_s3_class(second, "graft_store_format_error")
  expect_null(store$verification)
})

test_that("cached reads reject active schema registry tampering", {
  store <- local_ingest_store()
  kg_records(store, "Entity")
  tampered <- modified_ingest_schema(store$schema)
  tampered$manifest$classes$Entity$slots$description$sensitive <- TRUE
  DBI::dbExecute(
    store$connection,
    paste(
      "UPDATE _graft_schema_versions SET manifest_json = ?",
      "WHERE build_digest = ?"
    ),
    params = list(
      canonical_manifest_json(tampered$manifest),
      store$schema$manifest$fingerprints$build_digest
    )
  )

  condition <- catch_graft_condition(kg_records(store, "Entity"))

  expect_s3_class(condition, "graft_backend_error")
  expect_match(conditionMessage(condition), "schema registry entry")
  expect_null(store$verification)
})

test_that("unsupported store formats are rejected explicitly", {
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema)
  withr::defer(kg_disconnect(store))
  kg_init(store)
  DBI::dbExecute(
    store$connection,
    "UPDATE _graft_store SET store_format_version = '2.0.0'"
  )

  condition <- catch_graft_condition(kg_init(store))

  expect_s3_class(condition, "graft_store_format_error")
  expect_identical(condition$observed_version, "2.0.0")
  expect_identical(condition$supported_version, "3.0.0")
})

test_that("file stores reopen and initialize without Python", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema <- kg_schema(tempest_manifest_path())
  python_before <- reticulate::py_available(initialize = FALSE)

  store <- kg_connect_duckdb(schema, path)
  kg_init(store)
  store_id <- kg_store_info(store)$stored$store_id
  kg_disconnect(store)

  reopened <- kg_connect_duckdb(schema, path)
  withr::defer(kg_disconnect(reopened))
  expect_invisible(kg_init(reopened))
  expect_identical(kg_store_info(reopened)$stored$store_id, store_id)
  expect_identical(
    reticulate::py_available(initialize = FALSE),
    python_before
  )
})

test_that("connection ownership and close state are explicit", {
  schema <- kg_schema(tempest_manifest_path())
  connection <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  withr::defer({
    if (DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection, shutdown = TRUE)
    }
  })

  supplied <- kg_connect_duckdb(schema, connection = connection)
  expect_identical(supplied$owns_connection, FALSE)
  kg_init(supplied)
  expect_invisible(kg_disconnect(supplied))
  expect_identical(DBI::dbIsValid(connection), TRUE)
  expect_identical(kg_store_info(supplied)$closed, TRUE)
  expect_invisible(kg_disconnect(supplied))

  closed_error <- catch_graft_condition(kg_init(supplied))
  expect_s3_class(closed_error, "graft_backend_error")

  compatible <- kg_connect_duckdb(
    schema,
    path = ":memory:",
    connection = connection
  )
  expect_identical(compatible$owns_connection, FALSE)
  kg_disconnect(compatible)

  conflict <- catch_graft_condition(
    kg_connect_duckdb(
      schema,
      path = withr::local_tempfile(fileext = ".duckdb"),
      connection = connection
    )
  )
  expect_s3_class(conflict, "graft_backend_error")

  owned <- kg_connect_duckdb(schema)
  owned_connection <- owned$connection
  kg_disconnect(owned)
  expect_identical(DBI::dbIsValid(owned_connection), FALSE)
})

test_that("read-only stores verify but never initialize or mutate", {
  schema <- kg_schema(tempest_manifest_path())
  blank_path <- withr::local_tempfile(fileext = ".duckdb")
  connection <- DBI::dbConnect(duckdb::duckdb(), dbdir = blank_path)
  DBI::dbDisconnect(connection, shutdown = TRUE)

  blank <- kg_connect_duckdb(schema, blank_path, read_only = TRUE)
  withr::defer(kg_disconnect(blank))
  blank_error <- catch_graft_condition(kg_init(blank))
  expect_s3_class(blank_error, "graft_backend_error")
  expect_match(conditionMessage(blank_error), "read-only")

  initialized_path <- withr::local_tempfile(fileext = ".duckdb")
  writable <- kg_connect_duckdb(schema, initialized_path)
  kg_init(writable)
  kg_disconnect(writable)

  read_only <- kg_connect_duckdb(
    schema,
    initialized_path,
    read_only = TRUE
  )
  withr::defer(kg_disconnect(read_only))
  expect_invisible(kg_init(read_only))
  expect_identical(store_schema_is_verified(read_only), TRUE)
  expect_s3_class(kg_records(read_only, "Entity"), "tbl_dbi")
  expect_identical(kg_capabilities(read_only)$writable, FALSE)
  mutation_error <- catch_graft_condition(
    graft:::validate_store_writable(read_only, "test_write")
  )
  expect_s3_class(mutation_error, "graft_backend_error")
})

test_that("structural mismatches carry a schema diff", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema, path)
  kg_init(store)
  kg_disconnect(store)

  incompatible <- modified_schema(schema)
  incompatible$manifest$classes$Entity$slots$description$sensitive <- TRUE
  incompatible <- refresh_schema_structural_digest(incompatible)

  mismatched <- kg_connect_duckdb(incompatible, path)
  withr::defer(kg_disconnect(mismatched))
  condition <- catch_graft_condition(kg_init(mismatched))

  expect_s3_class(condition, "graft_schema_mismatch")
  expect_s3_class(condition$schema_diff, "kg_schema_diff")
  expect_identical(condition$schema_diff$compatible, FALSE)
  expect_match(
    conditionMessage(condition),
    condition$schema_diff$classification,
    fixed = TRUE
  )
  expect_in("Entity", condition$schema_diff$classes$changed)
})

test_that("compiler-only digest changes remain writable", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema, path)
  kg_init(store)
  store_id <- kg_store_info(store)$stored$store_id
  kg_disconnect(store)

  rebuilt <- modified_schema(schema)
  rebuilt$manifest$fingerprints$source_digest <- paste0(
    "sha256:",
    paste(rep("1", 64L), collapse = "")
  )
  rebuilt$manifest$fingerprints$build_digest <- paste0(
    "sha256:",
    paste(rep("2", 64L), collapse = "")
  )

  compatible <- kg_connect_duckdb(rebuilt, path)
  withr::defer(kg_disconnect(compatible))
  expect_invisible(kg_init(compatible))

  info <- kg_store_info(compatible)
  expect_identical(info$stored$store_id, store_id)
  expect_identical(
    info$stored$source_digest,
    rebuilt$manifest$fingerprints$source_digest
  )
  expect_identical(
    info$stored$build_digest,
    rebuilt$manifest$fingerprints$build_digest
  )
  expect_identical(
    info$stored$active_build_digest,
    rebuilt$manifest$fingerprints$build_digest
  )
  versions <- DBI::dbReadTable(
    compatible$connection,
    "_graft_schema_versions"
  )
  expect_equal(nrow(versions), 2L)
  expect_identical(kg_capabilities(compatible)$writable, TRUE)
})

test_that("reserved projections and invalid types leave stores blank", {
  schema <- kg_schema(tempest_manifest_path())
  reserved <- modified_schema(schema)
  reserved$manifest$classes$Entity$view <- "_graft_client_entity"
  reserved <- refresh_schema_structural_digest(reserved)
  reserved_store <- kg_connect_duckdb(reserved)
  withr::defer(kg_disconnect(reserved_store))

  reserved_error <- catch_graft_condition(kg_init(reserved_store))
  expect_s3_class(reserved_error, "graft_schema_error")
  expect_length(DBI::dbListTables(reserved_store$connection), 0L)

  invalid <- modified_schema(schema)
  invalid$manifest$classes$Source$slots$title$duckdb_type <- "NOT SQL"
  invalid <- refresh_schema_structural_digest(invalid)
  invalid_store <- kg_connect_duckdb(invalid)
  withr::defer(kg_disconnect(invalid_store))

  invalid_error <- catch_graft_condition(kg_init(invalid_store))
  expect_s3_class(invalid_error, "graft_schema_error")
  expect_length(DBI::dbListTables(invalid_store$connection), 0L)
})

test_that("fresh initialization refuses invalid manifest integrity atomically", {
  base <- kg_schema(tempest_manifest_path())
  stale <- migration_schema_copy(base, "stale-fresh", structural = FALSE)
  stale$manifest$classes$Entity$slots$description$sensitive <- TRUE
  stale_store <- kg_connect_duckdb(stale)
  withr::defer(kg_disconnect(stale_store))

  stale_condition <- catch_graft_condition(kg_init(stale_store))

  expect_s3_class(stale_condition, "graft_schema_integrity_error")
  expect_identical(
    stale_condition$rule,
    "structural_digest_content_mismatch"
  )
  expect_length(DBI::dbListTables(stale_store$connection), 0L)

  malformed <- modified_schema(base)
  malformed$manifest$classes$Claim$slots$about$duckdb_type <- "DOUBLE"
  malformed <- refresh_schema_structural_digest(malformed)
  malformed_store <- kg_connect_duckdb(malformed)
  withr::defer(kg_disconnect(malformed_store))

  type_condition <- catch_graft_condition(kg_init(malformed_store))

  expect_s3_class(type_condition, "graft_schema_integrity_error")
  expect_identical(type_condition$rule, "object_reference_varchar")
  expect_length(DBI::dbListTables(malformed_store$connection), 0L)
})

test_that("store info and capabilities describe the lifecycle", {
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema)

  before <- kg_store_info(store)
  expect_identical(before$initialized, FALSE)
  expect_identical(before$closed, FALSE)
  expect_identical(before$store_format_version, NA_character_)
  expect_identical(before$required_store_format_version, "3.0.0")
  expect_identical(kg_capabilities(store)$transactions, TRUE)
  expect_identical(kg_capabilities(store)$single_owning_process, TRUE)

  kg_disconnect(store)
  after <- kg_store_info(store)
  expect_identical(after$closed, TRUE)
  expect_identical(after$initialized, NA)
  expect_identical(after$store_format_version, NA_character_)
  expect_identical(after$required_store_format_version, "3.0.0")
})
