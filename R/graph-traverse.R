graph_result_limits <- list(
  nodes = 500L,
  edges = 2000L,
  hops = 2L
)

#' Retrieve a bounded graph neighborhood
#'
#' `kg_neighbors()` performs deterministic breadth-first expansion for one or
#' two hops. It only follows generated graph projections and always collects a
#' bounded result.
#'
#' @param store An initialized `kg_store`.
#' @param id One projected graph node identifier.
#' @param predicate Optional exact predicate restriction applied at every hop.
#' @param direction One of `"both"`, `"out"`, or `"in"`.
#' @param hops One or two hops.
#' @param projection One of `"semantic"`, `"provenance"`, or `"combined"`.
#' @param max_nodes Maximum collected nodes, up to 500.
#' @param max_edges Maximum collected edges, up to 2,000.
#'
#' @return A collected `kg_subgraph` with nodes, edges, request metadata,
#'   limits, truncation state, and the store structural digest.
#' @export
kg_neighbors <- function(
  store,
  id,
  predicate = NULL,
  direction = c("both", "out", "in"),
  hops = 1,
  projection = c("semantic", "provenance", "combined"),
  max_nodes = 500,
  max_edges = 2000
) {
  validate_retrieval_store(store)
  id <- validate_scalar_text(id, "id", condition = abort_reference_error)
  predicate <- validate_optional_scalar_text(predicate, "predicate")
  direction <- rlang::arg_match(direction)
  projection <- rlang::arg_match(projection)
  hops <- validate_result_limit(
    hops,
    "hops",
    hard_limit = graph_result_limits$hops
  )
  limits <- validate_graph_limits(max_nodes, max_edges)
  graph_assert_node_ids(store, id, field = "id")

  path <- if (is.null(predicate)) {
    rep(list(NULL), hops)
  } else {
    rep(list(predicate), hops)
  }
  result <- graph_expand(
    store = store,
    roots = id,
    predicates = path,
    direction = direction,
    projection = projection,
    limits = limits
  )
  new_kg_subgraph(
    nodes = result$nodes,
    edges = result$edges,
    roots = id,
    path = if (is.null(predicate)) character() else rep(predicate, hops),
    predicate = predicate,
    direction = direction,
    hops = hops,
    projection = projection,
    truncated = result$truncated,
    limits = limits,
    store_schema_digest = store_schema_digest(store),
    request_kind = "neighbors"
  )
}

#' Traverse a bounded predicate path
#'
#' `kg_traverse()` follows a manifest-safe sequence of one or two predicates.
#' It uses generated joins for each hop and never runs recursive or unbounded
#' SQL.
#'
#' @param store An initialized `kg_store`.
#' @param from One projected graph node identifier.
#' @param via One or two exact predicates in traversal order.
#' @param direction One of `"out"`, `"in"`, or `"both"`.
#' @param max_hops Maximum predicates from `via` to follow, up to two.
#' @param max_nodes Maximum collected nodes, up to 500.
#' @param max_edges Maximum collected edges, up to 2,000.
#' @param projection One of `"combined"`, `"semantic"`, or `"provenance"`.
#'
#' @return A collected `kg_subgraph` with path and limit metadata.
#' @export
kg_traverse <- function(
  store,
  from,
  via,
  direction = "out",
  max_hops = length(via),
  max_nodes = 500,
  max_edges = 2000,
  projection = "combined"
) {
  validate_retrieval_store(store)
  from <- validate_scalar_text(from, "from", condition = abort_reference_error)
  via <- validate_graph_path(via)
  direction <- rlang::arg_match(direction, c("out", "in", "both"))
  projection <- rlang::arg_match(
    projection,
    c("combined", "semantic", "provenance")
  )
  max_hops <- validate_result_limit(
    max_hops,
    "max_hops",
    hard_limit = graph_result_limits$hops
  )
  if (max_hops > length(via)) {
    abort_limit_error(
      "`max_hops` may not exceed the number of predicates in `via`.",
      argument = "max_hops",
      requested_limit = max_hops,
      hard_limit = length(via)
    )
  }
  limits <- validate_graph_limits(max_nodes, max_edges)
  graph_assert_node_ids(store, from, field = "from")
  traversed_path <- via[seq_len(max_hops)]

  result <- graph_expand(
    store = store,
    roots = from,
    predicates = as.list(traversed_path),
    direction = direction,
    projection = projection,
    limits = limits
  )
  new_kg_subgraph(
    nodes = result$nodes,
    edges = result$edges,
    roots = from,
    path = traversed_path,
    predicate = NULL,
    direction = direction,
    hops = max_hops,
    projection = projection,
    truncated = result$truncated,
    limits = limits,
    store_schema_digest = store_schema_digest(store),
    request_kind = "traverse"
  )
}

