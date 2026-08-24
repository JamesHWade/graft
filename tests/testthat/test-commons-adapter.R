local_captured_commons_source <- function(source, classes = NULL) {
  local_mocked_bindings(
    commons_data_source_call = function(tables, dictionary, types) {
      list(
        tables = tables,
        types = types,
        dictionary = yaml::read_yaml(dictionary)
      )
    }
  )
  graft_commons_data_source(source, classes = classes)
}

test_that("graft_commons_data_source() detaches accepted public tables", {
  store <- local_definition_store()

  result <- local_captured_commons_source(store, classes = "Entity")

  expect_named(result$tables, "Entity")
  expect_identical(nrow(result$tables$Entity), 3L)
  expect_identical(
    names(result$tables$Entity),
    definition_public_scalar_columns(
      as_graft_store_internal(store)$schema$manifest$classes$Entity
    )
  )
  expect_identical(result$dictionary$tables[[1L]]$name, "Entity")
  definitions <- result$dictionary$tables[[1L]]$definitions
  expect_setequal(
    vapply(definitions, `[[`, character(1), "name"),
    graft_definitions(store, target = "Entity")$name
  )
})

test_that("Commons materialization preserves pinned boundaries", {
  store <- local_definition_store()
  view <- graft_at(store, graft_snapshot(store))
  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = test_graft_id("definition-entity-later"),
        label = "base",
        preferred_name = "Ammonia"
      )
    ),
    graft_provenance(producer = "fixture", idempotency_key = "later-entity")
  )

  current <- local_captured_commons_source(store, classes = "Entity")
  pinned <- local_captured_commons_source(view, classes = "Entity")

  expect_identical(nrow(current$tables$Entity), 4L)
  expect_identical(nrow(pinned$tables$Entity), 3L)
})

