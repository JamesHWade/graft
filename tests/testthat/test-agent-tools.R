test_that("graft_tools exposes four read-only ToolDefs", {
  fixture <- local_retrieval_store()
  tools <- graft_tools(fixture$store)
  expected <- c("graft_find", "graft_get", "graft_query", "graft_history")

  expect_named(tools, expected)
  expect_identical(length(tools), 4L)
  expect_identical(
    vapply(tools, inherits, logical(1), "ellmer::ToolDef"),
    stats::setNames(rep(TRUE, 4L), expected)
  )
  expect_identical(
    lapply(tools, \(tool) agent_tool_prop(tool, "annotations")),
    rep(
      list(list(
        read_only_hint = TRUE,
        open_world_hint = FALSE,
        idempotent_hint = TRUE,
        destructive_hint = FALSE
      )),
      4L
    ) |>
      stats::setNames(expected)
  )
})

test_that("graft_tools schemas are closed and hard bounded", {
  fixture <- local_retrieval_store()
  arguments <- lapply(
    graft_tools(fixture$store),
    \(tool) agent_tool_prop(tool, "arguments")
  )
  properties <- lapply(
    arguments,
    \(argument) agent_tool_prop(argument, "properties")
  )

  expect_identical(
    vapply(
      arguments,
      \(argument) agent_tool_prop(argument, "additional_properties"),
      logical(1)
    ),
    stats::setNames(rep(FALSE, 4L), names(arguments))
  )
  expect_identical(
    agent_tool_prop(properties$graft_find$limit, "json")$maximum,
    graft_retrieval_limits$find
  )
  expect_identical(
    agent_tool_prop(properties$graft_history$limit, "json")$maximum,
    graft_retrieval_limits$history
  )
  expect_identical(
    agent_tool_prop(properties$graft_query$operation, "values"),
    graft_tool_query_operations()
  )

  request <- agent_tool_prop(properties$graft_query$request, "json")
  expect_identical(request$additionalProperties, FALSE)
  expect_identical(request$properties$hops$maximum, 2L)
  expect_identical(request$properties$max_hops$maximum, 2L)
  expect_identical(request$properties$max_nodes$maximum, 500L)
  expect_identical(request$properties$max_edges$maximum, 2000L)

  limits <- agent_tool_prop(properties$graft_get$limits, "properties")
  expect_identical(
    agent_tool_prop(limits$identifiers, "json")$maximum,
    graft_retrieval_limits$identifiers
  )
  expect_identical(
    agent_tool_prop(limits$claims, "json")$maximum,
    graft_retrieval_limits$get_claims
  )
  expect_identical(
    agent_tool_prop(limits$evidence, "json")$maximum,
    graft_retrieval_limits$get_evidence
  )
})

test_that("graft_tools returns one canonical receipt", {
  fixture <- local_retrieval_store()
  snapshot <- graft_snapshot(fixture$store)
  view <- graft_at(fixture$store, snapshot)
  tool <- graft_tools(view)$graft_find

  first <- tool(query = "polypropylene")
  graft_ingest(
    fixture$store,
    list(
      Entity = data.frame(
        id = test_graft_id("pinned-tool-polypropylene"),
        preferred_name = "Polypropylene"
      )
    ),
    graft_provenance("test", idempotency_key = "pinned-tool-v2")
  )
  second <- tool(query = "polypropylene")

  expect_named(first, c("result", "truncated", "limit", "receipt"))
  expect_equal(nrow(first$result), 0L)
  expect_identical(second$result, first$result)
  expect_identical(second$receipt, first$receipt)
  expect_identical(
    first$receipt,
    list(
      store = list(id = fixture$store@id),
      boundary = list(
        kind = "snapshot",
        batch_id = snapshot@batch_id,
        commit_order = snapshot@commit_order,
        snapshot_id = snapshot@snapshot_id
      ),
      schema = list(
        structural_digest = fixture$store@schema@structural_digest,
        build_digest = snapshot@schema_build_digest
      )
    )
  )
})

