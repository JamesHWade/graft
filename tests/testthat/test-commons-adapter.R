local_captured_commons_source <- function(source, classes = NULL) {
  local_mocked_bindings(
    commons_data_source_call = function(tables, dictionary) {
      list(
        tables = tables,
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
    commons_materialized_connection = function(tables) connection,
    commons_connection_handle = function(connection) connection
  )

  source <- commons_data_source_call(
    list(tables = data.frame(id = 1L)),
    "dictionary.yaml"
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
  expect_type(table$page_start, "double")
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
    commons_data_source_call = function(tables, dictionary) {
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
