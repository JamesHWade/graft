#' Describe the active knowledge contract
#'
#' The schema-specific context is generated from the active compiled manifest.
#' Sensitive slots are omitted. The rendered text is bounded by an approximate
#' token budget and the structured fields retain the same safe contract.
#'
#' @param store An initialized `kg_store`.
#' @param class Optional concrete class restriction.
#' @param token_budget Maximum approximate tokens in the rendered context text.
#'
#' @return A `kg_context` object with bounded text and structured safe details.
#' @export
kg_context <- function(store, class = NULL, token_budget = 1500) {
  validate_retrieval_store(store)
  token_budget <- validate_result_limit(
    token_budget,
    argument = "token_budget",
    hard_limit = graft_retrieval_limits$context_tokens
  )
  if (is.null(class)) {
    classes <- public_class_names(store)
  } else {
    validate_public_class(store, class)
    classes <- class
  }
  class_details <- context_class_details(store, classes)
  identities <- context_identity_details(store, classes)
  relationships <- context_relationship_details(store, classes)
  evidence <- context_evidence_details(store, classes)
  limits <- context_query_limits()
  ownership <- context_duckdb_ownership(store)
  text <- render_context_text(
    store,
    class_details,
    identities,
    relationships,
    evidence,
    limits,
    ownership
  )
  bounded <- bound_context_text(text, token_budget)
  new_kg_context(
    text = bounded$text,
    classes = class_details,
    identity_namespaces = identities,
    relationships = relationships,
    evidence_expectations = evidence,
    query_limits = limits,
    duckdb_ownership = ownership,
    token_budget = token_budget,
    estimated_tokens = bounded$estimated_tokens,
    truncated = bounded$truncated,
    store_schema_digest = store_schema_digest(store)
  )
}

context_class_details <- function(store, classes) {
  rows <- lapply(classes, function(record_class) {
    contract <- validate_public_class(store, record_class)
    search <- empty_character(contract$search_slots)
    label <- scalar_character(contract$label_slot)
    public <- public_slot_names(contract, multivalued = TRUE)
    search <- search[search %in% public]
    if (!is.na(label) && label %in% public) {
      search <- unique(c(label, search))
    }
    identifiers <- unique(vapply(
      Filter(
        \(.x) {
          !scalar_logical(.x$sensitive) &&
            !is.na(scalar_character(.x$external_identifier))
        },
        contract$slots
      ),
      \(.x) scalar_character(.x$external_identifier),
      character(1)
    ))
    data <- data.frame(
      class = record_class,
      role = scalar_character(contract$role),
      statement_shape = scalar_character(contract$statement_shape),
      label_slot = if (!is.na(label) && label %in% public) {
        label
      } else {
        NA_character_
      },
      stringsAsFactors = FALSE
    )
    data$searchable_fields <- I(list(search))
    data$identity_namespaces <- I(list(sort(identifiers)))
    data$public_fields <- I(list(sort(public)))
    data
  })
  bind_public_rows(rows)
}