#' Collect a bounded induced subgraph
#'
#' `kg_subgraph()` explicitly collects projected nodes and every projected edge
#' whose endpoints are both in the retained identifier set.
#'
#' @param store An initialized `kg_store`.
#' @param ids Projected graph node identifiers.
#' @param projection One of `"combined"`, `"semantic"`, or `"provenance"`.
#' @param max_nodes Maximum collected nodes, up to 500.
#' @param max_edges Maximum collected edges, up to 2,000.
#'
#' @return A collected `kg_subgraph` with limit and truncation metadata.
#' @export
kg_subgraph <- function(
  store,
  ids,
  projection = "combined",
  max_nodes = 500,
  max_edges = 2000
) {
  validate_retrieval_store(store)
  ids <- validate_graph_ids(ids)
  projection <- rlang::arg_match(
    projection,
    c("combined", "semantic", "provenance")
  )
  limits <- validate_graph_limits(max_nodes, max_edges)
  requested <- unique(ids)
  retained <- sort(requested)
  truncated <- length(retained) > limits$max_nodes
  if (truncated) {
    retained <- retained[seq_len(limits$max_nodes)]
  }
  nodes <- graph_collect_nodes(store, retained)
  graph_assert_collected_nodes(
    nodes,
    retained,
    field = "ids",
    rule = "graph_node_exists"
  )
  edges <- graph_collect_induced_edges(
    store,
    retained,
    projection,
    limits$max_edges
  )
  truncated <- truncated || isTRUE(attr(edges, "truncated"))
  attr(edges, "truncated") <- NULL
  graph_assert_edge_endpoints(store, edges)

  new_kg_subgraph(
    nodes = nodes,
    edges = edges,
    roots = requested,
    path = character(),
    predicate = NULL,
    direction = NA_character_,
    hops = 0L,
    projection = projection,
    truncated = truncated,
    limits = limits,
    store_schema_digest = store_schema_digest(store),
    request_kind = "subgraph"
  )
}

validate_graph_path <- function(via) {
  valid <- is.character(via) &&
    length(via) %in% c(1L, 2L) &&
    !anyNA(via) &&
    all(nzchar(via))
  if (!valid) {
    abort_limit_error(
      "`via` must contain one or two non-empty predicates.",
      argument = "via",
      requested_limit = length(via),
      hard_limit = graph_result_limits$hops
    )
  }
  via
}

validate_graph_ids <- function(ids) {
  valid <- is.character(ids) &&
    length(ids) > 0L &&
    !anyNA(ids) &&
    all(nzchar(ids))
  if (!valid) {
    abort_validation_error(
      "`ids` must contain one or more non-empty graph node identifiers.",
      field = "ids",
      rule = "graph_node_identifiers",
      observed_value = ids
    )
  }
  ids
}

validate_graph_limits <- function(max_nodes, max_edges) {
  list(
    max_nodes = validate_result_limit(
      max_nodes,
      "max_nodes",
      hard_limit = graph_result_limits$nodes
    ),
    max_edges = validate_result_limit(
      max_edges,
      "max_edges",
      hard_limit = graph_result_limits$edges
    )
  )
}

