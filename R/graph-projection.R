graft_graph_view_names <- c(
  "_graft_nodes",
  "_graft_edges",
  "_graft_provenance_edges"
)

drop_graph_views <- function(connection) {
  for (name in graft_graph_view_names) {
    DBI::dbExecute(
      connection,
      paste0(
        "DROP VIEW IF EXISTS ",
        quote_identifier(connection, name)
      )
    )
  }
  invisible(connection)
}

create_graph_views <- function(connection, schema) {
  definitions <- graph_view_definitions(connection, schema)
  for (name in names(definitions)) {
    sql <- paste0(
      "CREATE OR REPLACE VIEW ",
      quote_identifier(connection, name),
      " AS ",
      definitions[[name]]
    )
    DBI::dbExecute(connection, sql)
  }
  invisible(connection)
}

verify_graph_views <- function(connection) {
  missing <- graft_graph_view_names[
    !vapply(
      graft_graph_view_names,
      \(.x) duckdb_table_exists(connection, .x),
      logical(1)
    )
  ]
  if (length(missing) > 0L) {
    abort_backend_error(
      paste0(
        "The initialized read-only store is missing generated graph view(s): ",
        paste(missing, collapse = ", "),
        ". Reopen it writable and call `kg_init()`."
      ),
      operation = "verify_graph_views",
      missing_views = missing
    )
  }
  invisible(connection)
}

graph_view_definitions <- function(connection, schema) {
  list(
    `_graft_nodes` = graph_nodes_view_sql(connection, schema),
    `_graft_edges` = graph_semantic_edges_view_sql(connection, schema),
    `_graft_provenance_edges` = graph_provenance_edges_view_sql(
      connection,
      schema
    )
  )
}

graph_projection_classes <- function(schema, projection) {
  manifest <- schema$manifest
  declared <- manifest$graph_projections[[projection]]
  classes <- manifest$classes

  if (identical(projection, "node_classes")) {
    declared_names <- empty_character(declared)
    if (length(declared_names) == 0L) {
      declared_names <- names(Filter(
        \(.x) {
          scalar_character(.x$role) %in%
            c("node", "statement", "evidence", "source")
        },
        classes
      ))
    }
    mention_classes <- names(Filter(
      \(.x) identical(scalar_character(.x$role), "mention"),
      classes
    ))
    return(sort(unique(c(declared_names, mention_classes))))
  }

  empty_character(declared)
}

graph_nodes_view_sql <- function(connection, schema) {
  classes <- graph_projection_classes(schema, "node_classes")
  parts <- lapply(classes, function(record_class) {
    contract <- schema$manifest$classes[[record_class]]
    if (is.null(contract)) {
      abort_schema_error(
        paste0(
          "Graph projection refers to unknown class `",
          record_class,
          "`."
        ),
        record_class = record_class,
        projection = "nodes"
      )
    }
    graph_node_select_sql(connection, record_class, contract)
  })
  graph_union_sql(parts, graph_empty_nodes_sql())
}

graph_node_select_sql <- function(connection, record_class, contract) {
  id <- graph_slot_identifier(connection, contract, "id")
  created_at <- graph_optional_slot_expression(
    connection,
    contract,
    "created_at",
    "TIMESTAMP"
  )
  label <- graph_label_expression(connection, contract)
  statement_shape <- graph_sql_string(
    connection,
    scalar_character(contract$statement_shape)
  )
  paste0(
    "SELECT CAST(",
    id,
    " AS VARCHAR) AS id, ",
    graph_sql_string(connection, record_class),
    " AS class, ",
    label,
    " AS label, ",
    graph_sql_string(connection, scalar_character(contract$role)),
    " AS role, ",
    statement_shape,
    " AS statement_shape, ",
    graph_sql_string(connection, scalar_character(contract$type_uri)),
    " AS type_uri, CAST(",
    created_at,
    " AS TIMESTAMP) AS created_at FROM ",
    quote_identifier(connection, scalar_character(contract$table))
  )
}

