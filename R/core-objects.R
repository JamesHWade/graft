new_kg_schema <- function(manifest, path = NULL) {
  structure(
    list(
      manifest = manifest,
      path = path
    ),
    class = "kg_schema"
  )
}

new_kg_schema_diff <- function(
  compatible,
  old_structural_digest,
  new_structural_digest,
  classes,
  slots,
  enums,
  tables,
  relations,
  classification,
  details
) {
  structure(
    list(
      compatible = compatible,
      classification = classification,
      old_structural_digest = old_structural_digest,
      new_structural_digest = new_structural_digest,
      classes = classes,
      slots = slots,
      enums = enums,
      tables = tables,
      relations = relations,
      details = details
    ),
    class = "kg_schema_diff"
  )
}

new_kg_store <- function(
  schema,
  connection,
  owns_connection,
  read_only,
  path,
  capabilities,
  okf_mode,
  okf_path
) {
  store <- new.env(parent = emptyenv())
  store$schema <- schema
  store$connection <- connection
  store$owns_connection <- owns_connection
  store$read_only <- read_only
  store$path <- path
  store$closed <- FALSE
  store$capabilities <- capabilities
  store$okf_mode <- okf_mode
  store$okf_path <- okf_path
  store$okf_expected <- NULL
  store$verification <- NULL
  class(store) <- "kg_store"
  store
}

new_kg_record <- function(
  id,
  record_class,
  record,
  related,
  limits,
  truncated,
  store_schema_digest
) {
  structure(
    c(
      list(
        id = id,
        class = record_class,
        record = record
      ),
      related,
      list(
        truncated = truncated,
        limits = limits,
        store_schema_digest = store_schema_digest
      )
    ),
    class = "kg_record"
  )
}

new_kg_context <- function(
  text,
  classes,
  identity_namespaces,
  relationships,
  evidence_expectations,
  query_limits,
  duckdb_ownership,
  token_budget,
  estimated_tokens,
  truncated,
  store_schema_digest
) {
  structure(
    list(
      text = text,
      classes = classes,
      identity_namespaces = identity_namespaces,
      relationships = relationships,
      evidence_expectations = evidence_expectations,
      query_limits = query_limits,
      duckdb_ownership = duckdb_ownership,
      token_budget = token_budget,
      estimated_tokens = estimated_tokens,
      truncated = truncated,
      store_schema_digest = store_schema_digest
    ),
    class = "kg_context"
  )
}

new_kg_subgraph <- function(
  nodes,
  edges,
  roots,
  path,
  predicate,
  direction,
  hops,
  projection,
  truncated,
  limits,
  store_schema_digest,
  request_kind
) {
  request <- list(
    kind = request_kind,
    roots = roots,
    path = path,
    predicate = predicate,
    direction = direction,
    hops = as.integer(hops),
    projection = projection
  )
  structure(
    list(
      nodes = nodes,
      edges = edges,
      roots = roots,
      requested_roots = roots,
      path = path,
      predicate = predicate,
      direction = direction,
      hops = as.integer(hops),
      projection = projection,
      request = request,
      truncated = isTRUE(truncated),
      limits = limits,
      store_schema_digest = store_schema_digest
    ),
    class = "kg_subgraph"
  )
}

is_kg_schema <- function(x) {
  inherits(x, "kg_schema")
}

as_kg_schema <- function(x, arg = rlang::caller_arg(x)) {
  if (is_kg_schema(x)) {
    return(x)
  }
  if (is.character(x) && length(x) == 1L && !is.na(x)) {
    return(kg_schema(x))
  }
  abort_schema_error(
    paste0("`", arg, "` must be a kg_schema object or a manifest path."),
    argument = arg
  )
}

is_kg_store <- function(x) {
  inherits(x, "kg_store") && is.environment(x)
}

validate_kg_store <- function(
  store,
  require_open = TRUE,
  arg = rlang::caller_arg(store)
) {
  if (!is_kg_store(store)) {
    abort_backend_error(
      paste0("`", arg, "` must be a kg_store object."),
      operation = "validate_store",
      argument = arg
    )
  }
  if (
    !isTRUE(store$closed) &&
      !isTRUE(tryCatch(
        DBI::dbIsValid(store$connection),
        error = \(.x) FALSE
      ))
  ) {
    store$closed <- TRUE
  }
  if (isTRUE(require_open) && isTRUE(store$closed)) {
    abort_backend_error(
      "The kg_store is closed.",
      operation = "validate_store",
      store_path = store$path
    )
  }
  invisible(store)
}

scalar_character <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0L) {
    return(default)
  }
  as.character(x[[1L]])
}

scalar_logical <- function(x, default = FALSE) {
  if (is.null(x) || length(x) == 0L) {
    return(default)
  }
  isTRUE(x[[1L]])
}

empty_character <- function(x) {
  if (is.null(x)) {
    return(character())
  }
  as.character(unlist(x, use.names = FALSE))
}
