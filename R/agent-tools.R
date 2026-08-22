#' Create bounded read-only tools for a Graft store or view
#'
#' `graft_tools()` returns [ellmer::tool()] definitions that delegate only
#' to Graft's public bounded retrieval operations. The tools do not expose SQL,
#' filesystem, network, connection, or mutation arguments.
#' When the store has accepted measures, a fifth `graft_measure` tool
#' evaluates them by name through [graft_measure()]; it is omitted when no
#' measures are accepted.
#' When given a `GraftView`, all tools remain pinned to its immutable
#' snapshot boundary and the live-store integrity diagnostic is unavailable.
#'
#' Every tool returns `result` plus explicit `truncated`, `limit`, and
#' `store_schema_digest` metadata; `graft_measure` results add `measure_id`
#' and `revision_id`.
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
        result <- graft_find(
          store,
          query = query,
          class = class,
          limit = limit
        )
        graft_tool_bounded_result(result, limit)
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
        result <- graft_get(
          store,
          id = id,
          include = include,
          limits = limits
        )
        graft_tool_result(
          result,
          truncated = any(unlist(result$truncated, use.names = FALSE)),
          limit = result$limits,
          store_schema_digest = result$store_schema_digest
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
        result <- graft_query(
          store,
          operation = operation,
          request = request,
          limit = limit
        )
        graft_tool_bounded_result(result, limit)
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
        result <- graft_history(
          store,
          id = id,
          as_of = as_of,
          limit = limit
        )
        graft_tool_bounded_result(result, limit)
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
  measures <- graft_measures(store)
  if (nrow(measures) > 0L) {
    tools$graft_measure <- graft_measure_tool(store, measures, annotations)
  }
  tools
}

graft_measure_tool <- function(store, measures, annotations) {
  ellmer::tool(
    function(name, arguments = list(), by = NULL) {
      result <- graft_measure(
        store,
        name = name,
        arguments = arguments,
        by = by
      )
      wrapped <- graft_tool_bounded_result(
        result,
        graft_retrieval_limits$measure_rows
      )
      wrapped$measure_id <- attr(result, "measure_id")
      wrapped$revision_id <- attr(result, "revision_id")
      wrapped
    },
    name = "graft_measure",
    description = paste(
      "Evaluate one accepted, governed measure over accepted state.",
      "Arguments bind to declared parameters as equality filters and",
      "`by` groups by declared dimensions. Results are deterministic",
      "and bounded; no SQL is accepted."
    ),
    arguments = list(
      name = ellmer::type_enum(
        sort(measures$name),
        "Name of one accepted measure."
      ),
      arguments = graft_tool_json_type(
        list(type = "object", additionalProperties = TRUE),
        required = FALSE
      ),
      by = ellmer::type_array(
        ellmer::type_string("A declared dimension column."),
        "Declared dimensions to group by.",
        required = FALSE
      )
    ),
    annotations = annotations
  )
}

check_graft_tools_dependency <- function() {
  rlang::check_installed(
    "ellmer",
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

graft_tool_bounded_result <- function(result, fallback_limit) {
  if (is.data.frame(result)) {
    limit <- attr(result, "limit")
    if (is.null(limit)) {
      limit <- fallback_limit
    }
    return(graft_tool_result(
      result,
      truncated = isTRUE(attr(result, "truncated")),
      limit = limit,
      store_schema_digest = attr(result, "store_schema_digest")
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
    store_schema_digest = result$store_schema_digest
  )
}

graft_tool_result <- function(result, truncated, limit, store_schema_digest) {
  list(
    result = if (is.list(result) && !is.data.frame(result)) {
      unclass(result)
    } else {
      result
    },
    truncated = isTRUE(truncated),
    limit = limit,
    store_schema_digest = store_schema_digest
  )
}