test_that("live tool calls pin an exact boundary per invocation", {
  fixture <- local_retrieval_store()
  original_find <- graft_find
  observed <- list()
  local_mocked_bindings(
    graft_find = function(store, query, class, limit) {
      expect_s7_class(store, graft:::GraftView)
      observed[[length(observed) + 1L]] <<- graft_view_snapshot(store)
      original_find(store, query = query, class = class, limit = limit)
    }
  )
  tool <- graft_tools(fixture$store)$graft_find
  polypropylene_id <- test_graft_id("tool-receipt-polypropylene")

  first <- tool(query = "polypropylene")
  graft_ingest(
    fixture$store,
    list(
      Entity = data.frame(
        id = polypropylene_id,
        preferred_name = "Polypropylene"
      )
    ),
    graft_provenance("test", idempotency_key = "tool-receipt-v2")
  )
  second <- tool(query = "polypropylene")

  expect_equal(nrow(first$result), 0L)
  expect_in(polypropylene_id, second$result$id)
  expect_identical(first$receipt$boundary$kind, "live")
  expect_named(
    first$receipt$boundary,
    c("kind", "batch_id", "commit_order")
  )
  expect_identical(
    first$receipt$boundary$batch_id,
    observed[[1L]]@batch_id
  )
  expect_identical(
    first$receipt$boundary$commit_order,
    observed[[1L]]@commit_order
  )
  expect_identical(
    second$receipt$boundary$batch_id,
    observed[[2L]]@batch_id
  )
  expect_identical(
    second$receipt$boundary$commit_order,
    observed[[2L]]@commit_order
  )
  expect_gt(
    second$receipt$boundary$commit_order,
    first$receipt$boundary$commit_order
  )
})

test_that("graft_history receipts its explicit historical boundary", {
  fixture <- local_retrieval_store()
  historical <- graft_snapshot(fixture$store)
  entity <- retrieval_fixture_records()$records$Entity[1L, , drop = FALSE]
  entity$preferred_name <- "Polyethylene resin"
  graft_ingest(
    fixture$store,
    list(Entity = entity),
    graft_provenance("test", idempotency_key = "tool-history-receipt-v2")
  )

  result <- graft_tools(fixture$store)$graft_history(
    id = fixture$ids$entity,
    as_of = historical@batch_id
  )

  expect_identical(
    result$receipt$boundary,
    list(
      kind = "history",
      batch_id = historical@batch_id,
      commit_order = historical@commit_order
    )
  )
  expect_equal(nrow(result$result), 1L)
})

test_that("explicit history receipts the selected boundary schema", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  schema <- graft_schema(tempest_manifest_path())
  store <- graft_open(schema, path, okf = "disabled")
  fixture <- retrieval_fixture_records()
  graft_ingest(
    store,
    fixture$records,
    graft_provenance("test", idempotency_key = "history-schema-v1")
  )
  historical <- graft_snapshot(store)
  graft_close(store)

  rebuilt <- as_graft_schema_internal(schema)
  rebuilt$manifest$schema$source_files[[1L]]$content_digest <-
    graft_sha256("history receipt rebuilt source")
  rebuilt$manifest$fingerprints$source_digest <- graft_linkml_source_digest(
    rebuilt$manifest$schema$source_files
  )
  rebuilt$manifest$fingerprints$build_digest <-
    manifest_build_digest(rebuilt$manifest)
  rebuilt <- new_graft_schema(rebuilt)
  reopened <- graft_open(rebuilt, path, okf = "disabled")
  withr::defer(graft_close(reopened))
  entity <- fixture$records$Entity[1L, , drop = FALSE]
  entity$preferred_name <- "Polyethylene resin"
  graft_ingest(
    reopened,
    list(Entity = entity),
    graft_provenance("test", idempotency_key = "history-schema-v2")
  )

  result <- graft_tools(reopened)$graft_history(
    id = fixture$ids$entity,
    as_of = historical@batch_id
  )

  expect_identical(
    result$receipt$schema,
    list(
      structural_digest = schema@structural_digest,
      build_digest = schema@build_digest
    )
  )
})

