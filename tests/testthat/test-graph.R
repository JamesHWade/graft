test_that("generated graph views have exact schemas and live contents", {
  fixture <- local_retrieval_store()
  store <- fixture$store
  literal_id <- test_graft_id("graph-literal-semantic")

  kg_write(
    store,
    kg_batch("graph-literal", idempotency_key = "graph-literal"),
    "SemanticClaim",
    data.frame(
      id = literal_id,
      subject = fixture$ids$entity,
      predicate = "schema:description",
      object_value = "A literal value",
      object_datatype = "xsd:string"
    )
  )

  nodes <- DBI::dbReadTable(store$connection, "_graft_nodes")
  semantic <- DBI::dbReadTable(store$connection, "_graft_edges")
  provenance <- DBI::dbReadTable(
    store$connection,
    "_graft_provenance_edges"
  )

  expect_named(
    nodes,
    c(
      "id",
      "class",
      "label",
      "role",
      "statement_shape",
      "type_uri",
      "created_at"
    )
  )
  expect_named(
    semantic,
    c(
      "edge_id",
      "subject",
      "predicate",
      "object",
      "edge_class",
      "source_table",
      "created_at"
    )
  )
  expect_named(
    provenance,
    c("edge_id", "subject", "predicate", "object", "source_table")
  )
  expect_identical(
    nodes$label[nodes$id == fixture$ids$entity],
    "Polyethylene"
  )
  expect_identical(
    nodes$label[nodes$id == fixture$ids$active_claim],
    "Polyethylene remains durable."
  )
  expect_identical(
    semantic$edge_id,
    fixture$ids$semantic_claim
  )
  expect_identical(
    literal_id %in% semantic$edge_id,
    FALSE
  )
  expect_identical(
    any(
      c(
        fixture$ids$active_claim,
        fixture$ids$competing_claim,
        fixture$ids$superseded_claim
      ) %in%
        semantic$edge_id
    ),
    FALSE
  )

  about <- provenance[
    provenance$predicate == "https://w3id.org/graft/about",
    ,
    drop = FALSE
  ]
  expect_in(fixture$ids$active_claim, about$subject)
  expect_in(fixture$ids$entity, about$object)
  expect_equal(
    provenance$object[
      provenance$subject == fixture$ids$evidence &
        provenance$predicate == "https://w3id.org/graft/source_id"
    ],
    fixture$ids$source
  )
  expect_equal(
    provenance$object[
      provenance$subject == fixture$ids$superseded_claim &
        provenance$predicate == "https://w3id.org/graft/superseded_by"
    ],
    fixture$ids$active_claim
  )
  expect_equal(
    provenance$object[
      provenance$subject == fixture$ids$resolved &
        provenance$predicate == "https://w3id.org/graft/entity_id"
    ],
    fixture$ids$entity
  )
  expect_equal(
    provenance$object[
      provenance$subject == fixture$ids$semantic_claim &
        provenance$predicate == "https://w3id.org/graft/derived_from_statement"
    ],
    fixture$ids$active_claim
  )
})

test_that("direct edge-role records project as semantic edges", {
  schema <- graph_schema_with_direct_edge()
  store <- local_ingest_store(schema = schema)
  subject <- test_graft_id("direct-edge-subject")
  object <- test_graft_id("direct-edge-object")
  edge <- test_graft_id("direct-edge")

  kg_ingest(
    store,
    kg_batch("direct-edge", idempotency_key = "direct-edge"),
    list(
      Entity = data.frame(
        id = c(subject, object),
        preferred_name = c("Subject", "Object")
      ),
      RelatedEdge = data.frame(
        id = edge,
        subject = subject,
        predicate = "schema:relatedTo",
        object = object
      )
    )
  )
  rows <- DBI::dbReadTable(store$connection, "_graft_edges")

  expect_identical(rows$edge_id, edge)
  expect_identical(rows$edge_class, "RelatedEdge")
  expect_identical(rows$subject, subject)
  expect_identical(rows$object, object)
})

test_that("graph accessors stay lazy and hide metadata tables", {
  fixture <- local_retrieval_store()

  nodes <- kg_nodes(fixture$store)
  semantic <- kg_edges(fixture$store, "semantic")
  provenance <- kg_edges(fixture$store, "provenance")
  combined <- kg_edges(fixture$store, "combined")

  expect_s3_class(nodes, "tbl_lazy")
  expect_s3_class(semantic, "tbl_lazy")
  expect_s3_class(provenance, "tbl_lazy")
  expect_s3_class(combined, "tbl_lazy")
  expect_match(dbplyr::remote_query(nodes), "_graft_nodes")
  expect_match(dbplyr::remote_query(semantic), "_graft_edges")
  expect_match(
    dbplyr::remote_query(provenance),
    "_graft_provenance_edges"
  )
  expect_match(dbplyr::remote_query(combined), "UNION ALL")
  expect_identical(
    attr(nodes, "store_schema_digest"),
    graft:::store_schema_digest(fixture$store)
  )
})

