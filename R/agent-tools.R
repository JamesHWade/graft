#' Create bounded read-only tools for a Graft store or view
#'
#' `graft_tools()` returns [ellmer::tool()] definitions that delegate only
#' to Graft's public bounded retrieval operations. The tools do not expose SQL,
#' filesystem, network, connection, or mutation arguments.
#' When the store has accepted definitions, `graft_definitions` exposes their
#' bounded catalog and one `graft_calculate` tool composes them through
#' [graft_calculate()]. Both are omitted when no definitions are accepted.
#' When given a `GraftView`, all tools remain pinned to its immutable
#' snapshot boundary and the live-store integrity diagnostic is unavailable.
#'
#' Every tool returns `result`, `truncated`, `limit`, and one canonical nested
#' `receipt`. The receipt identifies the store, exact accepted boundary, and
#' structural and build schema digests. Calculation receipts also identify the
#' complete accepted definition closure. Live-store tools pin a fresh boundary
#' for each invocation; tools created from a `GraftView` retain its snapshot
#' boundary.
#'
#' @param store An initialized `GraftStore` or immutable `GraftView`.
#'
#' @return A named list of `ellmer::ToolDef` objects.
#' @seealso `vignette("agents", package = "graft")` for pinning an accepted
#'   boundary, registering the tools with a chat, and accepting
#'   agent-authored proposals.
#' @export
graft_tools <- function(store) {
  check_graft_tools_dependency()
  read_store <- as_graft_read_store_internal(store, "store")
  annotations <- graft_tool_annotations()

  tools <- list(
    graft_find = ellmer::tool(
      function(query, class = NULL, limit = 20) {
        context <- graft_tool_context(store)
        result <- graft_find(
          context$store,
          query = query,
          class = class,
          limit = limit
        )
        graft_tool_bounded_result(result, limit, context$receipt)
      },
      name = "graft_find",
      description = paste(
        "Search manifest-declared public fields.",
        "Results are deterministic and bounded."
      ),
      arguments = list(
        query = ellmer::type_string("Non-empty search text."),
        class = ellmer::type_string(
          "Optional concrete class restriction.",
          required = FALSE
        ),
        limit = graft_tool_integer(
          "Maximum result rows.",
          minimum = 1L,
          maximum = graft_retrieval_limits$find,
          required = FALSE
        )
      ),
      annotations = annotations
    ),
    graft_get = ellmer::tool(
      function(
        id,
        include = c("identifiers", "claims", "evidence"),
        limits = list(
          identifiers = 100L,
          claims = 50L,
          evidence = 100L
        )
      ) {
        context <- graft_tool_context(store)
        result <- graft_get(
          context$store,
          id = id,
          include = include,
          limits = limits
        )
        graft_tool_result(
          result,
          truncated = any(unlist(result$truncated, use.names = FALSE)),
          limit = result$limits,
          receipt = context$receipt
        )
      },
      name = "graft_get",
      description = paste(
        "Retrieve one current public record with optional identifiers,",
        "claims, and evidence."
      ),
      arguments = list(
        id = ellmer::type_string("Internal record identifier."),
        include = ellmer::type_array(
          ellmer::type_enum(c("identifiers", "claims", "evidence")),
          description = "Related results to include.",
          required = FALSE
        ),
        limits = ellmer::type_object(
          .description = "Optional named related-result limits.",
          identifiers = graft_tool_integer(
            "Maximum identifier rows.",
            minimum = 1L,
            maximum = graft_retrieval_limits$identifiers,
            required = FALSE
          ),
          claims = graft_tool_integer(
            "Maximum claim rows.",
            minimum = 1L,
            maximum = graft_retrieval_limits$get_claims,
            required = FALSE
          ),
          evidence = graft_tool_integer(
            "Maximum evidence rows.",
            minimum = 1L,
            maximum = graft_retrieval_limits$get_evidence,
            required = FALSE
          ),
          .required = FALSE
        )
      ),
      annotations = annotations
    ),
    graft_query = ellmer::tool(
      function(operation, request = list(), limit = 100) {
        if (identical(operation, "integrity") && !is_graft_view(store)) {
          return(graft_tool_integrity_result(store, request, limit))
        }
        context <- graft_tool_context(store)
        result <- graft_query(
          context$store,
          operation = operation,
          request = request,
          limit = limit
        )
        graft_tool_bounded_result(result, limit, context$receipt)
      },
      name = "graft_query",
      description = paste(
        "Run one bounded advanced retrieval operation.",
        "The request shape is validated for the selected operation."
      ),
      arguments = list(
        operation = ellmer::type_enum(graft_tool_query_operations(read_store)),
        request = graft_tool_request_type(),
        limit = graft_tool_integer(
          "Maximum rows for tabular operations.",
          minimum = 1L,
          maximum = graft_retrieval_limits$unresolved,
          required = FALSE
        )
      ),
      annotations = annotations
    ),
    graft_history = ellmer::tool(
      function(id, as_of = NULL, limit = 100) {
        context <- graft_tool_context(store)
        result <- graft_history(
          context$store,
          id = id,
          as_of = as_of,
          limit = limit
        )
        receipt <- graft_tool_history_receipt(
          context$receipt,
          result,
          as_of,
          context$store
        )
        graft_tool_bounded_result(result, limit, receipt)
      },
      name = "graft_history",
      description = paste(
        "Retrieve newest-first accepted revision history.",
        "An optional `as_of` value selects a committed batch boundary."
      ),
      arguments = list(
        id = ellmer::type_string("Internal record identifier."),
        as_of = ellmer::type_string(
          "Optional committed batch identifier.",
          required = FALSE
        ),
        limit = graft_tool_integer(
          "Maximum history rows.",
          minimum = 1L,
          maximum = graft_retrieval_limits$history,
          required = FALSE
        )
      ),
      annotations = annotations
    )
  )
  definitions <- graft_definitions(store)
  if (nrow(definitions) > 0L) {
    tools$graft_definitions <- graft_definitions_tool(store, annotations)
    tools$graft_calculate <- graft_calculate_tool(store, annotations)
  }
  tools
}