test_that("empty-store tool receipts name the empty accepted boundary", {
  store <- local_graft_ingest_store()

  result <- graft_tools(store)$graft_find(query = "nothing")

  expect_identical(
    result$receipt$boundary,
    list(
      kind = "live",
      batch_id = NULL,
      commit_order = 0
    )
  )
})

test_that("live integrity queries return a canonical receipt", {
  fixture <- local_retrieval_store()

  result <- graft_tools(fixture$store)$graft_query(operation = "integrity")
  boundary <- graft_snapshot(fixture$store)

  expect_named(result, c("result", "truncated", "limit", "receipt"))
  expect_s3_class(result$result, "data.frame")
  expect_identical(
    result$receipt$boundary,
    list(
      kind = "live",
      batch_id = boundary@batch_id,
      commit_order = boundary@commit_order
    )
  )
})

test_that("graft_tools delegates through the public retrieval API", {
  fixture <- local_retrieval_store()
  view <- graft_at(fixture$store, graft_snapshot(fixture$store))
  calls <- character()
  digest <- paste0("sha256:", strrep("a", 64L))
  tabular_result <- function(id, limit) {
    result <- data.frame(id = id)
    attr(result, "truncated") <- FALSE
    attr(result, "limit") <- limit
    attr(result, "store_schema_digest") <- digest
    result
  }
  local_mocked_bindings(
    graft_find = function(observed_store, query, class, limit) {
      expect_identical(observed_store, view)
      calls <<- c(calls, "graft_find")
      tabular_result(query, limit)
    },
    graft_get = function(observed_store, id, include, limits) {
      expect_identical(observed_store, view)
      calls <<- c(calls, "graft_get")
      list(
        id = id,
        truncated = list(
          identifiers = FALSE,
          claims = FALSE,
          evidence = FALSE
        ),
        limits = limits,
        store_schema_digest = digest
      )
    },
    graft_query = function(observed_store, operation, request, limit) {
      expect_identical(observed_store, view)
      calls <<- c(calls, "graft_query")
      tabular_result(operation, limit)
    },
    graft_history = function(observed_store, id, as_of, limit) {
      expect_identical(observed_store, view)
      calls <<- c(calls, "graft_history")
      tabular_result(id, limit)
    }
  )
  tools <- graft_tools(view)
  outputs <- list(
    tools$graft_find(query = "needle", limit = 2L),
    tools$graft_get(id = fixture$ids$entity, include = character()),
    tools$graft_query(operation = "identifiers", limit = 3L),
    tools$graft_history(id = fixture$ids$entity, limit = 4L)
  )
  operation <- agent_tool_prop(
    agent_tool_prop(
      agent_tool_prop(tools$graft_query, "arguments"),
      "properties"
    )$operation,
    "values"
  )

  expect_s7_class(view, graft:::GraftView)
  expect_named(
    tools,
    c("graft_find", "graft_get", "graft_query", "graft_history")
  )
  expect_identical(
    operation,
    setdiff(graft_tool_query_operations(), "integrity")
  )
  expect_identical(
    calls,
    c("graft_find", "graft_get", "graft_query", "graft_history")
  )
  expected_receipt <- list(
    store = list(id = fixture$store@id),
    boundary = list(
      kind = "snapshot",
      batch_id = view@batch_id,
      commit_order = view@commit_order,
      snapshot_id = view@snapshot_id
    ),
    schema = list(
      structural_digest = fixture$store@schema@structural_digest,
      build_digest = view@schema_build_digest
    )
  )
  for (output in outputs) {
    expect_named(output, c("result", "truncated", "limit", "receipt"))
    expect_identical(output$truncated, FALSE)
    expect_identical(output$receipt, expected_receipt)
  }
})