test_that("neighbors honor direction, predicates, and one or two hops", {
  fixture <- local_retrieval_store()
  store <- fixture$store

  outgoing <- kg_neighbors(
    store,
    fixture$ids$entity,
    predicate = "schema:relatedTo",
    direction = "out",
    projection = "semantic"
  )
  incoming <- kg_neighbors(
    store,
    fixture$ids$other_entity,
    direction = "in",
    projection = "semantic"
  )
  no_outgoing <- kg_neighbors(
    store,
    fixture$ids$other_entity,
    direction = "out",
    projection = "semantic"
  )
  no_predicate <- kg_neighbors(
    store,
    fixture$ids$entity,
    predicate = "schema:notPresent",
    direction = "out",
    projection = "semantic"
  )
  one_hop <- kg_neighbors(
    store,
    fixture$ids$active_claim,
    direction = "out",
    projection = "combined"
  )
  two_hop <- kg_neighbors(
    store,
    fixture$ids$active_claim,
    direction = "out",
    hops = 2,
    projection = "combined"
  )
  narrative_about <- kg_neighbors(
    store,
    fixture$ids$active_claim,
    predicate = "https://w3id.org/graft/about",
    direction = "out",
    projection = "provenance"
  )

  expect_identical(outgoing$edges$object, fixture$ids$other_entity)
  expect_identical(incoming$edges$subject, fixture$ids$entity)
  expect_identical(nrow(no_outgoing$edges), 0L)
  expect_identical(nrow(no_predicate$edges), 0L)
  expect_identical(fixture$ids$source %in% one_hop$nodes$id, FALSE)
  expect_identical(fixture$ids$source %in% two_hop$nodes$id, TRUE)
  expect_identical(narrative_about$edges$object, fixture$ids$entity)
  expect_s3_class(two_hop, "kg_subgraph")
  expect_identical(two_hop$request$kind, "neighbors")
  expect_identical(two_hop$hops, 2L)
})

test_that("predicate traversal and induced subgraphs are bounded and exact", {
  fixture <- local_retrieval_store()
  store <- fixture$store
  path <- c(
    "https://w3id.org/graft/evidence",
    "https://w3id.org/graft/source_id"
  )

  traversed <- kg_traverse(
    store,
    fixture$ids$active_claim,
    via = path
  )
  induced <- kg_subgraph(
    store,
    c(
      fixture$ids$active_claim,
      fixture$ids$evidence,
      fixture$ids$source
    )
  )

  expect_identical(traversed$path, path)
  expect_identical(
    traversed$nodes$id,
    sort(c(
      fixture$ids$active_claim,
      fixture$ids$evidence,
      fixture$ids$source
    ))
  )
  expect_identical(nrow(traversed$edges), 2L)
  expect_identical(nrow(induced$nodes), 3L)
  expect_identical(nrow(induced$edges), 2L)
  expect_identical(induced$request$kind, "subgraph")
  expect_identical(
    induced$store_schema_digest,
    graft:::store_schema_digest(store)
  )
})

test_that("graph limits truncate explicitly and ordering is deterministic", {
  fixture <- local_retrieval_store()
  store <- fixture$store

  node_limited <- kg_neighbors(
    store,
    fixture$ids$entity,
    hops = 2,
    projection = "combined",
    max_nodes = 2
  )
  edge_limited <- kg_neighbors(
    store,
    fixture$ids$entity,
    hops = 2,
    projection = "combined",
    max_edges = 1
  )
  induced_limited <- kg_subgraph(
    store,
    c(
      fixture$ids$active_claim,
      fixture$ids$evidence,
      fixture$ids$source
    ),
    max_edges = 1
  )
  repeated <- kg_neighbors(
    store,
    fixture$ids$entity,
    hops = 2,
    projection = "combined"
  )
  repeated_again <- kg_neighbors(
    store,
    fixture$ids$entity,
    hops = 2,
    projection = "combined"
  )

  expect_identical(nrow(node_limited$nodes), 2L)
  expect_identical(node_limited$truncated, TRUE)
  expect_identical(nrow(edge_limited$edges), 1L)
  expect_identical(edge_limited$truncated, TRUE)
  expect_identical(nrow(induced_limited$edges), 1L)
  expect_identical(induced_limited$truncated, TRUE)
  expect_identical(repeated$nodes, repeated_again$nodes)
  expect_identical(repeated$edges, repeated_again$edges)
  expect_identical(repeated$nodes$id, sort(repeated$nodes$id))
  expect_identical(
    graft:::graph_order_edges(repeated$edges),
    repeated$edges
  )
  expect_identical(repeated$limits$max_nodes, 500L)
  expect_identical(repeated$limits$max_edges, 2000L)

  hop_error <- catch_graft_ingest_condition(
    kg_neighbors(store, fixture$ids$entity, hops = 3)
  )
  node_error <- catch_graft_ingest_condition(
    kg_neighbors(store, fixture$ids$entity, max_nodes = 501)
  )
  edge_error <- catch_graft_ingest_condition(
    kg_neighbors(store, fixture$ids$entity, max_edges = 2001)
  )
  path_error <- catch_graft_ingest_condition(
    kg_traverse(
      store,
      fixture$ids$entity,
      via = rep("schema:relatedTo", 3)
    )
  )

  expect_s3_class(hop_error, "graft_limit_error")
  expect_s3_class(node_error, "graft_limit_error")
  expect_s3_class(edge_error, "graft_limit_error")
  expect_s3_class(path_error, "graft_limit_error")
})

test_that("dangling graph endpoints raise structured reference errors", {
  fixture <- local_retrieval_store()
  missing <- test_graft_id("missing-graph-endpoint")
  corrupt_statement <- test_graft_id("corrupt-semantic-statement")
  sql <- paste0(
    "INSERT INTO semantic_claim ",
    "(id, subject, predicate, object_entity) VALUES (?, ?, ?, ?)"
  )
  DBI::dbExecute(
    fixture$store$connection,
    sql,
    params = list(
      corrupt_statement,
      fixture$ids$entity,
      "schema:corruptEdge",
      missing
    )
  )

  condition <- catch_graft_ingest_condition(
    kg_neighbors(
      fixture$store,
      fixture$ids$entity,
      predicate = "schema:corruptEdge",
      direction = "out",
      projection = "semantic"
    )
  )

  expect_s3_class(condition, "graft_reference_error")
  expect_identical(condition$rule, "graph_endpoint_exists")
  expect_in(missing, condition$missing_record_ids)
})