graft_definitions_tool <- function(store, annotations) {
  ellmer::tool(
    function(target = NULL) {
      context <- graft_tool_context(store)
      result <- graft_definitions(
        context$store,
        target = target
      )
      graft_tool_bounded_result(
        result,
        graft_retrieval_limits$definitions,
        context$receipt
      )
    },
    name = "graft_definitions",
    description = paste(
      "List accepted metric, filter, and derived definitions plus their",
      "public targets, dependencies, and eligible columns."
    ),
    arguments = list(
      target = ellmer::type_string(
        "Optional public-table restriction.",
        required = FALSE
      )
    ),
    annotations = annotations
  )
}

graft_calculate_tool <- function(store, annotations) {
  ellmer::tool(
    function(metrics, dimensions = NULL, filters = NULL, where = NULL) {
      context <- graft_tool_context(store)
      result <- graft_calculate(
        context$store,
        metrics = metrics,
        dimensions = dimensions,
        filters = filters,
        where = where
      )
      definitions <- attr(result, "definitions")
      context$receipt$definitions <- lapply(
        seq_len(nrow(definitions)),
        function(index) {
          list(
            id = definitions$id[[index]],
            revision_id = definitions$revision_id[[index]],
            kind = definitions$kind[[index]]
          )
        }
      )
      graft_tool_result(
        result,
        truncated = FALSE,
        limit = graft_retrieval_limits$calculation_rows,
        receipt = context$receipt
      )
    },
    name = "graft_calculate",
    description = paste(
      "Compose accepted same-table metrics, dimensions, filters, and simple",
      "predicates over one exact accepted boundary. No SQL is accepted."
    ),
    arguments = list(
      metrics = ellmer::type_array(
        ellmer::type_string("An accepted metric name."),
        "One or more accepted metrics."
      ),
      dimensions = ellmer::type_array(
        ellmer::type_string("A public column or accepted derived definition."),
        "Optional grouping dimensions.",
        required = FALSE
      ),
      filters = ellmer::type_array(
        ellmer::type_string("An accepted filter definition."),
        "Optional accepted filters.",
        required = FALSE
      ),
      where = graft_tool_where_type(
        required = FALSE
      )
    ),
    annotations = annotations
  )
}

