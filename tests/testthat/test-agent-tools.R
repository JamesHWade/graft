test_that("kg_tools returns exactly six safe read-only ToolDefs", {
  fixture <- local_retrieval_store()
  tools <- kg_tools(fixture$store)
  expected <- c(
    "kg_describe",
    "kg_find",
    "kg_get",
    "kg_neighbors",
    "kg_claims",
    "kg_select"
  )

  expect_named(tools, expected)
  expect_identical(length(tools), 6L)
  expect_identical(
    vapply(tools, inherits, logical(1), "ellmer::ToolDef"),
    stats::setNames(rep(TRUE, 6L), expected)
  )
  expect_identical(
    vapply(tools, \(.x) .x@name, character(1)),
    stats::setNames(expected, expected)
  )
  expected_annotations <- list(
    read_only_hint = TRUE,
    open_world_hint = FALSE,
    idempotent_hint = TRUE,
    destructive_hint = FALSE
  )
  expect_identical(
    lapply(tools, \(.x) .x@annotations),
    rep(list(expected_annotations), 6L) |>
      stats::setNames(expected)
  )
  expect_identical(
    vapply(
      tools,
      \(.x) .x@arguments@additional_properties,
      logical(1)
    ),
    stats::setNames(rep(FALSE, 6L), expected)
  )
  exposed <- unique(unlist(lapply(
    tools,
    \(.x) names(.x@arguments@properties)
  )))
  expect_identical(
    intersect(
      exposed,
      c("sql", "query_sql", "path", "file", "url", "network", "connection")
    ),
    character()
  )
})

test_that("kg_tools checks its optional ellmer dependency first", {
  first_expression <- body(kg_tools)[[2L]]

  expect_identical(
    deparse(first_expression[[1L]]),
    "rlang::check_installed"
  )
  expect_identical(first_expression[[2L]], "ellmer")
  expect_match(
    first_expression$reason,
    "kg_tools",
    fixed = TRUE
  )
})

test_that("ToolDef schemas encode defaults, enums, and hard caps", {
  fixture <- local_retrieval_store()
  tools <- kg_tools(fixture$store)
  find <- tools$kg_find@arguments@properties
  get <- tools$kg_get@arguments@properties
  neighbors <- tools$kg_neighbors@arguments@properties
  select <- tools$kg_select@arguments@properties

  expect_named(find, c("query", "class", "limit"))
  expect_identical(find$query@required, TRUE)
  expect_identical(find$class@required, FALSE)
  expect_identical(find$limit@required, FALSE)
  expect_identical(find$limit@json$maximum, 1000L)

  expect_named(get, c("id", "include", "limits"))
  expect_identical(
    get$include@items@values,
    c("identifiers", "claims", "evidence")
  )
  expect_identical(get$limits@required, FALSE)
  expect_identical(
    get$limits@properties$evidence@json$maximum,
    2000L
  )

  expect_named(
    neighbors,
    c(
      "id",
      "predicate",
      "direction",
      "hops",
      "projection",
      "max_nodes",
      "max_edges"
    )
  )
  expect_identical(
    neighbors$direction@values,
    c("both", "out", "in")
  )
  expect_identical(neighbors$hops@json$maximum, 2L)
  expect_identical(neighbors$max_nodes@json$maximum, 500L)
  expect_identical(neighbors$max_edges@json$maximum, 2000L)

  expect_named(
    select,
    c("class", "fields", "filters", "order_by", "limit")
  )
  filter_schema <- select$filters@items@json
  order_schema <- select$order_by@items@json
  expect_identical(filter_schema$additionalProperties, FALSE)
  expect_identical(
    unlist(filter_schema$required, use.names = FALSE),
    c("field", "operator")
  )
  expect_setequal(
    unlist(filter_schema$properties$operator$enum),
    c(
      "eq",
      "ne",
      "in",
      "contains",
      "starts_with",
      "gt",
      "gte",
      "lt",
      "lte",
      "is_null",
      "not_null"
    )
  )
  value_schema <- filter_schema$properties$value
  expect_named(value_schema, "anyOf")
  expect_length(value_schema$anyOf, 6L)
  expect_named(value_schema$anyOf[[6L]]$items, "anyOf")
  expect_length(value_schema$anyOf[[6L]]$items$anyOf, 4L)
  expect_identical(order_schema$additionalProperties, FALSE)
  expect_identical(
    unlist(order_schema$properties$direction$enum),
    c("asc", "desc")
  )
  expect_identical(select$limit@json$maximum, 1000L)

  expect_identical(eval(formals(tools$kg_find)$limit), 20)
  expect_identical(
    eval(formals(tools$kg_get)$include),
    c(
      "identifiers",
      "claims",
      "evidence"
    )
  )
  expect_identical(eval(formals(tools$kg_neighbors)$direction), "both")
  expect_identical(eval(formals(tools$kg_neighbors)$projection), "semantic")
  expect_identical(eval(formals(tools$kg_claims)$limit), 100)
  expect_identical(eval(formals(tools$kg_select)$filters), list())
})

test_that("kg_select tool accepts integer and mixed numeric filter values", {
  fixture <- local_retrieval_store()
  tool <- kg_tools(fixture$store)$kg_select

  integer <- tool(
    class = "SemanticClaim",
    fields = c("id", "temperature"),
    filters = list(list(
      field = "temperature",
      operator = "eq",
      value = 23L
    ))
  )
  mixed <- tool(
    class = "SemanticClaim",
    fields = c("id", "temperature"),
    filters = list(list(
      field = "temperature",
      operator = "in",
      value = c(22L, 23)
    ))
  )

  expect_identical(integer$result$id, fixture$ids$semantic_claim)
  expect_identical(integer$result$temperature, 23)
  expect_identical(mixed$result$id, fixture$ids$semantic_claim)
  expect_identical(mixed$result$temperature, 23)
})

