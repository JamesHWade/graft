metadata_table_names <- function() {
  c(
    "_graft_batches",
    "_graft_identifiers",
    "_graft_record_observations",
    "_graft_record_origins",
    "_graft_store"
  )
}

schema_physical_table_names <- function(schema) {
  c(
    vapply(
      schema$manifest$tables,
      \(.x) .x$name,
      character(1)
    ),
    vapply(
      schema$manifest$relations,
      \(.x) .x$table,
      character(1)
    )
  )
}

modified_schema <- function(schema) {
  unserialize(serialize(schema, NULL))
}

catch_graft_condition <- function(code) {
  tryCatch(code, graft_error = identity)
}

test_that("in-memory initialization creates metadata and manifest tables", {
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema)
  withr::defer(kg_disconnect(store))

  expect_s3_class(store, "kg_store")
  expect_invisible(kg_init(store))

  expected <- c(
    metadata_table_names(),
    schema_physical_table_names(schema),
    graft:::graft_graph_view_names
  )
  expect_setequal(DBI::dbListTables(store$connection), expected)

  store_row <- DBI::dbReadTable(store$connection, "_graft_store")
  expect_equal(nrow(store_row), 1L)
  expect_identical(
    store_row$active_structural_digest,
    schema$manifest$fingerprints$structural_digest
  )
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
      "source_digest",
      "build_digest",
      "manifest_json",
      "created_at",
      "updated_at"
    )
  )
  expect_identical(
    metadata_columns$`_graft_batches`,
    c(
      "batch_id",
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
    metadata_columns$`_graft_record_origins`,
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
    c("record_id", "class", "batch_id", "observed_at")
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

  entity_info <- DBI::dbGetQuery(
    store$connection,
    "PRAGMA table_info('entity')"
  )
  expect_identical(
    entity_info$notnull[entity_info$name == "preferred_name"],
    TRUE
  )
  expect_identical(entity_info$pk[entity_info$name == "id"], TRUE)
  expect_identical(
    DBI::dbListFields(store$connection, "claim__about"),
    c("id", "subject", "object", "position", "created_at")
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
  incompatible$manifest$fingerprints$structural_digest <- paste0(
    "sha256:",
    paste(rep("0", 64L), collapse = "")
  )
  incompatible$manifest$tables$Entity$columns[[1L]]$type <- "DOUBLE"

  mismatched <- kg_connect_duckdb(incompatible, path)
  withr::defer(kg_disconnect(mismatched))
  condition <- catch_graft_condition(kg_init(mismatched))

  expect_s3_class(condition, "graft_schema_mismatch")
  expect_s3_class(condition$schema_diff, "kg_schema_diff")
  expect_identical(condition$schema_diff$compatible, FALSE)
  expect_in("Entity", condition$schema_diff$tables$changed)
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
  expect_identical(kg_capabilities(compatible)$writable, TRUE)
})

test_that("reserved client names and failed DDL leave stores blank", {
  schema <- kg_schema(tempest_manifest_path())
  reserved <- modified_schema(schema)
  reserved$manifest$tables$Entity$name <- "_graft_client_entity"
  reserved$manifest$classes$Entity$table <- "_graft_client_entity"
  reserved_store <- kg_connect_duckdb(reserved)
  withr::defer(kg_disconnect(reserved_store))

  reserved_error <- catch_graft_condition(kg_init(reserved_store))
  expect_s3_class(reserved_error, "graft_schema_error")
  expect_length(DBI::dbListTables(reserved_store$connection), 0L)

  invalid <- modified_schema(schema)
  invalid$manifest$tables$Source$columns[[1L]]$type <- "NOT SQL"
  invalid_store <- kg_connect_duckdb(invalid)
  withr::defer(kg_disconnect(invalid_store))

  invalid_error <- catch_graft_condition(kg_init(invalid_store))
  expect_s3_class(invalid_error, "graft_schema_error")
  expect_length(DBI::dbListTables(invalid_store$connection), 0L)
})

test_that("store info and capabilities describe the lifecycle", {
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema)

  before <- kg_store_info(store)
  expect_identical(before$initialized, FALSE)
  expect_identical(before$closed, FALSE)
  expect_identical(kg_capabilities(store)$transactions, TRUE)
  expect_identical(kg_capabilities(store)$single_owning_process, TRUE)

  kg_disconnect(store)
  after <- kg_store_info(store)
  expect_identical(after$closed, TRUE)
  expect_identical(after$initialized, NA)
})