graph_label_expression <- function(connection, contract) {
  candidates <- unique(c(
    scalar_character(contract$label_slot),
    empty_character(contract$search_slots),
    "label",
    "title",
    "name",
    "statement_text",
    "surface_form"
  ))
  candidates <- candidates[
    !is.na(candidates) &
      candidates %in% names(contract$slots)
  ]
  candidates <- Filter(
    function(slot_name) {
      slot <- contract$slots[[slot_name]]
      !scalar_logical(slot$multivalued) &&
        !scalar_logical(slot$sensitive) &&
        !scalar_logical(slot$object_reference) &&
        !is.na(scalar_character(slot$column))
    },
    candidates
  )
  if (length(candidates) == 0L) {
    return("CAST(NULL AS VARCHAR)")
  }
  columns <- vapply(
    candidates,
    function(slot_name) {
      paste0(
        "NULLIF(TRIM(CAST(",
        graph_slot_identifier(connection, contract, slot_name),
        " AS VARCHAR)), '')"
      )
    },
    character(1)
  )
  paste0("COALESCE(", paste(columns, collapse = ", "), ")")
}

graph_semantic_edges_view_sql <- function(connection, schema) {
  manifest <- schema$manifest
  projection <- manifest$graph_projections$semantic_edges
  direct <- empty_character(projection$direct_edge_classes)
  if (length(direct) == 0L) {
    direct <- names(Filter(
      \(.x) identical(scalar_character(.x$role), "edge"),
      manifest$classes
    ))
  }
  semantic <- empty_character(projection$semantic_statement_classes)
  if (length(semantic) == 0L) {
    semantic <- names(Filter(
      \(.x) identical(scalar_character(.x$statement_shape), "semantic"),
      manifest$classes
    ))
  }

  parts <- c(
    lapply(sort(unique(direct)), function(record_class) {
      contract <- graph_projection_contract(
        schema,
        record_class,
        "semantic edges"
      )
      graph_direct_edge_select_sql(connection, record_class, contract)
    }),
    lapply(sort(unique(semantic)), function(record_class) {
      contract <- graph_projection_contract(
        schema,
        record_class,
        "semantic edges"
      )
      graph_semantic_statement_select_sql(
        connection,
        record_class,
        contract
      )
    })
  )
  graph_union_sql(parts, graph_empty_semantic_edges_sql())
}

graph_direct_edge_select_sql <- function(connection, record_class, contract) {
  fixed_predicate <- scalar_character(contract$fixed_predicate)
  predicate <- if (is.na(fixed_predicate)) {
    graph_slot_identifier(connection, contract, "predicate")
  } else {
    graph_sql_string(connection, fixed_predicate)
  }
  graph_edge_select_sql(
    connection = connection,
    record_class = record_class,
    contract = contract,
    edge_id = graph_slot_identifier(connection, contract, "id"),
    subject = graph_slot_identifier(connection, contract, "subject"),
    predicate = predicate,
    object = graph_slot_identifier(connection, contract, "object")
  )
}

graph_semantic_statement_select_sql <- function(
  connection,
  record_class,
  contract
) {
  object <- graph_slot_identifier(connection, contract, "object_entity")
  paste0(
    graph_edge_select_sql(
      connection = connection,
      record_class = record_class,
      contract = contract,
      edge_id = graph_slot_identifier(connection, contract, "id"),
      subject = graph_slot_identifier(connection, contract, "subject"),
      predicate = graph_slot_identifier(connection, contract, "predicate"),
      object = object
    ),
    " WHERE ",
    object,
    " IS NOT NULL"
  )
}

graph_edge_select_sql <- function(
  connection,
  record_class,
  contract,
  edge_id,
  subject,
  predicate,
  object
) {
  created_at <- graph_optional_slot_expression(
    connection,
    contract,
    "created_at",
    "TIMESTAMP"
  )
  paste0(
    "SELECT CAST(",
    edge_id,
    " AS VARCHAR) AS edge_id, CAST(",
    subject,
    " AS VARCHAR) AS subject, CAST(",
    predicate,
    " AS VARCHAR) AS predicate, CAST(",
    object,
    " AS VARCHAR) AS object, ",
    graph_sql_string(connection, record_class),
    " AS edge_class, ",
    graph_sql_string(connection, scalar_character(contract$table)),
    " AS source_table, CAST(",
    created_at,
    " AS TIMESTAMP) AS created_at FROM ",
    quote_identifier(connection, scalar_character(contract$table))
  )
}