test_that("graft_tools has no mutation surface and leaves the store unchanged", {
  fixture <- local_retrieval_store()
  tools <- graft_tools(fixture$store)
  arguments <- lapply(
    tools,
    \(tool) agent_tool_prop(tool, "arguments")
  )
  exposed <- unique(unlist(lapply(
    arguments,
    \(argument) names(agent_tool_prop(argument, "properties"))
  )))
  before <- DBI::dbGetQuery(
    fixture$connection,
    paste(
      "SELECT COUNT(*) AS batches,",
      "COALESCE(MAX(commit_order), 0) AS commit_order FROM _graft_batches"
    )
  )

  tools$graft_find(query = "polyethylene")
  tools$graft_get(id = fixture$ids$entity, include = character())
  tools$graft_query(
    operation = "identifiers",
    request = list(id = fixture$ids$entity)
  )
  tools$graft_history(id = fixture$ids$entity)
  after <- DBI::dbGetQuery(
    fixture$connection,
    paste(
      "SELECT COUNT(*) AS batches,",
      "COALESCE(MAX(commit_order), 0) AS commit_order FROM _graft_batches"
    )
  )
  cap <- catch_graft_ingest_condition(
    tools$graft_find(query = "polyethylene", limit = 1001L)
  )
  arbitrary <- catch_graft_ingest_condition(
    tools$graft_query(
      operation = "claims",
      request = list(id = fixture$ids$entity, sql = "SELECT *")
    )
  )

  expect_identical(
    intersect(
      exposed,
      c(
        "records",
        "provenance",
        "plan",
        "commit",
        "ingest",
        "sql",
        "path",
        "url",
        "network",
        "connection",
        "write"
      )
    ),
    character()
  )
  expect_identical(before, after)
  expect_s3_class(cap, "graft_limit_error")
  expect_s3_class(arbitrary, "graft_validation_error")
})

test_that("graft_tools adds a bounded graft_measure tool when measures exist", {
  fixture <- local_retrieval_store()
  store <- fixture$store
  graft_ingest(
    store,
    list(
      GraftMeasure = data.frame(
        id = "measure:entity-count",
        name = "entity-count",
        title = "Entity count",
        description = "Number of accepted entities.",
        target_class = "Entity",
        expr = "COUNT(*)",
        parameters = "[]",
        dimensions = "[\"preferred_name\"]"
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "measure-tool-v1")
  )

  tools <- graft_tools(store)
  expect_named(
    tools,
    c(
      "graft_find",
      "graft_get",
      "graft_query",
      "graft_history",
      "graft_measure"
    )
  )
  properties <- agent_tool_prop(
    agent_tool_prop(tools$graft_measure, "arguments"),
    "properties"
  )
  expect_identical(agent_tool_prop(properties$name, "values"), "entity-count")
  expect_identical(
    agent_tool_prop(tools$graft_measure, "annotations"),
    list(
      read_only_hint = TRUE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE,
      destructive_hint = FALSE
    )
  )

  result <- tools$graft_measure(name = "entity-count")
  revision_id <- graft_history(store, "measure:entity-count")$revision_id[[1L]]
  expect_named(result, c("result", "truncated", "limit", "receipt"))
  expect_identical(result$result$value, 2)
  expect_identical(result$truncated, FALSE)
  expect_identical(
    result$receipt$definition,
    list(id = "measure:entity-count", revision_id = revision_id)
  )
  expect_match(result$receipt$schema$structural_digest, "^sha256:")
})

test_that("graft_tools omits graft_measure when no measures are accepted", {
  fixture <- local_retrieval_store()
  expect_named(
    graft_tools(fixture$store),
    c("graft_find", "graft_get", "graft_query", "graft_history")
  )
})