graft_tool_where_type <- function(required = FALSE) {
  graft_tool_json_type(
    list(
      type = "array",
      items = list(
        type = "object",
        additionalProperties = FALSE,
        properties = list(
          column = list(type = "string"),
          op = list(
            type = "string",
            enum = c("=", "!=", "<", "<=", ">", ">=")
          ),
          value = list(type = "string")
        ),
        required = c("column", "op", "value")
      )
    ),
    required = required
  )
}

check_graft_tools_dependency <- function() {
  rlang::check_installed(
    "ellmer",
    version = "0.5.0",
    reason = "to create bounded tools with `graft_tools()`"
  )
}

graft_tool_annotations <- function() {
  ellmer::tool_annotations(
    read_only_hint = TRUE,
    open_world_hint = FALSE,
    idempotent_hint = TRUE,
    destructive_hint = FALSE
  )
}

graft_tool_integer <- function(description, minimum, maximum, required) {
  type <- ellmer::type_from_schema(
    text = as.character(jsonlite::toJSON(
      list(
        type = "integer",
        minimum = as.integer(minimum),
        maximum = as.integer(maximum)
      ),
      auto_unbox = TRUE
    ))
  )
  type@description <- description
  type@required <- required
  type
}

graft_tool_query_operations <- function(store = NULL) {
  operations <- c(
    "lookup",
    "identifiers",
    "claims",
    "evidence",
    "neighbors",
    "traverse",
    "unresolved",
    "integrity"
  )
  if (!is.null(store) && is_graft_snapshot_backend(store)) {
    operations <- setdiff(operations, "integrity")
  }
  operations
}

graft_tool_request_type <- function() {
  graft_tool_json_type(
    list(
      type = "object",
      additionalProperties = FALSE,
      properties = list(
        id = list(type = "string"),
        namespace = list(type = "string"),
        value = list(type = "string"),
        class = list(type = "string"),
        predicate = list(type = "string"),
        include_superseded = list(type = "boolean"),
        statement_id = list(type = "string"),
        source_id = list(type = "string"),
        support_type = list(type = "string"),
        direction = list(type = "string", enum = c("both", "out", "in")),
        hops = list(type = "integer", minimum = 1L, maximum = 2L),
        projection = list(
          type = "string",
          enum = c("semantic", "provenance", "combined")
        ),
        max_nodes = list(type = "integer", minimum = 1L, maximum = 500L),
        max_edges = list(type = "integer", minimum = 1L, maximum = 2000L),
        from = list(type = "string"),
        via = list(type = "array", items = list(type = "string")),
        max_hops = list(type = "integer", minimum = 1L, maximum = 2L),
        projections = list(type = "boolean")
      )
    ),
    required = FALSE
  )
}

graft_tool_json_type <- function(schema, required = TRUE) {
  type <- ellmer::type_from_schema(
    text = as.character(jsonlite::toJSON(
      schema,
      auto_unbox = TRUE,
      null = "null"
    ))
  )
  type@required <- required
  type
}

graft_tool_bounded_result <- function(result, fallback_limit, receipt) {
  if (is.data.frame(result)) {
    limit <- attr(result, "limit")
    if (is.null(limit)) {
      limit <- fallback_limit
    }
    return(graft_tool_result(
      result,
      truncated = isTRUE(attr(result, "truncated")),
      limit = limit,
      receipt = receipt
    ))
  }
  truncated <- result$truncated
  if (is.list(truncated)) {
    truncated <- any(unlist(truncated, use.names = FALSE))
  }
  limit <- result$limits
  if (is.null(limit)) {
    limit <- fallback_limit
  }
  graft_tool_result(
    result,
    truncated = isTRUE(truncated),
    limit = limit,
    receipt = receipt
  )
}

graft_tool_result <- function(result, truncated, limit, receipt) {
  list(
    result = if (is.list(result) && !is.data.frame(result)) {
      unclass(result)
    } else {
      result
    },
    truncated = isTRUE(truncated),
    limit = limit,
    receipt = receipt
  )
}

graft_tool_context <- function(store) {
  if (is_graft_view(store)) {
    return(list(
      store = store,
      receipt = graft_tool_receipt(store, "snapshot")
    ))
  }
  snapshot <- graft_snapshot(store)
  view <- graft_at(store, snapshot)
  list(
    store = view,
    receipt = graft_tool_receipt(view, "live")
  )
}