graph_expand <- function(
  store,
  roots,
  predicates,
  direction,
  projection,
  limits
) {
  visited <- sort(unique(roots))
  frontier <- visited
  edges <- graph_empty_edge_data()
  truncated <- FALSE

  for (predicate in predicates) {
    if (length(frontier) == 0L) {
      break
    }
    remaining_edges <- limits$max_edges - nrow(edges)
    candidates <- graph_collect_frontier_edges(
      store = store,
      frontier = frontier,
      predicate = predicate,
      direction = direction,
      projection = projection,
      limit = remaining_edges
    )
    truncated <- truncated || isTRUE(attr(candidates, "truncated"))
    attr(candidates, "truncated") <- NULL
    if (nrow(candidates) == 0L) {
      frontier <- character()
      next
    }
    graph_assert_edge_endpoints(store, candidates)

    existing_keys <- graph_edge_keys(edges)
    candidates <- candidates[
      !graph_edge_keys(candidates) %in% existing_keys,
      ,
      drop = FALSE
    ]
    candidate_nodes <- sort(unique(c(
      as.character(candidates$subject),
      as.character(candidates$object)
    )))
    new_nodes <- setdiff(candidate_nodes, visited)
    remaining_nodes <- limits$max_nodes - length(visited)
    if (length(new_nodes) > remaining_nodes) {
      truncated <- TRUE
      new_nodes <- if (remaining_nodes > 0L) {
        new_nodes[seq_len(remaining_nodes)]
      } else {
        character()
      }
    }
    retained_nodes <- c(visited, new_nodes)
    retained_edges <- candidates[
      candidates$subject %in%
        retained_nodes &
        candidates$object %in% retained_nodes,
      ,
      drop = FALSE
    ]
    if (nrow(retained_edges) < nrow(candidates)) {
      truncated <- TRUE
    }
    edges <- dplyr::bind_rows(edges, retained_edges)
    edges <- graph_order_edges(edges)
    visited <- sort(unique(retained_nodes))
    frontier <- sort(unique(new_nodes))
  }

  nodes <- graph_collect_nodes(store, visited)
  graph_assert_collected_nodes(
    nodes,
    visited,
    field = "graph",
    rule = "graph_endpoint_exists"
  )
  list(
    nodes = nodes,
    edges = graph_order_edges(edges),
    truncated = truncated
  )
}

graph_collect_frontier_edges <- function(
  store,
  frontier,
  predicate,
  direction,
  projection,
  limit
) {
  connection <- store$connection
  placeholders <- paste(rep("?", length(frontier)), collapse = ", ")
  if (identical(direction, "out")) {
    incidence <- paste0("subject IN (", placeholders, ")")
    params <- as.list(frontier)
  } else if (identical(direction, "in")) {
    incidence <- paste0("object IN (", placeholders, ")")
    params <- as.list(frontier)
  } else {
    incidence <- paste0(
      "(subject IN (",
      placeholders,
      ") OR object IN (",
      placeholders,
      "))"
    )
    params <- c(as.list(frontier), as.list(frontier))
  }
  predicate_sql <- ""
  if (!is.null(predicate)) {
    predicate_sql <- " AND predicate = ?"
    params <- c(params, list(predicate))
  }
  sql <- paste0(
    "SELECT edge_id, subject, predicate, object, edge_class, source_table, ",
    "created_at FROM (",
    graph_normalized_edges_sql(connection, projection),
    ") AS graft_graph_edges WHERE ",
    incidence,
    predicate_sql,
    graph_edge_order_sql(),
    " LIMIT ",
    limit + 1L
  )
  rows <- with_duckdb_error(
    "graph_neighbors",
    DBI::dbGetQuery(connection, sql, params = params)
  )
  truncated <- nrow(rows) > limit
  if (truncated) {
    rows <- rows[seq_len(limit), , drop = FALSE]
  }
  rownames(rows) <- NULL
  attr(rows, "truncated") <- truncated
  rows
}

graph_collect_induced_edges <- function(
  store,
  ids,
  projection,
  limit
) {
  if (length(ids) == 0L) {
    rows <- graph_empty_edge_data()
    attr(rows, "truncated") <- FALSE
    return(rows)
  }
  placeholders <- paste(rep("?", length(ids)), collapse = ", ")
  sql <- paste0(
    "SELECT edge_id, subject, predicate, object, edge_class, source_table, ",
    "created_at FROM (",
    graph_normalized_edges_sql(store$connection, projection),
    ") AS graft_graph_edges WHERE subject IN (",
    placeholders,
    ") AND object IN (",
    placeholders,
    ")",
    graph_edge_order_sql(),
    " LIMIT ",
    limit + 1L
  )
  rows <- with_duckdb_error(
    "graph_subgraph",
    DBI::dbGetQuery(
      store$connection,
      sql,
      params = c(as.list(ids), as.list(ids))
    )
  )
  truncated <- nrow(rows) > limit
  if (truncated) {
    rows <- rows[seq_len(limit), , drop = FALSE]
  }
  rownames(rows) <- NULL
  attr(rows, "truncated") <- truncated
  rows
}