test_that("ToolDefs invoke directly and return universal metadata", {
  fixture <- local_retrieval_store()
  tools <- kg_tools(fixture$store)
  outputs <- list(
    kg_describe = tools$kg_describe(token_budget = 40),
    kg_find = tools$kg_find(query = "polyethylene"),
    kg_get = tools$kg_get(id = fixture$ids$entity),
    kg_neighbors = tools$kg_neighbors(id = fixture$ids$entity),
    kg_claims = tools$kg_claims(entity_id = fixture$ids$entity),
    kg_select = tools$kg_select(
      class = "Entity",
      fields = c("id", "preferred_name")
    )
  )
  digest <- graft:::store_schema_digest(fixture$store)

  for (output in outputs) {
    expect_named(
      output,
      c("result", "truncated", "limit", "store_schema_digest")
    )
    expect_identical(length(output$truncated), 1L)
    expect_type(output$truncated, "logical")
    expect_identical(output$store_schema_digest, digest)
    expect_identical(is.null(output$limit), FALSE)
  }
  expect_s3_class(outputs$kg_describe$result, "kg_context")
  expect_s3_class(outputs$kg_find$result, "data.frame")
  expect_s3_class(outputs$kg_get$result, "kg_record")
  expect_s3_class(outputs$kg_neighbors$result, "kg_subgraph")
  expect_s3_class(outputs$kg_claims$result, "data.frame")
  expect_s3_class(outputs$kg_select$result, "data.frame")

  expect_identical(outputs$kg_describe$limit, 40L)
  expect_identical(outputs$kg_find$limit, 20L)
  expect_named(
    outputs$kg_get$limit,
    c("identifiers", "claims", "evidence")
  )
  expect_identical(
    outputs$kg_neighbors$limit,
    list(nodes = 500L, edges = 2000L, hops = 1L)
  )
  expect_identical(outputs$kg_claims$limit, 100L)
  expect_identical(outputs$kg_select$limit, 100L)
  expect_identical(outputs$kg_neighbors$result$projection, "semantic")
})

test_that("ToolDef envelopes report truncation and preserve native limits", {
  fixture <- local_retrieval_store()
  tools <- kg_tools(fixture$store)

  found <- tools$kg_find(query = "polyethylene", limit = 1)
  record <- tools$kg_get(
    id = fixture$ids$entity,
    limits = list(claims = 1L)
  )
  neighbors <- tools$kg_neighbors(
    id = fixture$ids$entity,
    projection = "combined",
    max_nodes = 1
  )
  claims <- tools$kg_claims(
    entity_id = fixture$ids$entity,
    limit = 1
  )
  selected <- tools$kg_select(
    class = "Entity",
    fields = "id",
    limit = 1
  )

  expect_identical(found$truncated, TRUE)
  expect_identical(found$limit, 1L)
  expect_identical(record$truncated, TRUE)
  expect_identical(record$limit$claims, 1L)
  expect_identical(neighbors$truncated, TRUE)
  expect_identical(
    neighbors$limit,
    list(nodes = 1L, edges = 2000L, hops = 1L)
  )
  expect_identical(claims$truncated, TRUE)
  expect_identical(claims$limit, 1L)
  expect_identical(selected$truncated, TRUE)
  expect_identical(selected$limit, 1L)
})

test_that("ToolDef calls retain graft runtime validation and hard caps", {
  fixture <- local_retrieval_store()
  tools <- kg_tools(fixture$store)

  bad_field <- catch_graft_ingest_condition(
    tools$kg_select(class = "Entity", fields = "private_sql")
  )
  bad_operator <- catch_graft_ingest_condition(
    tools$kg_select(
      class = "Entity",
      fields = "id",
      filters = list(list(
        field = "id",
        operator = "sql",
        value = fixture$ids$entity
      ))
    )
  )
  sql_member <- catch_graft_ingest_condition(
    tools$kg_select(
      class = "Entity",
      fields = "id",
      filters = list(list(
        field = "id",
        operator = "eq",
        value = fixture$ids$entity,
        sql = "OR TRUE"
      ))
    )
  )
  find_cap <- catch_graft_ingest_condition(
    tools$kg_find(query = "x", limit = 1001)
  )
  graph_cap <- catch_graft_ingest_condition(
    tools$kg_neighbors(id = fixture$ids$entity, max_edges = 2001)
  )
  describe_cap <- catch_graft_ingest_condition(
    tools$kg_describe(token_budget = 10001)
  )

  expect_s3_class(bad_field, "graft_validation_error")
  expect_identical(bad_field$rule, "public_scalar_field")
  expect_s3_class(bad_operator, "graft_validation_error")
  expect_identical(bad_operator$rule, "supported_filter_operator")
  expect_s3_class(sql_member, "graft_validation_error")
  expect_identical(sql_member$rule, "filter_shape")
  expect_s3_class(find_cap, "graft_limit_error")
  expect_identical(find_cap$hard_limit, 1000L)
  expect_s3_class(graph_cap, "graft_limit_error")
  expect_identical(graph_cap$hard_limit, 2000L)
  expect_s3_class(describe_cap, "graft_limit_error")
  expect_identical(describe_cap$hard_limit, 10000L)
})
