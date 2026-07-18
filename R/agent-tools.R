#' Create bounded ellmer tools for a graft store
#'
#' `kg_tools()` creates six read-only [ellmer::tool()] definitions that capture
#' one initialized store. The tools expose only graft's bounded retrieval
#' functions; they do not accept SQL, file paths, URLs, or network options.
#'
#' Every tool returns the native graft result in `result` plus explicit
#' `truncated`, `limit`, and `store_schema_digest` fields.
#'
#' @param store An initialized `kg_store`.
#'
#' @return A named list of six `ellmer::ToolDef` objects.
#' @export
kg_tools <- function(store) {
  rlang::check_installed(
    "ellmer",
    reason = "to create bounded graft tools with `kg_tools()`"
  )
  validate_retrieval_store(store)
  annotations <- agent_tool_annotations()

  list(
    kg_describe = ellmer::tool(
      function(class = NULL, token_budget = 1500) {
        result <- kg_context(
          store,
          class = class,
          token_budget = token_budget
        )
        agent_tool_result(
          result,
          truncated = result$truncated,
          limit = result$token_budget,
          store_schema_digest = result$store_schema_digest
        )
      },
      name = "kg_describe",
      description = paste(
        "Describe the active manifest-derived knowledge contract.",
        "Sensitive fields are omitted and output is token bounded."
      ),
      arguments = list(
        class = ellmer::type_string(
          "Optional concrete class to describe.",
          required = FALSE
        ),
        token_budget = agent_tool_integer(
          "Maximum approximate output tokens.",
          minimum = 1L,
          maximum = graft_retrieval_limits$context_tokens,
          required = FALSE
        )
      ),
      annotations = annotations
    ),
    kg_find = ellmer::tool(
      function(query, class = NULL, limit = 20) {
        result <- kg_find(
          store,
          query = query,
          class = class,
          limit = limit
        )
        agent_tool_bounded_result(result)
      },
      name = "kg_find",
      description = paste(
        "Search manifest-declared label and text fields.",
        "Results are deterministic and bounded."
      ),
      arguments = list(
        query = ellmer::type_string("Non-empty search text."),
        class = ellmer::type_string(
          "Optional concrete class restriction.",
          required = FALSE
        ),
        limit = agent_tool_integer(
          "Maximum result rows.",
          minimum = 1L,
          maximum = graft_retrieval_limits$find,
          required = FALSE
        )
      ),
      annotations = annotations
    ),
    kg_get = ellmer::tool(
      function(
        id,
        include = c("identifiers", "claims", "evidence"),
        limits = list(
          identifiers = 100L,
          claims = 50L,
          evidence = 100L
        )
      ) {
        result <- kg_get(
          store,
          id = id,
          include = include,
          limits = limits
        )
        agent_tool_result(
          result,
          truncated = any(
            unlist(result$truncated, use.names = FALSE)
          ),
          limit = result$limits,
          store_schema_digest = result$store_schema_digest
        )
      },
      name = "kg_get",
      description = paste(
        "Hydrate exactly one public record with optional identifiers,",
        "claims, and evidence."
      ),
      arguments = list(
        id = ellmer::type_string("Internal record identifier."),
        include = ellmer::type_array(
          ellmer::type_enum(c("identifiers", "claims", "evidence")),
          description = "Related data to include.",
          required = FALSE
        ),
        limits = ellmer::type_object(
          .description = "Optional named related-record limits.",
          identifiers = agent_tool_integer(
            "Maximum identifier rows.",
            minimum = 1L,
            maximum = graft_retrieval_limits$identifiers,
            required = FALSE
          ),
          claims = agent_tool_integer(
            "Maximum claim rows.",
            minimum = 1L,
            maximum = graft_retrieval_limits$get_claims,
            required = FALSE
          ),
          evidence = agent_tool_integer(
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
    kg_neighbors = ellmer::tool(
      function(
        id,
        predicate = NULL,
        direction = "both",
        hops = 1,
        projection = "semantic",
        max_nodes = 500,
        max_edges = 2000
      ) {
        result <- kg_neighbors(
          store,
          id = id,
          predicate = predicate,
          direction = direction,
          hops = hops,
          projection = projection,
          max_nodes = max_nodes,
          max_edges = max_edges
        )
        agent_tool_result(
          result,
          truncated = result$truncated,
          limit = list(
            nodes = result$limits$max_nodes,
            edges = result$limits$max_edges,
            hops = result$hops
          ),
          store_schema_digest = result$store_schema_digest
        )
      },
      name = "kg_neighbors",
      description = paste(
        "Collect a deterministic one-hop or two-hop graph neighborhood.",
        "Only generated semantic and provenance projections are available."
      ),
      arguments = list(
        id = ellmer::type_string("Projected graph node identifier."),
        predicate = ellmer::type_string(
          "Optional exact predicate restriction.",
          required = FALSE
        ),
        direction = ellmer::type_enum(
          c("both", "out", "in"),
          "Edge direction.",
          required = FALSE
        ),
        hops = agent_tool_integer(
          "Breadth-first hop count.",
          minimum = 1L,
          maximum = graph_result_limits$hops,
          required = FALSE
        ),
        projection = ellmer::type_enum(
          c("semantic", "provenance", "combined"),
          "Graph edge projection.",
          required = FALSE
        ),
        max_nodes = agent_tool_integer(
          "Maximum collected nodes.",
          minimum = 1L,
          maximum = graph_result_limits$nodes,
          required = FALSE
        ),
        max_edges = agent_tool_integer(
          "Maximum collected edges.",
          minimum = 1L,
          maximum = graph_result_limits$edges,
          required = FALSE
        )
      ),
      annotations = annotations
    ),
    kg_claims = ellmer::tool(
      function(
        entity_id,
        predicate = NULL,
        include_superseded = FALSE,
        limit = 100
      ) {
        result <- kg_claims(
          store,
          entity_id = entity_id,
          predicate = predicate,
          include_superseded = include_superseded,
          limit = limit
        )
        agent_tool_bounded_result(
          result,
          extra_truncated = isTRUE(attr(result, "evidence_truncated"))
        )
      },
      name = "kg_claims",
      description = paste(
        "Retrieve bounded narrative and semantic claims about an entity.",
        "Narrative claims are never converted into fabricated semantic edges."
      ),
      arguments = list(
        entity_id = ellmer::type_string("Internal entity identifier."),
        predicate = ellmer::type_string(
          "Optional semantic predicate restriction.",
          required = FALSE
        ),
        include_superseded = ellmer::type_boolean(
          "Whether to include non-active statements.",
          required = FALSE
        ),
        limit = agent_tool_integer(
          "Maximum claim rows.",
          minimum = 1L,
          maximum = graft_retrieval_limits$claims,
          required = FALSE
        )
      ),
      annotations = annotations
    ),
    kg_select = ellmer::tool(
      function(
        class,
        fields,
        filters = list(),
        order_by = list(),
        limit = 100
      ) {
        result <- kg_select(
          store,
          class = class,
          fields = fields,
          filters = filters,
          order_by = order_by,
          limit = limit
        )
        agent_tool_bounded_result(result)
      },
      name = "kg_select",
      description = paste(
        "Run a bounded structured selection against one manifest class.",
        "Fields, filters, order clauses, and values are validated by graft;",
        "arbitrary SQL is not accepted."
      ),
      arguments = list(
        class = ellmer::type_string("Concrete manifest class."),
        fields = ellmer::type_array(
          ellmer::type_string("Public scalar field."),
          description = "Unique public scalar fields to return."
        ),
        filters = ellmer::type_array(
          agent_tool_filter_type(),
          description = "Structured filter clauses.",
          required = FALSE
        ),
        order_by = ellmer::type_array(
          agent_tool_order_type(),
          description = "Structured ordering clauses.",
          required = FALSE
        ),
        limit = agent_tool_integer(
          "Maximum result rows.",
          minimum = 1L,
          maximum = graft_retrieval_limits$select,
          required = FALSE
        )
      ),
      annotations = annotations
    )
  )
}

agent_tool_annotations <- function() {
  ellmer::tool_annotations(
    read_only_hint = TRUE,
    open_world_hint = FALSE,
    idempotent_hint = TRUE,
    destructive_hint = FALSE
  )
}

agent_tool_integer <- function(
  description,
  minimum,
  maximum,
  required
) {
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

agent_tool_filter_type <- function() {
  agent_tool_json_type(list(
    type = "object",
    additionalProperties = FALSE,
    properties = list(
      field = list(type = "string"),
      operator = list(
        type = "string",
        enum = c(
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
      ),
      value = list(
        anyOf = list(
          list(type = "string"),
          list(type = "number"),
          list(type = "integer"),
          list(type = "boolean"),
          list(type = "null"),
          list(
            type = "array",
            minItems = 1L,
            items = list(
              anyOf = list(
                list(type = "string"),
                list(type = "number"),
                list(type = "integer"),
                list(type = "boolean")
              )
            )
          )
        )
      )
    ),
    required = c("field", "operator")
  ))
}

agent_tool_order_type <- function() {
  agent_tool_json_type(list(
    type = "object",
    additionalProperties = FALSE,
    properties = list(
      field = list(type = "string"),
      direction = list(
        type = "string",
        enum = c("asc", "desc")
      )
    ),
    required = "field"
  ))
}

agent_tool_json_type <- function(schema) {
  ellmer::type_from_schema(
    text = as.character(jsonlite::toJSON(
      schema,
      auto_unbox = TRUE,
      null = "null"
    ))
  )
}

agent_tool_bounded_result <- function(result, extra_truncated = FALSE) {
  agent_tool_result(
    result,
    truncated = isTRUE(attr(result, "truncated")) ||
      isTRUE(extra_truncated),
    limit = attr(result, "limit"),
    store_schema_digest = attr(result, "store_schema_digest")
  )
}

agent_tool_result <- function(
  result,
  truncated,
  limit,
  store_schema_digest
) {
  list(
    result = result,
    truncated = isTRUE(truncated),
    limit = limit,
    store_schema_digest = store_schema_digest
  )
}