graph_provenance_edges_view_sql <- function(connection, schema) {
  manifest <- schema$manifest
  projection <- manifest$graph_projections$provenance_edges
  narrative <- empty_character(projection$narrative_statement_classes)
  if (length(narrative) == 0L) {
    narrative <- names(Filter(
      \(.x) identical(scalar_character(.x$statement_shape), "narrative"),
      manifest$classes
    ))
  }
  parts <- list()

  narrative_slots <- empty_character(projection$narrative_slots)
  if (length(narrative_slots) == 0L) {
    narrative_slots <- c("about", "primary_subject")
  }
  if ("about" %in% narrative_slots) {
    relations <- Filter(
      \(.x) {
        scalar_character(.x$owner_class) %in%
          narrative &&
          identical(scalar_character(.x$slot), "about") &&
          identical(scalar_character(.x$kind), "object")
      },
      manifest$relations
    )
    parts <- c(
      parts,
      lapply(relations, function(relation) {
        graph_relation_provenance_select_sql(connection, relation)
      })
    )
  }
  if ("primary_subject" %in% narrative_slots) {
    parts <- c(
      parts,
      lapply(narrative, function(record_class) {
        contract <- graph_projection_contract(
          schema,
          record_class,
          "provenance edges"
        )
        graph_scalar_provenance_select_sql(
          connection,
          contract,
          subject_slot = "id",
          object_slot = "primary_subject",
          predicate = graph_slot_predicate(contract, "primary_subject"),
          edge_kind = "primary_subject"
        )
      })
    )
  }

  if (scalar_logical(projection$statement_to_evidence, TRUE)) {
    evidence <- graph_role_class_names(schema, "evidence")
    parts <- c(
      parts,
      lapply(evidence, function(record_class) {
        contract <- manifest$classes[[record_class]]
        graph_scalar_provenance_select_sql(
          connection,
          contract,
          subject_slot = "statement_id",
          object_slot = "id",
          predicate = graft_predicate_uri("evidence"),
          edge_kind = "statement_evidence",
          edge_owner_slot = "id"
        )
      })
    )
  }
  if (scalar_logical(projection$evidence_to_source, TRUE)) {
    evidence <- graph_role_class_names(schema, "evidence")
    parts <- c(
      parts,
      lapply(evidence, function(record_class) {
        contract <- manifest$classes[[record_class]]
        graph_scalar_provenance_select_sql(
          connection,
          contract,
          subject_slot = "id",
          object_slot = "source_id",
          predicate = graph_slot_predicate(contract, "source_id"),
          edge_kind = "evidence_source"
        )
      })
    )
  }
  if (scalar_logical(projection$supersession, TRUE)) {
    statements <- graph_role_class_names(schema, "statement")
    parts <- c(
      parts,
      lapply(statements, function(record_class) {
        contract <- manifest$classes[[record_class]]
        graph_scalar_provenance_select_sql(
          connection,
          contract,
          subject_slot = "id",
          object_slot = "superseded_by",
          predicate = graph_slot_predicate(contract, "superseded_by"),
          edge_kind = "superseded_by"
        )
      })
    )
  }
  if (scalar_logical(projection$mention_resolution, TRUE)) {
    mentions <- graph_role_class_names(schema, "mention")
    parts <- c(
      parts,
      lapply(mentions, function(record_class) {
        contract <- manifest$classes[[record_class]]
        graph_scalar_provenance_select_sql(
          connection,
          contract,
          subject_slot = "id",
          object_slot = "entity_id",
          predicate = graph_slot_predicate(contract, "entity_id"),
          edge_kind = "mention_entity"
        )
      })
    )
  }
  if (scalar_logical(projection$semantic_derivation, TRUE)) {
    semantic <- names(Filter(
      \(.x) identical(scalar_character(.x$statement_shape), "semantic"),
      manifest$classes
    ))
    parts <- c(
      parts,
      lapply(semantic, function(record_class) {
        contract <- manifest$classes[[record_class]]
        graph_scalar_provenance_select_sql(
          connection,
          contract,
          subject_slot = "id",
          object_slot = "derived_from_statement",
          predicate = graph_slot_predicate(
            contract,
            "derived_from_statement"
          ),
          edge_kind = "semantic_derivation"
        )
      })
    )
  }

  graph_union_sql(parts, graph_empty_provenance_edges_sql())
}