graft_tool_integrity_result <- function(store, request, limit) {
  backend <- as_graft_store_internal(store, "store")
  DBI::dbWithTransaction(backend$connection, {
    snapshot <- graft_snapshot(store)
    view <- graft_at(store, snapshot)
    result <- graft_query(
      store,
      operation = "integrity",
      request = request,
      limit = limit
    )
    graft_tool_bounded_result(
      result,
      limit,
      graft_tool_receipt(view, "live")
    )
  })
}

graft_tool_history_receipt <- function(receipt, result, as_of, store) {
  if (is.null(as_of)) {
    return(receipt)
  }
  receipt$boundary <- graft_tool_boundary(
    "history",
    attr(result, "as_of_batch_id"),
    attr(result, "as_of_commit_order")
  )
  receipt$schema <- graft_tool_history_schema(
    store,
    receipt$boundary$commit_order
  )
  receipt
}

graft_tool_receipt <- function(view, kind) {
  state <- graft_view_state(view)
  snapshot <- state$snapshot
  schema <- state$schema
  list(
    store = list(id = snapshot@store_id),
    boundary = graft_tool_boundary(
      kind,
      snapshot@batch_id,
      snapshot@commit_order,
      snapshot@snapshot_id
    ),
    schema = graft_tool_schema(
      schema,
      snapshot@schema_build_digest
    )
  )
}

graft_tool_boundary <- function(
  kind,
  batch_id,
  commit_order,
  snapshot_id = NULL
) {
  if (
    !is_nonempty_string(kind) ||
      !kind %in%
        c(
          "live",
          "snapshot",
          "history"
        )
  ) {
    abort_backend_error(
      "An internal tool receipt has an invalid boundary kind.",
      operation = "graft_tools",
      boundary_kind = kind
    )
  }
  if (length(batch_id) == 1L && is.na(batch_id)) {
    batch_id <- NULL
  }
  if (!is.null(batch_id) && !is_nonempty_string(batch_id)) {
    abort_backend_error(
      "An internal tool receipt has an invalid batch identifier.",
      operation = "graft_tools",
      batch_id = batch_id
    )
  }
  if (
    !is.numeric(commit_order) ||
      length(commit_order) != 1L ||
      is.na(commit_order) ||
      !is.finite(commit_order) ||
      commit_order < 0 ||
      commit_order != floor(commit_order) ||
      commit_order >= 2^53
  ) {
    abort_backend_error(
      "An internal tool receipt has an invalid commit order.",
      operation = "graft_tools",
      commit_order = commit_order
    )
  }
  boundary <- list(
    kind = kind,
    batch_id = batch_id,
    commit_order = commit_order
  )
  if (identical(kind, "snapshot")) {
    if (!is_nonempty_string(snapshot_id)) {
      abort_backend_error(
        "A snapshot tool receipt requires a snapshot identifier.",
        operation = "graft_tools",
        snapshot_id = snapshot_id
      )
    }
    boundary <- c(boundary, list(snapshot_id = snapshot_id))
  }
  boundary
}

graft_tool_history_schema <- function(store, commit_order) {
  store <- as_graft_read_store_internal(store, "store")
  row <- with_duckdb_error(
    "graft_tool_history_receipt",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT schema_build_digest FROM ",
        quote_identifier(store$connection, "_graft_batches"),
        " WHERE status = 'committed' AND commit_order = ?"
      ),
      params = list(commit_order)
    )
  )
  if (nrow(row) != 1L) {
    abort_backend_error(
      "A history tool receipt requires one committed boundary schema.",
      operation = "graft_tool_history_receipt",
      commit_order = commit_order,
      schema_count = nrow(row)
    )
  }
  build_digest <- scalar_character(row$schema_build_digest)
  schema <- historical_schemas(store, build_digest)[[build_digest]]
  graft_tool_schema(schema, build_digest)
}

graft_tool_schema <- function(schema, build_digest) {
  list(
    structural_digest = scalar_character(
      schema$manifest$fingerprints$structural_digest
    ),
    build_digest = build_digest
  )
}