test_that("Commons selection includes applicable normalized relations", {
  fixture <- local_retrieval_store()
  graft_ingest(
    fixture$store,
    list(
      GraftDefinition = data.frame(
        name = "about_count",
        target = "claim__about",
        expr = "ROW_COUNT()"
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "about-count")
  )

  result <- local_captured_commons_source(fixture$store, classes = "Claim")

  expect_named(result$tables, c("Claim", "claim__about"))
  expect_identical(
    names(result$tables$claim__about),
    c("id", "subject", "object", "position", "created_at")
  )
  expect_identical(nrow(result$tables$claim__about), 3L)
  relation <- result$dictionary$tables[[2L]]
  expect_identical(relation$name, "claim__about")
  expect_identical(relation$definitions[[1L]]$name, "about_count")
})

test_that("Commons dictionary includes definitions beyond listing bounds", {
  store <- local_definition_store()
  expected <- graft_definitions(store, target = "Entity")$name
  limits <- graft_retrieval_limits
  limits$definitions <- 1L
  local_mocked_bindings(graft_retrieval_limits = limits)

  result <- local_captured_commons_source(store, classes = "Entity")

  definitions <- result$dictionary$tables[[1L]]$definitions
  expect_setequal(
    vapply(definitions, `[[`, character(1), "name"),
    expected
  )
})

test_that("Commons preserves selected join-only data-dict relationships", {
  included <- list(
    join = "employment.person_id = person.id",
    cardinality = "many-to-one"
  )
  excluded <- list(
    join = "employment.source_id = source.id",
    cardinality = "many-to-one"
  )
  document <- list(
    tables = list(
      list(name = "employment"),
      list(name = "person"),
      list(name = "son"),
      list(name = "source")
    ),
    relationships = list(included, excluded)
  )

  relationships <- commons_dictionary_relationships(
    document,
    c("employment", "person")
  )

  expect_identical(relationships, list(included))
})

test_that("Commons formal table names use connection dispatch", {
  connection <- structure(list(id = "connection"), class = "test_connection")
  data_source <- function(
    ...,
    tables = NULL,
    exclude = NULL,
    dictionary = NULL
  ) {
    list(
      dots = list(...),
      tables = tables,
      dictionary = dictionary
    )
  }
  local_mocked_bindings(
    commons_data_source_function = function() data_source,
    commons_materialized_connection = function(tables, types) connection,
    commons_connection_handle = function(connection) connection
  )

  source <- commons_data_source_call(
    list(tables = data.frame(id = 1L)),
    "dictionary.yaml",
    list(tables = c(id = "BIGINT"))
  )

  expect_identical(source$dots, list(connection))
  expect_identical(source$tables, "tables")
  expect_identical(source$dictionary, "dictionary.yaml")
  expect_identical(source$graft_connection_handle, connection)
})

test_that("Commons selection rejects system and unknown classes", {
  store <- local_definition_store()

  expect_snapshot(
    error = TRUE,
    graft_commons_data_source(store, classes = "GraftDefinition")
  )
  expect_snapshot(
    error = TRUE,
    graft_commons_data_source(store, classes = "Missing")
  )
})

test_that("Commons materialization excludes sensitive columns", {
  schema <- modified_ingest_schema(
    as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  )
  schema$manifest$classes$Entity$slots$description$sensitive <- TRUE
  schema$manifest$classes$Entity$search_slots <- as.list(setdiff(
    unlist(schema$manifest$classes$Entity$search_slots, use.names = FALSE),
    "description"
  ))
  schema$manifest$slots$description$sensitive <- TRUE
  schema <- new_graft_schema(refresh_schema_structural_digest(schema))
  store <- local_graft_ingest_store(schema = schema)

  result <- local_captured_commons_source(store, classes = "Entity")

  expect_length(intersect("description", names(result$tables$Entity)), 0L)
  columns <- result$dictionary$tables[[1L]]$columns
  expect_length(
    intersect("description", vapply(columns, `[[`, character(1), "name")),
    0L
  )
})

test_that("Commons materialization includes typed empty tables", {
  store <- local_graft_ingest_store()

  result <- local_captured_commons_source(store, classes = "ClaimEvidence")
  table <- result$tables$ClaimEvidence

  expect_identical(nrow(table), 0L)
  expect_s3_class(table$created_at, "POSIXct")
  expect_type(table$page_start, "character")
})

test_that("Commons materialization preserves exact values and SQL types", {
  schema <- modified_ingest_schema(
    as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  )
  schema$manifest$classes$SemanticClaim$slots$temperature$range <- "decimal"
  schema$manifest$classes$SemanticClaim$slots$temperature$duckdb_type <-
    "DECIMAL"
  schema$manifest$slots$temperature$range <- "decimal"
  schema$manifest$slots$temperature$duckdb_type <- "DECIMAL"
  schema <- new_graft_schema(refresh_schema_structural_digest(schema))
  fixture <- retrieval_fixture_records()
  exact_bigint <- "9223372036854775807"
  exact_decimal <- "12345678901234.567"
  exact_timestamp <- as.POSIXct(
    "2026-08-23T14:30:00Z",
    format = "%Y-%m-%dT%H:%M:%OSZ",
    tz = "UTC"
  )
  fixture$records$ClaimEvidence$page_start <- exact_bigint
  fixture$records$ClaimEvidence$page_end <- exact_bigint
  fixture$records$SemanticClaim$temperature <- exact_decimal
  fixture$records$SemanticClaim$valid_from <- exact_timestamp
  store <- local_graft_ingest_store(schema = schema)
  graft_ingest(
    store,
    fixture$records,
    graft_provenance(
      "commons-exact-values",
      idempotency_key = "commons-exact-values"
    )
  )

  result <- local_captured_commons_source(
    store,
    classes = c("ClaimEvidence", "SemanticClaim")
  )
  connection <- commons_materialized_connection(
    result$tables,
    result$types
  )
  withr::defer(DBI::dbDisconnect(connection, shutdown = TRUE))
  bigint <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT CAST(page_start AS VARCHAR) AS value ",
      "FROM ClaimEvidence"
    )
  )
  decimal <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT CAST(temperature AS VARCHAR) AS value ",
      ", epoch(valid_from) AS valid_from FROM SemanticClaim"
    )
  )
  evidence_types <- DBI::dbGetQuery(
    connection,
    "DESCRIBE ClaimEvidence"
  )
  semantic_types <- DBI::dbGetQuery(
    connection,
    "DESCRIBE SemanticClaim"
  )

  expect_identical(
    result$tables$ClaimEvidence$page_start,
    exact_bigint
  )
  expect_equal(
    result$tables$SemanticClaim$valid_from,
    exact_timestamp
  )
  expect_identical(
    result$tables$SemanticClaim$temperature,
    exact_decimal
  )
  expect_identical(bigint$value, exact_bigint)
  expect_identical(decimal$value, exact_decimal)
  expect_equal(decimal$valid_from, as.numeric(exact_timestamp))
  expect_identical(
    evidence_types$column_type[evidence_types$column_name == "page_start"],
    "BIGINT"
  )
  expect_match(
    semantic_types$column_type[semantic_types$column_name == "temperature"],
    "^DECIMAL"
  )
  expect_identical(
    semantic_types$column_type[semantic_types$column_name == "valid_from"],
    "TIMESTAMP"
  )
})

test_that("Commons construction is atomic across selected tables", {
  store <- local_graft_ingest_store()
  original <- definition_target_frame
  called <- FALSE
  local_mocked_bindings(
    definition_target_frame = function(source, contract) {
      if (identical(contract$name, "Source")) {
        stop("projection failure")
      }
      original(source, contract)
    },
    commons_data_source_call = function(tables, dictionary, types) {
      called <<- TRUE
    }
  )

  expect_error(
    graft_commons_data_source(store, classes = c("Entity", "Source")),
    "projection failure",
    fixed = TRUE
  )
  expect_identical(called, FALSE)
})

test_that("Commons accepts the detached source through its public API", {
  skip_if_not_installed("commons", minimum_version = "0.0.0.9002")
  store <- local_definition_store()

  source <- graft_commons_data_source(store, classes = "Entity")

  expect_s3_class(source, "commons_data_source")
  expect_identical(commons::list_tables(source), "Entity")
})