context_identity_details <- function(store, classes) {
  rows <- list()
  for (record_class in classes) {
    contract <- validate_public_class(store, record_class)
    for (slot_name in names(contract$slots)) {
      slot <- contract$slots[[slot_name]]
      namespace <- scalar_character(slot$external_identifier)
      if (
        scalar_logical(slot$sensitive) ||
          is.na(namespace)
      ) {
        next
      }
      rows[[length(rows) + 1L]] <- data.frame(
        class = record_class,
        field = slot_name,
        namespace = namespace,
        normalization_version = scalar_character(
          store$schema$manifest$identifier_normalization_versions[[namespace]]
        ),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0L) {
    return(data.frame(
      class = character(),
      field = character(),
      namespace = character(),
      normalization_version = character(),
      stringsAsFactors = FALSE
    ))
  }
  bind_public_rows(rows)
}

context_relationship_details <- function(store, classes) {
  rows <- list()
  for (owner_class in classes) {
    contract <- validate_public_class(store, owner_class)
    references <- Filter(
      \(.x) {
        scalar_logical(.x$object_reference) &&
          !scalar_logical(.x$multivalued) &&
          !scalar_logical(.x$sensitive)
      },
      contract$slots
    )
    for (slot in names(references)) {
      slot_contract <- references[[slot]]
      rows[[length(rows) + 1L]] <- data.frame(
        name = paste(owner_class, slot, sep = "."),
        owner_class = owner_class,
        field = slot,
        kind = "object_reference",
        target_range = scalar_character(slot_contract$range),
        predicate = scalar_character(slot_contract$meaning),
        stringsAsFactors = FALSE
      )
    }
  }
  for (relation in store$schema$manifest$relations) {
    owner_class <- scalar_character(relation$owner_class)
    if (!owner_class %in% classes) {
      next
    }
    contract <- validate_public_class(store, owner_class)
    slot <- scalar_character(relation$slot)
    slot_contract <- contract$slots[[slot]]
    if (is.null(slot_contract) || scalar_logical(slot_contract$sensitive)) {
      next
    }
    rows[[length(rows) + 1L]] <- data.frame(
      name = scalar_character(relation$name),
      owner_class = owner_class,
      field = slot,
      kind = scalar_character(relation$kind),
      target_range = scalar_character(slot_contract$range),
      predicate = scalar_character(relation$predicate),
      stringsAsFactors = FALSE
    )
  }
  if (length(rows) == 0L) {
    return(data.frame(
      name = character(),
      owner_class = character(),
      field = character(),
      kind = character(),
      target_range = character(),
      predicate = character(),
      stringsAsFactors = FALSE
    ))
  }
  bind_public_rows(rows)
}

context_evidence_details <- function(store, classes) {
  evidence_classes <- intersect(classes, role_classes(store, "evidence"))
  if (length(evidence_classes) == 0L) {
    evidence_classes <- role_classes(store, "evidence")
  }
  expected <- c(
    "statement_id",
    "source_id",
    "support_type",
    "locator_type",
    "locator_value",
    "page_start",
    "page_end",
    "excerpt",
    "source_content_hash"
  )
  rows <- lapply(evidence_classes, function(record_class) {
    contract <- validate_public_class(store, record_class, roles = "evidence")
    available <- intersect(expected, public_slot_names(contract))
    data <- data.frame(
      class = record_class,
      statement_field = if ("statement_id" %in% available) {
        "statement_id"
      } else {
        NA_character_
      },
      source_field = if ("source_id" %in% available) {
        "source_id"
      } else {
        NA_character_
      },
      stringsAsFactors = FALSE
    )
    data$citation_fields <- I(list(intersect(
      c(
        "support_type",
        "locator_type",
        "locator_value",
        "page_start",
        "page_end",
        "excerpt",
        "source_content_hash"
      ),
      available
    )))
    data
  })
  if (length(rows) == 0L) {
    data <- data.frame(
      class = character(),
      statement_field = character(),
      source_field = character(),
      stringsAsFactors = FALSE
    )
    data$citation_fields <- I(list())
    return(data)
  }
  bind_public_rows(rows)
}

context_query_limits <- function() {
  list(
    find_rows = graft_retrieval_limits$find,
    claims_rows = graft_retrieval_limits$claims,
    evidence_rows = graft_retrieval_limits$evidence,
    select_rows = graft_retrieval_limits$select,
    unresolved_rows = graft_retrieval_limits$unresolved,
    traversal_hops = 2L,
    traversal_nodes = 500L,
    traversal_edges = 2000L
  )
}

context_duckdb_ownership <- function(store) {
  list(
    backend = "duckdb",
    single_owning_process = isTRUE(
      store$capabilities$single_owning_process
    ),
    owns_connection = isTRUE(store$owns_connection),
    read_only = isTRUE(store$read_only),
    agent_reads = "bounded, structured, and read-only",
    multiprocess_live_writes = FALSE
  )
}

render_context_text <- function(
  store,
  classes,
  identities,
  relationships,
  evidence,
  limits,
  ownership
) {
  manifest <- store$schema$manifest
  schema_name <- scalar_character(manifest$schema$name)
  schema_version <- scalar_character(manifest$schema$version)
  header <- paste0(
    "# ",
    schema_name,
    if (!is.na(schema_version)) paste0(" ", schema_version) else "",
    "\nStructural digest: ",
    store_schema_digest(store)
  )
  class_lines <- vapply(
    seq_len(nrow(classes)),
    function(index) {
      searchable <- classes$searchable_fields[[index]]
      label <- classes$label_slot[[index]]
      if (is.na(label)) {
        label <- "<none>"
      }
      paste0(
        "- ",
        classes$class[[index]],
        " [",
        classes$role[[index]],
        if (!is.na(classes$statement_shape[[index]])) {
          paste0("/", classes$statement_shape[[index]])
        } else {
          ""
        },
        "]; label=",
        label,
        "; search=",
        if (length(searchable) == 0L) {
          "<none>"
        } else {
          paste(searchable, collapse = ",")
        }
      )
    },
    character(1)
  )
  identity_lines <- if (nrow(identities) == 0L) {
    "- <none>"
  } else {
    paste0(
      "- ",
      identities$class,
      ".",
      identities$field,
      ": ",
      identities$namespace,
      " v",
      identities$normalization_version
    )
  }
  relation_lines <- if (nrow(relationships) == 0L) {
    "- <none>"
  } else {
    paste0(
      "- ",
      relationships$owner_class,
      ".",
      relationships$field,
      " -> ",
      relationships$target_range,
      " (",
      relationships$kind,
      ")"
    )
  }
  evidence_lines <- if (nrow(evidence) == 0L) {
    "- <none in selected class scope>"
  } else {
    vapply(
      seq_len(nrow(evidence)),
      function(index) {
        paste0(
          "- ",
          evidence$class[[index]],
          ": exact statement and source IDs; citation fields=",
          paste(evidence$citation_fields[[index]], collapse = ",")
        )
      },
      character(1)
    )
  }
  limit_line <- paste(
    paste0(names(limits), "=", unlist(limits, use.names = FALSE)),
    collapse = "; "
  )
  ownership_line <- paste0(
    "DuckDB is embedded and single-owning-process=",
    ownership$single_owning_process,
    "; connection_owned_by_graft=",
    ownership$owns_connection,
    "; read_only=",
    ownership$read_only,
    "; no live multi-process writes. Agent reads are bounded, structured, ",
    "read-only, and expose no SQL/file/network surface."
  )
  paste(
    header,
    "## Classes and search",
    paste(class_lines, collapse = "\n"),
    "## Identity namespaces",
    paste(identity_lines, collapse = "\n"),
    "## Relationships",
    paste(relation_lines, collapse = "\n"),
    "## Evidence expectations",
    paste(evidence_lines, collapse = "\n"),
    "## Query and traversal limits",
    limit_line,
    "## DuckDB ownership",
    ownership_line,
    sep = "\n"
  )
}

bound_context_text <- function(text, token_budget) {
  maximum_characters <- token_budget * 4L
  truncated <- nchar(text, type = "chars") > maximum_characters
  if (truncated) {
    suffix <- "\n[context truncated to token budget]"
    keep <- max(0L, maximum_characters - nchar(suffix, type = "chars"))
    text <- paste0(substr(text, 1L, keep), suffix)
    if (nchar(text, type = "chars") > maximum_characters) {
      text <- substr(text, 1L, maximum_characters)
    }
  }
  list(
    text = text,
    estimated_tokens = as.integer(ceiling(
      nchar(text, type = "chars") / 4
    )),
    truncated = truncated
  )
}