graph_relation_provenance_select_sql <- function(connection, relation) {
  table <- scalar_character(relation$table)
  id <- quote_identifier(connection, "id")
  paste0(
    "SELECT CONCAT(CAST(",
    id,
    " AS VARCHAR), '#about') AS edge_id, CAST(",
    quote_identifier(connection, "subject"),
    " AS VARCHAR) AS subject, ",
    graph_sql_string(connection, scalar_character(relation$predicate)),
    " AS predicate, CAST(",
    quote_identifier(connection, "object"),
    " AS VARCHAR) AS object, ",
    graph_sql_string(connection, table),
    " AS source_table FROM ",
    quote_identifier(connection, table)
  )
}

graph_scalar_provenance_select_sql <- function(
  connection,
  contract,
  subject_slot,
  object_slot,
  predicate,
  edge_kind,
  edge_owner_slot = subject_slot
) {
  if (
    !all(
      c(subject_slot, object_slot, edge_owner_slot) %in%
        names(contract$slots)
    )
  ) {
    return(NULL)
  }
  subject <- graph_slot_identifier(connection, contract, subject_slot)
  object <- graph_slot_identifier(connection, contract, object_slot)
  edge_owner <- graph_slot_identifier(connection, contract, edge_owner_slot)
  table <- scalar_character(contract$table)
  paste0(
    "SELECT CONCAT(CAST(",
    edge_owner,
    " AS VARCHAR), ",
    graph_sql_string(connection, paste0("#", edge_kind)),
    ") AS edge_id, CAST(",
    subject,
    " AS VARCHAR) AS subject, ",
    graph_sql_string(connection, predicate),
    " AS predicate, CAST(",
    object,
    " AS VARCHAR) AS object, ",
    graph_sql_string(connection, table),
    " AS source_table FROM ",
    quote_identifier(connection, table),
    " WHERE ",
    subject,
    " IS NOT NULL AND ",
    object,
    " IS NOT NULL"
  )
}

graph_projection_contract <- function(schema, record_class, projection) {
  contract <- schema$manifest$classes[[record_class]]
  if (is.null(contract)) {
    abort_schema_error(
      paste0(
        "Graph projection `",
        projection,
        "` refers to unknown class `",
        record_class,
        "`."
      ),
      record_class = record_class,
      projection = projection
    )
  }
  contract
}

graph_role_class_names <- function(schema, role) {
  names(Filter(
    \(.x) identical(scalar_character(.x$role), role),
    schema$manifest$classes
  ))
}

graph_slot_identifier <- function(connection, contract, slot_name) {
  slot <- contract$slots[[slot_name]]
  column <- scalar_character(slot$column)
  if (is.null(slot) || is.na(column)) {
    abort_schema_error(
      paste0(
        "Graph projection requires scalar slot `",
        slot_name,
        "` on class `",
        scalar_character(contract$name),
        "`."
      ),
      record_class = scalar_character(contract$name),
      slot = slot_name
    )
  }
  quote_identifier(connection, column)
}

graph_optional_slot_expression <- function(
  connection,
  contract,
  slot_name,
  type
) {
  slot <- contract$slots[[slot_name]]
  column <- scalar_character(slot$column)
  if (is.null(slot) || is.na(column)) {
    return(paste0("CAST(NULL AS ", safe_duckdb_type(type), ")"))
  }
  quote_identifier(connection, column)
}

graph_slot_predicate <- function(contract, slot_name) {
  slot <- contract$slots[[slot_name]]
  meaning <- scalar_character(slot$meaning)
  if (!is.na(meaning)) {
    return(meaning)
  }
  graft_predicate_uri(slot_name)
}

graft_predicate_uri <- function(slot_name) {
  paste0("https://w3id.org/graft/", slot_name)
}

graph_sql_string <- function(connection, value) {
  if (length(value) == 0L || is.na(value[[1L]])) {
    return("CAST(NULL AS VARCHAR)")
  }
  as.character(DBI::dbQuoteString(connection, as.character(value[[1L]])))
}