graph_normalized_edges_sql <- function(connection, projection) {
  if (identical(projection, "semantic")) {
    return(paste0(
      "SELECT edge_id, subject, predicate, object, edge_class, source_table, ",
      "created_at FROM ",
      quote_identifier(connection, "_graft_edges")
    ))
  }
  provenance <- paste0(
    "SELECT edge_id, subject, predicate, object, ",
    "'provenance' AS edge_class, source_table, ",
    "CAST(NULL AS TIMESTAMP) AS created_at FROM ",
    quote_identifier(connection, "_graft_provenance_edges")
  )
  if (identical(projection, "provenance")) {
    return(provenance)
  }
  graph_combined_edges_sql(connection)
}

graph_edge_order_sql <- function() {
  paste0(
    " ORDER BY subject ASC, predicate ASC, object ASC, ",
    "edge_class ASC, edge_id ASC, source_table ASC"
  )
}

graph_order_edges <- function(edges) {
  if (nrow(edges) == 0L) {
    return(edges)
  }
  edges <- edges[
    order(
      edges$subject,
      edges$predicate,
      edges$object,
      edges$edge_class,
      edges$edge_id,
      edges$source_table
    ),
    ,
    drop = FALSE
  ]
  rownames(edges) <- NULL
  edges
}

graph_edge_keys <- function(edges) {
  if (nrow(edges) == 0L) {
    return(character())
  }
  paste(
    edges$edge_id,
    edges$subject,
    edges$predicate,
    edges$object,
    edges$edge_class,
    edges$source_table,
    sep = "\r"
  )
}

graph_collect_nodes <- function(store, ids) {
  if (length(ids) == 0L) {
    return(graph_empty_node_data())
  }
  placeholders <- paste(rep("?", length(ids)), collapse = ", ")
  sql <- paste0(
    "SELECT id, class, label, role, statement_shape, type_uri, created_at FROM ",
    quote_identifier(store$connection, "_graft_nodes"),
    " WHERE id IN (",
    placeholders,
    ") ORDER BY id ASC, class ASC"
  )
  rows <- with_duckdb_error(
    "graph_nodes",
    DBI::dbGetQuery(
      store$connection,
      sql,
      params = as.list(ids)
    )
  )
  rownames(rows) <- NULL
  rows
}

graph_assert_node_ids <- function(store, ids, field) {
  rows <- graph_collect_nodes(store, unique(ids))
  graph_assert_collected_nodes(
    rows,
    unique(ids),
    field = field,
    rule = "graph_node_exists"
  )
  invisible(rows)
}

graph_assert_collected_nodes <- function(rows, ids, field, rule) {
  counts <- table(factor(rows$id, levels = ids))
  missing <- names(counts)[counts == 0L]
  if (length(missing) > 0L) {
    abort_reference_error(
      paste0(
        "Graph projection refers to missing node record(s): ",
        paste(missing, collapse = ", "),
        "."
      ),
      record_id = missing[[1L]],
      field = field,
      rule = rule,
      observed_value = missing,
      missing_record_ids = missing
    )
  }
  ambiguous <- names(counts)[counts > 1L]
  if (length(ambiguous) > 0L) {
    abort_identity_error(
      paste0(
        "Graph node identifier is ambiguous across projected classes: ",
        paste(ambiguous, collapse = ", "),
        "."
      ),
      record_id = ambiguous[[1L]],
      field = field,
      rule = "unique_graph_node",
      observed_value = ambiguous,
      ambiguous_record_ids = ambiguous
    )
  }
  invisible(rows)
}

graph_assert_edge_endpoints <- function(store, edges) {
  if (nrow(edges) == 0L) {
    return(invisible(edges))
  }
  endpoints <- sort(unique(c(
    as.character(edges$subject),
    as.character(edges$object)
  )))
  rows <- graph_collect_nodes(store, endpoints)
  graph_assert_collected_nodes(
    rows,
    endpoints,
    field = "graph_edge",
    rule = "graph_endpoint_exists"
  )
  invisible(edges)
}

graph_empty_node_data <- function() {
  data.frame(
    id = character(),
    class = character(),
    label = character(),
    role = character(),
    statement_shape = character(),
    type_uri = character(),
    created_at = as.POSIXct(
      numeric(),
      origin = "1970-01-01",
      tz = "UTC"
    ),
    stringsAsFactors = FALSE
  )
}

graph_empty_edge_data <- function() {
  data.frame(
    edge_id = character(),
    subject = character(),
    predicate = character(),
    object = character(),
    edge_class = character(),
    source_table = character(),
    created_at = as.POSIXct(
      numeric(),
      origin = "1970-01-01",
      tz = "UTC"
    ),
    stringsAsFactors = FALSE
  )
}