graph_union_sql <- function(parts, empty_sql) {
  parts <- Filter(
    \(.x) !is.null(.x) && length(.x) == 1L && nzchar(.x),
    parts
  )
  if (length(parts) == 0L) {
    return(empty_sql)
  }
  paste(parts, collapse = " UNION ALL ")
}

graph_empty_nodes_sql <- function() {
  paste0(
    "SELECT CAST(NULL AS VARCHAR) AS id, ",
    "CAST(NULL AS VARCHAR) AS class, ",
    "CAST(NULL AS VARCHAR) AS label, ",
    "CAST(NULL AS VARCHAR) AS role, ",
    "CAST(NULL AS VARCHAR) AS statement_shape, ",
    "CAST(NULL AS VARCHAR) AS type_uri, ",
    "CAST(NULL AS TIMESTAMP) AS created_at WHERE FALSE"
  )
}

graph_empty_semantic_edges_sql <- function() {
  paste0(
    "SELECT CAST(NULL AS VARCHAR) AS edge_id, ",
    "CAST(NULL AS VARCHAR) AS subject, ",
    "CAST(NULL AS VARCHAR) AS predicate, ",
    "CAST(NULL AS VARCHAR) AS object, ",
    "CAST(NULL AS VARCHAR) AS edge_class, ",
    "CAST(NULL AS VARCHAR) AS source_table, ",
    "CAST(NULL AS TIMESTAMP) AS created_at WHERE FALSE"
  )
}

graph_empty_provenance_edges_sql <- function() {
  paste0(
    "SELECT CAST(NULL AS VARCHAR) AS edge_id, ",
    "CAST(NULL AS VARCHAR) AS subject, ",
    "CAST(NULL AS VARCHAR) AS predicate, ",
    "CAST(NULL AS VARCHAR) AS object, ",
    "CAST(NULL AS VARCHAR) AS source_table WHERE FALSE"
  )
}

#' Access the graph node projection
#'
#' `kg_nodes()` returns the generated, manifest-driven node projection. It is
#' lazy and never collects implicitly.
#'
#' @param store An initialized `kg_store`.
#'
#' @return A lazy dbplyr table with node identifiers, classes, labels, roles,
#'   statement shapes, type URIs, and creation times.
#' @export
kg_nodes <- function(store) {
  validate_retrieval_store(store)
  result <- dplyr::tbl(store$connection, "_graft_nodes")
  attr(result, "store_schema_digest") <- store_schema_digest(store)
  result
}

#' Access a graph edge projection
#'
#' `kg_edges()` returns semantic edges, provenance edges, or their normalized
#' union. Semantic edges are only direct edge records and entity-valued
#' semantic statements. Narrative statements and literal objects are never
#' semantic edges. The result is lazy and never collects implicitly.
#'
#' @param store An initialized `kg_store`.
#' @param projection One of `"semantic"`, `"provenance"`, or `"combined"`.
#'
#' @return A lazy dbplyr table. The combined projection adds `edge_class` and
#'   `created_at` columns to provenance rows to match the semantic schema.
#' @export
kg_edges <- function(
  store,
  projection = c("semantic", "provenance", "combined")
) {
  validate_retrieval_store(store)
  projection <- rlang::arg_match(projection)
  if (identical(projection, "semantic")) {
    result <- dplyr::tbl(store$connection, "_graft_edges")
  } else if (identical(projection, "provenance")) {
    result <- dplyr::tbl(store$connection, "_graft_provenance_edges")
  } else {
    result <- dplyr::tbl(
      store$connection,
      dbplyr::sql(graph_combined_edges_sql(store$connection))
    )
  }
  attr(result, "graft_projection") <- projection
  attr(result, "store_schema_digest") <- store_schema_digest(store)
  result
}

graph_combined_edges_sql <- function(connection) {
  paste0(
    "SELECT edge_id, subject, predicate, object, edge_class, source_table, ",
    "created_at FROM ",
    quote_identifier(connection, "_graft_edges"),
    " UNION ALL SELECT edge_id, subject, predicate, object, ",
    "'provenance' AS edge_class, source_table, ",
    "CAST(NULL AS TIMESTAMP) AS created_at FROM ",
    quote_identifier(connection, "_graft_provenance_edges")
  )
}
