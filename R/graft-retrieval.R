#' Retrieve one current accepted record
#'
#' `graft_get()` hydrates one current record from its authoritative headed
#' revision. Sensitive fields are filtered by the active contract. Related
#' identifiers, claims, and evidence are optional and independently bounded.
#'
#' @param store An initialized Graft store.
#' @param id One internal record identifier.
#' @param include Related results to include. Supported values are
#'   `"identifiers"`, `"claims"`, and `"evidence"`.
#' @param limits Named limits for included results.
#'
#' @return An ordinary list containing the public record, related results,
#'   limits, and truncation state.
#' @export
graft_get <- function(
  store,
  id,
  include = c("identifiers", "claims", "evidence"),
  limits = list(identifiers = 100L, claims = 50L, evidence = 100L)
) {
  store <- as_graft_store_internal(store, "store")
  validate_graft_retrieval(store)
  id <- validate_scalar_text(id, "id", condition = abort_reference_error)
  include <- validate_graft_get_include(include)
  limits <- validate_graft_get_limits(limits)
  row <- graft_current_rows(store, ids = id, limit = 1L)
  if (nrow(row) == 0L) {
    abort_reference_error(
      paste0("Record `", id, "` was not found."),
      record_id = id,
      field = "id",
      rule = "record_exists",
      observed_value = id
    )
  }
  record <- graft_public_current_record(store, row[1L, , drop = FALSE])
  related <- list()
  truncated <- list()
  if ("identifiers" %in% include) {
    related$identifiers <- graft_identifier_rows(store, id, limits$identifiers)
    truncated$identifiers <- isTRUE(attr(related$identifiers, "truncated"))
  }
  claims <- NULL
  if ("claims" %in% include || "evidence" %in% include) {
    claims <- graft_claim_rows(store, id, limit = limits$claims)
    if ("claims" %in% include) {
      related$claims <- claims
      truncated$claims <- isTRUE(attr(claims, "truncated"))
    }
  }
  if ("evidence" %in% include) {
    role <- scalar_character(
      store$schema$manifest$classes[[row$class[[1L]]]]$role
    )
    related$evidence <- if (identical(role, "statement")) {
      graft_evidence_rows(
        store,
        statement_ids = id,
        limit = limits$evidence
      )
    } else if (identical(role, "source")) {
      graft_evidence_rows(store, source_id = id, limit = limits$evidence)
    } else if (identical(role, "node")) {
      graft_evidence_rows(
        store,
        entity_id = id,
        limit = limits$evidence
      )
    } else {
      empty_graft_evidence(store, limits$evidence)
    }
    truncated$evidence <- isTRUE(attr(related$evidence, "truncated"))
  }
  list(
    id = id,
    class = row$class[[1L]],
    record = record,
    related = related,
    limits = limits[include],
    truncated = truncated,
    store_schema_digest = store_schema_digest(store)
  )
}

#' Search current accepted records
#'
#' `graft_find()` searches manifest-declared public search fields in current
#' headed revisions. Results are collected, deterministic, and bounded.
#'
#' @param store An initialized Graft store.
#' @param query One non-empty case-insensitive search string.
#' @param class Optional concrete class restriction.
#' @param limit Maximum rows to return, up to the package hard limit.
#'
#' @return A bounded data frame with a public-record list-column.
#' @export
graft_find <- function(store, query, class = NULL, limit = 20L) {
  store <- as_graft_store_internal(store, "store")
  validate_graft_retrieval(store)
  query <- validate_scalar_text(query, "query")
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$find
  )
  classes <- if (is.null(class)) {
    public_class_names(store)
  } else {
    validate_public_class(store, class)
    class
  }
  branches <- list()
  params <- list()
  for (record_class in sort(classes, method = "radix")) {
    contract <- store$schema$manifest$classes[[record_class]]
    fields <- graft_search_fields(contract)
    if (length(fields) == 0L) {
      next
    }
    branches[[length(branches) + 1L]] <- paste0(
      "SELECT current.record_id, current.class, current.revision_id, ",
      "current.payload_json, current.content_digest, current.recorded_at FROM (",
      graft_current_source_sql(store$connection),
      ") AS current WHERE current.class = ",
      graft_sql_string(store$connection, record_class),
      " AND LOWER(current.payload_json) LIKE ? ESCAPE '\\'"
    )
    params <- c(
      params,
      list(paste0("%", escape_graft_like(tolower(query)), "%"))
    )
  }
  if (length(branches) == 0L) {
    return(empty_graft_find(store, limit))
  }
  rows <- graft_collect_candidate_rows(
    store,
    branches,
    params,
    limit,
    function(page) {
      records <- lapply(seq_len(nrow(page)), function(index) {
        graft_public_current_record(store, page[index, , drop = FALSE])
      })
      vapply(
        seq_len(nrow(page)),
        function(index) {
          contract <- store$schema$manifest$classes[[page$class[[index]]]]
          fields <- graft_search_fields(contract)
          any(vapply(
            fields,
            function(field) {
              value <- records[[index]][[field]]
              !is.null(value) &&
                grepl(
                  tolower(query),
                  tolower(canonical_json(value)),
                  fixed = TRUE
                )
            },
            logical(1)
          ))
        },
        logical(1)
      )
    }
  )
  records <- lapply(seq_len(nrow(rows)), function(index) {
    graft_public_current_record(store, rows[index, , drop = FALSE])
  })
  matched <- lapply(seq_len(nrow(rows)), function(index) {
    contract <- store$schema$manifest$classes[[rows$class[[index]]]]
    fields <- graft_search_fields(contract)
    fields[vapply(
      fields,
      function(field) {
        value <- records[[index]][[field]]
        !is.null(value) &&
          grepl(
            tolower(query),
            tolower(canonical_json(value)),
            fixed = TRUE
          )
      },
      logical(1)
    )]
  })
  keep <- lengths(matched) > 0L
  rows <- rows[keep, , drop = FALSE]
  records <- records[keep]
  matched <- matched[keep]
  truncated <- nrow(rows) > limit
  if (nrow(rows) > limit) {
    rows <- rows[seq_len(limit), , drop = FALSE]
    records <- records[seq_len(limit)]
    matched <- matched[seq_len(limit)]
  }
  labels <- vapply(
    seq_len(nrow(rows)),
    function(index) {
      contract <- store$schema$manifest$classes[[rows$class[[index]]]]
      graft_record_label(records[[index]], contract)
    },
    character(1)
  )
  result <- data.frame(
    id = rows$record_id,
    class = rows$class,
    label = labels,
    stringsAsFactors = FALSE
  )
  result$matched_fields <- I(matched)
  result$record <- I(records)
  bounded_data_frame(result, store, limit, truncated)
}

#' Run a bounded advanced retrieval operation
#'
#' `graft_query()` is the advanced read-only retrieval surface. It accepts a
#' named `request` rather than SQL. Supported operations are `"lookup"`,
#' `"identifiers"`, `"claims"`, `"evidence"`, `"neighbors"`, `"traverse"`,
#' `"unresolved"`, and `"integrity"`.
#'
#' Request members are operation-specific: exact identifier lookup accepts
#' `namespace`, `value`, and optional `class`; identifiers and claims accept
#' `id`; evidence accepts `statement_id` or `source_id`; graph operations
#' accept their bounded path and projection arguments; unresolved mentions
#' accept optional `class` and `source_id`; and integrity accepts `projections`.
#' Unknown members are rejected. Tabular results carry `limit`, `truncated`,
#' and `store_schema_digest` attributes.
#'
#' @param store An initialized Graft store.
#' @param operation One supported operation name.
#' @param request A named list of operation-specific values.
#' @param limit Maximum rows for tabular operations.
#'
#' @return An ordinary bounded data frame or list, depending on the operation.
#' @export
graft_query <- function(
  store,
  operation = c(
    "lookup",
    "identifiers",
    "claims",
    "evidence",
    "neighbors",
    "traverse",
    "unresolved",
    "integrity"
  ),
  request = list(),
  limit = 100L
) {
  store <- as_graft_store_internal(store, "store")
  validate_store_backend(store)
  operation <- rlang::arg_match(operation)
  request <- validate_graft_query_request(request)
  if (identical(operation, "integrity")) {
    validate_graft_integrity_store(store)
    validate_request_members(request, c("projections"))
    limit <- validate_result_limit(
      limit,
      hard_limit = graft_retrieval_limits$integrity_issues
    )
    projections <- request_value(request, "projections", TRUE)
    projections <- validate_history_flag(projections, "request$projections")
    return(graft_retrieval_integrity(
      store,
      limit,
      projections,
      deep = TRUE
    ))
  }
  validate_graft_retrieval(store)
  switch(
    operation,
    lookup = graft_query_lookup(store, request, limit),
    identifiers = graft_query_identifiers(store, request, limit),
    claims = graft_query_claims(store, request, limit),
    evidence = graft_query_evidence(store, request, limit),
    neighbors = graft_query_neighbors(store, request),
    traverse = graft_query_traverse(store, request),
    unresolved = graft_query_unresolved(store, request, limit)
  )
}

validate_graft_integrity_store <- function(store) {
  validate_store_backend(store)
  if (!duckdb_table_exists(store$connection, "_graft_store")) {
    abort_backend_error(
      "The GraftStore must be initialized by `graft_open()` before retrieval.",
      operation = "graft_retrieval_integrity",
      store_path = store$path
    )
  }
  invisible(store)
}

#' Retrieve accepted record history
#'
#' `graft_history()` reads immutable revisions and hydrates them with the exact
#' historical contract and sensitivity rules. A batch ID or timestamp selects
#' a deterministic commit boundary.
#'
#' @param store An initialized Graft store.
#' @param id One internal record identifier.
#' @param as_of Optional committed batch ID or scalar `POSIXt` time.
#' @param limit Maximum revisions to return.
#'
#' @return A bounded newest-first data frame with public record list-columns.
#' @export
graft_history <- function(store, id, as_of = NULL, limit = 100L) {
  store <- as_graft_store_internal(store, "store")
  validate_graft_retrieval(store)
  graft_history_engine(store, id = id, as_of = as_of, limit = limit)
}

retrieval_query <- function(connection, sql, params = NULL) {
  with_duckdb_error(
    "graft_retrieval",
    DBI::dbGetQuery(connection, sql, params = params)
  )
}

graft_collect_candidate_rows <- function(
  store,
  branches,
  params,
  limit,
  keep_page
) {
  page_size <- graft_candidate_page_size()
  cursor <- NULL
  matches <- list()
  match_count <- 0L
  target <- limit + 1L
  repeat {
    page <- graft_candidate_page(
      store,
      branches,
      params,
      cursor,
      page_size
    )
    if (nrow(page) == 0L) {
      break
    }
    keep <- keep_page(page)
    if (!is.logical(keep) || length(keep) != nrow(page) || anyNA(keep)) {
      abort_backend_error(
        "A retrieval page filter returned an invalid selection.",
        operation = "graft_retrieval"
      )
    }
    if (any(keep)) {
      selected <- page[keep, , drop = FALSE]
      matches[[length(matches) + 1L]] <- selected
      match_count <- match_count + nrow(selected)
    }
    if (match_count >= target) {
      break
    }
    cursor <- page[nrow(page), c("class", "record_id", "revision_id")]
    if (nrow(page) < page_size) {
      break
    }
  }
  if (length(matches) == 0L) {
    return(data.frame(
      record_id = character(),
      class = character(),
      revision_id = character(),
      payload_json = character(),
      content_digest = character(),
      recorded_at = as.POSIXct(character(), tz = "UTC")
    ))
  }
  rows <- dplyr::bind_rows(matches)
  if (nrow(rows) > target) {
    rows <- rows[seq_len(target), , drop = FALSE]
  }
  rows
}

graft_candidate_page <- function(
  store,
  branches,
  params,
  cursor,
  page_size
) {
  restriction <- ""
  cursor_params <- list()
  if (!is.null(cursor)) {
    restriction <- paste0(
      " WHERE class > ? OR (class = ? AND record_id > ?) OR ",
      "(class = ? AND record_id = ? AND revision_id > ?)"
    )
    cursor_params <- list(
      cursor$class[[1L]],
      cursor$class[[1L]],
      cursor$record_id[[1L]],
      cursor$class[[1L]],
      cursor$record_id[[1L]],
      cursor$revision_id[[1L]]
    )
  }
  retrieval_query(
    store$connection,
    paste0(
      "SELECT * FROM (",
      paste(branches, collapse = " UNION ALL "),
      ") candidates",
      restriction,
      " ORDER BY class, record_id, revision_id LIMIT ",
      page_size
    ),
    params = c(params, cursor_params)
  )
}

graft_candidate_page_size <- function() {
  size <- getOption("graft.retrieval_page_size", 256L)
  validate_result_limit(
    size,
    argument = "graft.retrieval_page_size",
    hard_limit = 1000L
  )
}

validate_graft_retrieval <- function(store) {
  validate_retrieval_store(store)
  issues <- graft_retrieval_integrity(
    store,
    limit = 1L,
    projections = FALSE,
    deep = FALSE
  )
  if (nrow(issues) > 0L) {
    abort_backend_error(
      "The authoritative revision ledger is not safe to retrieve.",
      operation = "graft_retrieval_integrity",
      issues = issues
    )
  }
  invisible(store)
}

graft_retrieval_integrity <- function(store, limit, projections, deep) {
  validate_graft_integrity_store(store)
  connection <- store$connection
  issues <- c(
    shallow_integrity_issues(store, limit),
    list(graft_registry_integrity_issues(store, limit))
  )
  if (isTRUE(deep)) {
    issues <- c(
      issues,
      deep_integrity_issues(store, limit)
    )
  }
  rows <- bind_integrity_issues(issues)
  if (isTRUE(projections)) {
    projection_error <- tryCatch(
      {
        verify_projection_views(connection, store$schema)
        NULL
      },
      graft_error = identity
    )
    if (!is.null(projection_error)) {
      rows <- rbind(
        rows,
        data.frame(
          issue = "stale_projection",
          record_id = NA_character_,
          class = NA_character_,
          revision_id = NA_character_,
          batch_id = NA_character_,
          detail = conditionMessage(projection_error),
          stringsAsFactors = FALSE
        )
      )
    }
  }
  if (nrow(rows) > 0L) {
    rows <- rows[
      order(rows$issue, rows$class, rows$record_id, rows$revision_id),
      ,
      drop = FALSE
    ]
  }
  trim_bounded_rows(rows, store, limit)
}

graft_registry_integrity_issues <- function(store, limit) {
  connection <- store$connection
  revision <- quote_identifier(connection, "_graft_record_revisions")
  identifier <- quote_identifier(connection, "_graft_identifiers")
  origin <- quote_identifier(connection, "_graft_origins")
  checks <- c(
    paste0(
      "SELECT 'duplicate_record_identity' AS issue, r.record_id, ",
      "MIN(r.class) AS class, CAST(NULL AS VARCHAR) AS revision_id, ",
      "CAST(NULL AS VARCHAR) AS batch_id, ",
      "'Record ID occurs in multiple classes.' AS detail FROM ",
      revision,
      " r GROUP BY r.record_id HAVING COUNT(DISTINCT r.class) > 1"
    ),
    paste0(
      "SELECT 'missing_identifier_record' AS issue, i.record_id, i.class, ",
      "CAST(NULL AS VARCHAR) AS revision_id, ",
      "CAST(NULL AS VARCHAR) AS batch_id, ",
      "'Identifier refers to no accepted revision.' AS detail FROM ",
      identifier,
      " i LEFT JOIN (SELECT DISTINCT record_id, class FROM ",
      revision,
      ") r ON r.record_id = i.record_id AND r.class = i.class ",
      "WHERE r.record_id IS NULL"
    ),
    paste0(
      "SELECT 'missing_origin_record' AS issue, o.record_id, o.class, ",
      "CAST(NULL AS VARCHAR) AS revision_id, ",
      "CAST(NULL AS VARCHAR) AS batch_id, ",
      "'Origin refers to no accepted revision.' AS detail FROM ",
      origin,
      " o LEFT JOIN (SELECT DISTINCT record_id, class FROM ",
      revision,
      ") r ON r.record_id = o.record_id AND r.class = o.class ",
      "WHERE r.record_id IS NULL"
    )
  )
  retrieval_query(
    connection,
    paste0(
      "SELECT * FROM (",
      paste(checks, collapse = " UNION ALL "),
      ") issues ORDER BY issue, class, record_id LIMIT ",
      limit + 1L
    )
  )
}

graft_current_source_sql <- function(connection) {
  paste0(
    "SELECT h.record_id, h.class, r.revision_id, r.revision_number, ",
    "r.schema_build_digest, r.payload_json, r.content_digest, ",
    "r.recorded_at, r.commit_order ",
    "FROM ",
    quote_identifier(connection, "_graft_record_heads"),
    " h INNER JOIN ",
    quote_identifier(connection, "_graft_record_revisions"),
    " r ON r.record_id = h.record_id AND r.class = h.class ",
    "AND r.revision_id = h.revision_id ",
    "AND r.revision_number = h.revision_number ",
    "WHERE r.operation <> 'delete'"
  )
}

graft_current_rows <- function(store, ids = NULL, classes = NULL, limit) {
  where <- character()
  params <- list()
  if (!is.null(ids)) {
    ids <- unique(as.character(ids))
    if (length(ids) == 0L) {
      return(data.frame())
    }
    where <- c(
      where,
      paste0(
        "record_id IN (",
        paste(rep("?", length(ids)), collapse = ", "),
        ")"
      )
    )
    params <- c(params, as.list(ids))
  }
  if (!is.null(classes)) {
    classes <- unique(as.character(classes))
    if (length(classes) == 0L) {
      return(data.frame())
    }
    where <- c(
      where,
      paste0(
        "class IN (",
        paste(rep("?", length(classes)), collapse = ", "),
        ")"
      )
    )
    params <- c(params, as.list(classes))
  }
  restriction <- if (length(where) == 0L) {
    ""
  } else {
    paste0(" WHERE ", paste(where, collapse = " AND "))
  }
  retrieval_query(
    store$connection,
    paste0(
      "SELECT * FROM (",
      graft_current_source_sql(store$connection),
      ") current",
      restriction,
      " ORDER BY class, record_id, revision_id LIMIT ",
      limit + 1L
    ),
    params = params
  )
}

graft_public_current_record <- function(store, row) {
  contract <- store$schema$manifest$classes[[row$class[[1L]]]]
  if (is.null(contract)) {
    abort_backend_error(
      "A current revision class is absent from the active contract.",
      operation = "graft_retrieval",
      record_id = row$record_id[[1L]],
      record_class = row$class[[1L]]
    )
  }
  validated_public_revision_record(
    row$payload_json[[1L]],
    row$content_digest[[1L]],
    contract,
    record_id = row$record_id[[1L]],
    revision_id = row$revision_id[[1L]]
  )
}

graft_search_fields <- function(contract) {
  fields <- unique(c(
    scalar_character(contract$label_slot),
    empty_character(contract$search_slots)
  ))
  fields[
    !is.na(fields) &
      fields %in% names(contract$slots) &
      !vapply(
        contract$slots[fields],
        \(.x) scalar_logical(.x$sensitive),
        logical(1)
      )
  ]
}

graft_record_label <- function(record, contract) {
  candidates <- unique(c(
    scalar_character(contract$label_slot),
    empty_character(contract$search_slots),
    "label",
    "title",
    "name",
    "statement_text",
    "surface_form"
  ))
  candidates <- candidates[!is.na(candidates) & candidates %in% names(record)]
  for (field in candidates) {
    value <- record[[field]]
    if (!is.null(value) && length(value) > 0L && !is.na(value[[1L]])) {
      value <- trimws(as.character(value[[1L]]))
      if (nzchar(value)) {
        return(value)
      }
    }
  }
  NA_character_
}

graft_sql_string <- function(connection, value) {
  as.character(DBI::dbQuoteString(connection, value))
}

validate_graft_get_include <- function(include) {
  allowed <- c("identifiers", "claims", "evidence")
  if (
    !is.character(include) ||
      anyNA(include) ||
      !all(nzchar(include)) ||
      anyDuplicated(include)
  ) {
    abort_validation_error(
      "`include` must contain unique related-data names.",
      field = "include",
      rule = "unique_supported_values",
      observed_value = include
    )
  }
  unknown <- setdiff(include, allowed)
  if (length(unknown) > 0L) {
    abort_validation_error(
      paste0(
        "Unsupported `include` value(s): ",
        paste(unknown, collapse = ", "),
        "."
      ),
      field = "include",
      rule = "supported_values",
      observed_value = unknown
    )
  }
  include
}

validate_graft_get_limits <- function(limits) {
  defaults <- list(identifiers = 100L, claims = 50L, evidence = 100L)
  if (!is.list(limits) || (length(limits) > 0L && is.null(names(limits)))) {
    abort_limit_error(
      "`limits` must be a named list.",
      argument = "limits",
      requested_limit = limits
    )
  }
  unknown <- setdiff(names(limits), names(defaults))
  if (length(unknown) > 0L || !all(nzchar(names(limits)))) {
    abort_limit_error(
      paste0(
        "Unknown related-data limit(s): ",
        paste(unknown, collapse = ", "),
        "."
      ),
      argument = "limits",
      requested_limit = limits
    )
  }
  defaults[names(limits)] <- limits
  defaults$identifiers <- validate_result_limit(
    defaults$identifiers,
    "limits$identifiers",
    graft_retrieval_limits$identifiers
  )
  defaults$claims <- validate_result_limit(
    defaults$claims,
    "limits$claims",
    graft_retrieval_limits$get_claims
  )
  defaults$evidence <- validate_result_limit(
    defaults$evidence,
    "limits$evidence",
    graft_retrieval_limits$get_evidence
  )
  defaults
}

escape_graft_like <- function(value) {
  value <- gsub("\\\\", "\\\\\\\\", value)
  value <- gsub("%", "\\\\%", value, fixed = TRUE)
  gsub("_", "\\\\_", value, fixed = TRUE)
}

graft_lookup_engine <- function(store, namespace, value, class = NULL) {
  namespace <- validate_scalar_text(namespace, "namespace")
  value <- validate_scalar_text(value, "value")
  versions <- store$schema$manifest$identifier_normalization_versions
  if (!namespace %in% names(versions)) {
    abort_validation_error(
      paste0(
        "Unknown identifier namespace `",
        namespace,
        "` for the active manifest."
      ),
      field = "namespace",
      rule = "manifest_identifier_namespace",
      observed_value = namespace
    )
  }
  eligible <- graft_identifier_namespace_classes(store, namespace)
  if (length(eligible) == 0L) {
    abort_validation_error(
      paste0(
        "Identifier namespace `",
        namespace,
        "` is not declared by a public concrete class."
      ),
      field = "namespace",
      rule = "public_identifier_namespace",
      observed_value = namespace
    )
  }
  if (!is.null(class)) {
    validate_public_class(store, class)
    if (!class %in% eligible) {
      abort_validation_error(
        paste0(
          "Class `",
          class,
          "` does not declare identifier namespace `",
          namespace,
          "`."
        ),
        record_class = class,
        field = "namespace",
        rule = "class_identifier_namespace",
        observed_value = namespace
      )
    }
    eligible <- class
  }
  normalized <- normalize_graft_identifier(store, namespace, value)
  if (is.na(normalized) || !nzchar(normalized)) {
    abort_validation_error(
      "`value` is empty after identifier normalization.",
      field = "value",
      rule = "normalized_identifier",
      observed_value = value,
      namespace = namespace
    )
  }
  placeholders <- paste(rep("?", length(eligible)), collapse = ", ")
  rows <- retrieval_query(
    store$connection,
    paste0(
      "SELECT record_id, class, namespace, value, normalized_value, ",
      "status, assigned_by, confidence, created_at FROM ",
      quote_identifier(store$connection, "_graft_identifiers"),
      " WHERE namespace = ? AND normalized_value = ?",
      " AND status IN ('primary', 'equivalent')",
      " AND class IN (",
      placeholders,
      ") ORDER BY class, record_id, status, created_at"
    ),
    params = c(list(namespace, normalized), as.list(eligible))
  )
  duplicate <- split(rows$record_id, rows$class)
  inconsistent <- names(Filter(
    \(.x) length(unique(.x)) > 1L,
    duplicate
  ))
  if (length(inconsistent) > 0L) {
    abort_identity_error(
      paste0(
        "The active identifier maps to multiple records in class `",
        inconsistent[[1L]],
        "`."
      ),
      record_class = inconsistent[[1L]],
      field = "value",
      rule = "unique_active_identifier",
      observed_value = value,
      namespace = namespace,
      normalized_value = normalized,
      matched_record_ids = unique(duplicate[[inconsistent[[1L]]]])
    )
  }
  bounded_data_frame(
    rows,
    store,
    limit = max(1L, length(eligible)),
    truncated = FALSE
  )
}

graft_identifier_namespace_classes <- function(store, namespace) {
  classes <- store$schema$manifest$classes
  keep <- vapply(
    classes,
    function(contract) {
      any(vapply(
        contract$slots,
        \(.x) {
          !scalar_logical(.x$sensitive) &&
            identical(
              scalar_character(.x$external_identifier),
              namespace
            )
        },
        logical(1)
      ))
    },
    logical(1)
  )
  names(classes)[keep]
}

normalize_graft_identifier <- function(store, namespace, value) {
  version <- scalar_character(
    store$schema$manifest$identifier_normalization_versions[[namespace]]
  )
  if (!identical(version, "1")) {
    abort_schema_error(
      paste0(
        "Identifier normalization contract `",
        namespace,
        "` version `",
        version,
        "` is not supported by this Graft runtime."
      ),
      namespace = namespace,
      normalization_version = version
    )
  }
  normalize_external_identifier(namespace, value)
}

empty_graft_find <- function(store, limit) {
  result <- data.frame(
    id = character(),
    class = character(),
    label = character(),
    stringsAsFactors = FALSE
  )
  result$matched_fields <- I(list())
  result$record <- I(list())
  bounded_data_frame(result, store, limit, FALSE)
}

graft_identifier_rows <- function(store, id, limit) {
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$identifiers
  )
  eligibility <- character()
  eligibility_params <- list()
  for (record_class in sort(public_class_names(store), method = "radix")) {
    contract <- store$schema$manifest$classes[[record_class]]
    namespaces <- unique(vapply(
      Filter(
        \(slot) {
          !scalar_logical(slot$sensitive) &&
            !is.na(scalar_character(slot$external_identifier))
        },
        contract$slots
      ),
      \(slot) scalar_character(slot$external_identifier),
      character(1)
    ))
    if (length(namespaces) == 0L) {
      next
    }
    eligibility <- c(
      eligibility,
      paste0(
        "(class = ? AND namespace IN (",
        paste(rep("?", length(namespaces)), collapse = ", "),
        "))"
      )
    )
    eligibility_params <- c(
      eligibility_params,
      list(record_class),
      as.list(namespaces)
    )
  }
  if (length(eligibility) == 0L) {
    result <- data.frame(
      record_id = character(),
      class = character(),
      namespace = character(),
      value = character(),
      normalized_value = character(),
      status = character(),
      assigned_by = character(),
      confidence = numeric(),
      created_at = as.POSIXct(character(), tz = "UTC")
    )
    return(bounded_data_frame(result, store, limit, FALSE))
  }
  rows <- retrieval_query(
    store$connection,
    paste0(
      "SELECT record_id, class, namespace, value, normalized_value, status, ",
      "assigned_by, confidence, created_at FROM ",
      quote_identifier(store$connection, "_graft_identifiers"),
      " WHERE record_id = ? AND (",
      paste(eligibility, collapse = " OR "),
      ") ORDER BY class, CASE status ",
      "WHEN 'primary' THEN 0 WHEN 'equivalent' THEN 1 ",
      "WHEN 'candidate' THEN 2 ELSE 3 END, namespace, normalized_value ",
      "LIMIT ",
      limit + 1L
    ),
    params = c(list(id), eligibility_params)
  )
  trim_bounded_rows(rows, store, limit)
}

graft_claim_rows <- function(
  store,
  entity_id,
  predicate = NULL,
  include_superseded = FALSE,
  limit
) {
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$claims
  )
  predicate <- validate_optional_scalar_text(predicate, "predicate")
  include_superseded <- validate_graft_include_superseded(include_superseded)
  classes <- statement_classes(store)
  branches <- list()
  params <- list()
  for (record_class in sort(classes, method = "radix")) {
    branches[[length(branches) + 1L]] <- paste0(
      "SELECT current.record_id, current.class, current.revision_id, ",
      "current.payload_json, current.content_digest, current.recorded_at FROM (",
      graft_current_source_sql(store$connection),
      ") current WHERE current.class = ",
      graft_sql_string(store$connection, record_class),
      " AND LOWER(current.payload_json) LIKE ? ESCAPE '\\'"
    )
    params <- c(
      params,
      list(paste0(
        "%",
        escape_graft_like(tolower(canonical_json(entity_id))),
        "%"
      ))
    )
  }
  if (length(branches) == 0L) {
    return(empty_graft_claims(store, limit))
  }
  rows <- graft_collect_candidate_rows(
    store,
    branches,
    params,
    limit,
    function(page) {
      result <- bind_public_rows(lapply(seq_len(nrow(page)), function(index) {
        graft_claim_result_row(store, page[index, , drop = FALSE])
      }))
      graft_claim_result_matches(
        result,
        entity_id,
        predicate,
        include_superseded
      )
    }
  )
  result <- bind_public_rows(lapply(seq_len(nrow(rows)), function(index) {
    graft_claim_result_row(store, rows[index, , drop = FALSE])
  }))
  if (nrow(result) == 0L) {
    return(empty_graft_claims(store, limit))
  }
  truncated <- nrow(result) > limit
  if (nrow(result) > limit) {
    result <- result[seq_len(limit), , drop = FALSE]
  }
  bounded_data_frame(result, store, limit, truncated)
}

validate_graft_include_superseded <- function(include_superseded) {
  if (
    !is.logical(include_superseded) ||
      length(include_superseded) != 1L ||
      is.na(include_superseded)
  ) {
    abort_validation_error(
      "`include_superseded` must be `TRUE` or `FALSE`.",
      field = "include_superseded",
      rule = "scalar_logical",
      observed_value = include_superseded
    )
  }
  include_superseded
}

graft_claim_result_matches <- function(
  result,
  entity_id,
  predicate,
  include_superseded
) {
  matches_entity <- vapply(
    seq_len(nrow(result)),
    function(index) {
      if (identical(result$statement_shape[[index]], "narrative")) {
        identical(result$primary_subject[[index]], entity_id) ||
          entity_id %in% result$about[[index]]
      } else {
        identical(result$subject[[index]], entity_id) ||
          identical(result$object_entity[[index]], entity_id)
      }
    },
    logical(1)
  )
  keep <- matches_entity
  if (!include_superseded) {
    keep <- keep & (is.na(result$status) | result$status == "active")
  }
  if (!is.null(predicate)) {
    keep <- keep & !is.na(result$predicate) & result$predicate == predicate
  }
  keep
}

graft_claim_result_row <- function(store, row) {
  record_class <- row$class[[1L]]
  contract <- store$schema$manifest$classes[[record_class]]
  record <- graft_public_current_record(store, row)
  shape <- scalar_character(contract$statement_shape)
  core <- c(
    "id",
    "statement_text",
    "primary_subject",
    "about",
    "subject",
    "predicate",
    "object_entity",
    "object_value",
    "object_datatype",
    "polarity",
    "confidence",
    "status",
    "valid_from",
    "valid_to",
    "asserted_at",
    "superseded_by",
    "derived_from_statement",
    "created_at",
    "updated_at"
  )
  qualifiers <- intersect(
    empty_character(contract$qualifier_slots),
    names(record)
  )
  result <- data.frame(
    id = as.character(retrieval_record_scalar(record, "id")),
    class = record_class,
    statement_shape = shape,
    statement_text = as.character(retrieval_record_scalar(
      record,
      "statement_text"
    )),
    primary_subject = as.character(retrieval_record_scalar(
      record,
      "primary_subject"
    )),
    subject = as.character(retrieval_record_scalar(record, "subject")),
    predicate = as.character(retrieval_record_scalar(record, "predicate")),
    object_entity = as.character(retrieval_record_scalar(
      record,
      "object_entity"
    )),
    object_value = as.character(retrieval_record_scalar(
      record,
      "object_value"
    )),
    object_datatype = as.character(retrieval_record_scalar(
      record,
      "object_datatype"
    )),
    polarity = as.character(retrieval_record_scalar(record, "polarity")),
    confidence = suppressWarnings(as.numeric(
      retrieval_record_scalar(record, "confidence", NA_real_)
    )),
    status = as.character(retrieval_record_scalar(record, "status")),
    superseded_by = as.character(retrieval_record_scalar(
      record,
      "superseded_by"
    )),
    derived_from_statement = as.character(
      retrieval_record_scalar(record, "derived_from_statement")
    ),
    stringsAsFactors = FALSE
  )
  about <- record$about
  if (is.null(about)) {
    about <- character()
  }
  result$about <- I(list(about))
  result$qualifiers <- I(list(record[qualifiers]))
  result$attributes <- I(list(record[setdiff(
    names(record),
    c(core, qualifiers)
  )]))
  result$record <- I(list(record))
  result
}

empty_graft_claims <- function(store, limit) {
  result <- data.frame(
    id = character(),
    class = character(),
    statement_shape = character(),
    statement_text = character(),
    primary_subject = character(),
    subject = character(),
    predicate = character(),
    object_entity = character(),
    object_value = character(),
    object_datatype = character(),
    polarity = character(),
    confidence = numeric(),
    status = character(),
    superseded_by = character(),
    derived_from_statement = character(),
    stringsAsFactors = FALSE
  )
  result$about <- I(list())
  result$qualifiers <- I(list())
  result$attributes <- I(list())
  result$record <- I(list())
  bounded_data_frame(result, store, limit, FALSE)
}

graft_evidence_rows <- function(
  store,
  statement_ids = NULL,
  source_id = NULL,
  support_type = NULL,
  entity_id = NULL,
  limit
) {
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$evidence
  )
  support_type <- validate_optional_scalar_text(support_type, "support_type")
  classes <- role_classes(store, "evidence")
  branches <- list()
  params <- list()
  for (record_class in sort(classes, method = "radix")) {
    contract <- store$schema$manifest$classes[[record_class]]
    where <- character()
    branch_params <- list()
    if (!is.null(statement_ids)) {
      statement_ids <- unique(as.character(statement_ids))
      where <- c(
        where,
        paste0(
          "(",
          paste(
            rep(
              "LOWER(current.payload_json) LIKE ? ESCAPE '\\'",
              length(statement_ids)
            ),
            collapse = " OR "
          ),
          ")"
        )
      )
      branch_params <- c(
        branch_params,
        lapply(statement_ids, \(id) {
          paste0("%", escape_graft_like(tolower(canonical_json(id))), "%")
        })
      )
    }
    if (!is.null(source_id)) {
      where <- c(
        where,
        "LOWER(current.payload_json) LIKE ? ESCAPE '\\'"
      )
      branch_params <- c(
        branch_params,
        list(paste0(
          "%",
          escape_graft_like(tolower(canonical_json(source_id))),
          "%"
        ))
      )
    }
    if (!is.null(support_type)) {
      validate_graft_evidence_support_type(store, contract, support_type)
      where <- c(
        where,
        "LOWER(current.payload_json) LIKE ? ESCAPE '\\'"
      )
      branch_params <- c(
        branch_params,
        list(paste0(
          "%",
          escape_graft_like(tolower(canonical_json(support_type))),
          "%"
        ))
      )
    }
    branches[[length(branches) + 1L]] <- paste0(
      "SELECT current.record_id, current.class, current.revision_id, ",
      "current.payload_json, current.content_digest, current.recorded_at FROM (",
      graft_current_source_sql(store$connection),
      ") current WHERE current.class = ",
      graft_sql_string(store$connection, record_class),
      if (length(where) > 0L) {
        paste0(" AND ", paste(where, collapse = " AND "))
      } else {
        ""
      }
    )
    params <- c(params, branch_params)
  }
  if (length(branches) == 0L) {
    return(empty_graft_evidence(store, limit))
  }
  rows <- graft_collect_candidate_rows(
    store,
    branches,
    params,
    limit,
    function(page) {
      records <- lapply(seq_len(nrow(page)), function(index) {
        graft_public_current_record(store, page[index, , drop = FALSE])
      })
      graft_evidence_records_match(
        store,
        records,
        statement_ids,
        source_id,
        support_type,
        entity_id
      )
    }
  )
  if (nrow(rows) == 0L) {
    return(empty_graft_evidence(store, limit))
  }
  records <- lapply(seq_len(nrow(rows)), function(index) {
    graft_public_current_record(store, rows[index, , drop = FALSE])
  })
  truncated <- nrow(rows) > limit
  if (nrow(rows) > limit) {
    rows <- rows[seq_len(limit), , drop = FALSE]
    records <- records[seq_len(limit)]
  }
  if (nrow(rows) == 0L) {
    return(empty_graft_evidence(store, limit))
  }
  source_ids <- unique(vapply(
    records,
    \(record) as.character(retrieval_record_scalar(record, "source_id")),
    character(1)
  ))
  sources <- graft_current_rows(
    store,
    ids = source_ids,
    limit = length(source_ids)
  )
  source_map <- list()
  for (index in seq_len(nrow(sources))) {
    source_record <- graft_public_current_record(
      store,
      sources[index, , drop = FALSE]
    )
    source_map[[sources$record_id[[index]]]] <- list(
      class = sources$class[[index]],
      record = source_record
    )
  }
  result <- bind_public_rows(lapply(seq_len(nrow(rows)), function(index) {
    graft_evidence_result_row(
      store,
      rows$class[[index]],
      records[[index]],
      source_map
    )
  }))
  bounded_data_frame(result, store, limit, truncated)
}

graft_evidence_records_match <- function(
  store,
  records,
  statement_ids,
  source_id,
  support_type,
  entity_id
) {
  keep <- vapply(
    records,
    function(record) {
      statement <- as.character(retrieval_record_scalar(record, "statement_id"))
      source <- as.character(retrieval_record_scalar(record, "source_id"))
      support <- as.character(retrieval_record_scalar(record, "support_type"))
      (is.null(statement_ids) || statement %in% statement_ids) &&
        (is.null(source_id) || identical(source, source_id)) &&
        (is.null(support_type) || identical(support, support_type))
    },
    logical(1)
  )
  if (is.null(entity_id) || !any(keep)) {
    return(keep)
  }
  selected <- which(keep)
  related <- graft_statement_ids_match_entity(
    store,
    vapply(
      records[selected],
      function(record) {
        as.character(retrieval_record_scalar(record, "statement_id"))
      },
      character(1)
    ),
    entity_id
  )
  keep[selected] <- related
  keep
}

graft_statement_ids_match_entity <- function(store, statement_ids, entity_id) {
  requested <- statement_ids
  statement_ids <- unique(requested)
  rows <- graft_current_rows(
    store,
    ids = statement_ids,
    classes = statement_classes(store),
    limit = length(statement_ids)
  )
  matches <- character()
  if (nrow(rows) > 0L) {
    result <- bind_public_rows(lapply(seq_len(nrow(rows)), function(index) {
      graft_claim_result_row(store, rows[index, , drop = FALSE])
    }))
    matches <- result$id[graft_claim_result_matches(
      result,
      entity_id,
      predicate = NULL,
      include_superseded = FALSE
    )]
  }
  requested %in% matches
}

graft_evidence_result_row <- function(
  store,
  evidence_class,
  record,
  source_map
) {
  source_id <- as.character(retrieval_record_scalar(record, "source_id"))
  source <- source_map[[source_id]]
  if (is.null(source)) {
    abort_reference_error(
      paste0("Evidence refers to missing source record `", source_id, "`."),
      record_id = source_id,
      field = "source_id",
      rule = "source_exists",
      observed_value = source_id
    )
  }
  source_contract <- store$schema$manifest$classes[[source$class]]
  uri_slot <- graft_source_uri_slot(source_contract)
  title_slot <- graft_source_title_slot(source_contract)
  result <- data.frame(
    evidence_class = evidence_class,
    id = as.character(retrieval_record_scalar(record, "id")),
    statement_id = as.character(retrieval_record_scalar(
      record,
      "statement_id"
    )),
    source_id = source_id,
    support_type = as.character(retrieval_record_scalar(
      record,
      "support_type"
    )),
    locator_type = as.character(retrieval_record_scalar(
      record,
      "locator_type"
    )),
    locator_value = as.character(retrieval_record_scalar(
      record,
      "locator_value"
    )),
    page_start = retrieval_record_scalar(record, "page_start", NA_real_),
    page_end = retrieval_record_scalar(record, "page_end", NA_real_),
    excerpt = as.character(retrieval_record_scalar(record, "excerpt")),
    source_class = source$class,
    source_uri = as.character(retrieval_record_scalar(source$record, uri_slot)),
    source_title = as.character(retrieval_record_scalar(
      source$record,
      title_slot
    )),
    stringsAsFactors = FALSE
  )
  result$record <- I(list(record))
  result$source_record <- I(list(source$record))
  result
}

validate_graft_evidence_support_type <- function(
  store,
  contract,
  support_type
) {
  slot <- contract$slots$support_type
  enum <- scalar_character(slot$enum)
  if (is.na(enum)) {
    return(invisible(support_type))
  }
  allowed <- vapply(
    store$schema$manifest$enums[[enum]]$permissible_values,
    \(.x) scalar_character(.x$value),
    character(1)
  )
  if (!support_type %in% allowed) {
    abort_validation_error(
      paste0("Unknown evidence support type `", support_type, "`."),
      record_class = scalar_character(contract$name),
      field = "support_type",
      rule = "enum",
      observed_value = support_type,
      allowed_values = allowed
    )
  }
  invisible(support_type)
}

graft_source_uri_slot <- function(contract) {
  slots <- public_scalar_slots(contract)
  external <- names(Filter(
    \(.x) {
      identical(
        scalar_character(.x$external_identifier),
        "canonical_url"
      )
    },
    slots
  ))
  candidates <- unique(c(external, "uri", "url"))
  candidates <- candidates[candidates %in% names(slots)]
  if (length(candidates) == 0L) NA_character_ else candidates[[1L]]
}

graft_source_title_slot <- function(contract) {
  candidates <- c(
    scalar_character(contract$label_slot),
    "title",
    "label",
    "name"
  )
  candidates <- candidates[
    !is.na(candidates) & candidates %in% names(public_scalar_slots(contract))
  ]
  if (length(candidates) == 0L) NA_character_ else candidates[[1L]]
}

empty_graft_evidence <- function(store, limit) {
  result <- data.frame(
    evidence_class = character(),
    id = character(),
    statement_id = character(),
    source_id = character(),
    support_type = character(),
    locator_type = character(),
    locator_value = character(),
    page_start = numeric(),
    page_end = numeric(),
    excerpt = character(),
    source_class = character(),
    source_uri = character(),
    source_title = character(),
    stringsAsFactors = FALSE
  )
  result$record <- I(list())
  result$source_record <- I(list())
  bounded_data_frame(result, store, limit, FALSE)
}

retrieval_record_scalar <- function(record, field, default = NA_character_) {
  if (
    length(field) != 1L ||
      is.na(field) ||
      is.null(record[[field]]) ||
      length(record[[field]]) == 0L
  ) {
    return(default)
  }
  record[[field]][[1L]]
}

validate_graft_query_request <- function(request) {
  if (!is.list(request) || (length(request) > 0L && is.null(names(request)))) {
    abort_validation_error(
      "`request` must be a named list.",
      field = "request",
      rule = "named_request",
      observed_value = request
    )
  }
  if (
    length(request) > 0L &&
      (anyNA(names(request)) ||
        !all(nzchar(names(request))) ||
        anyDuplicated(names(request)))
  ) {
    abort_validation_error(
      "`request` names must be unique and non-empty.",
      field = "request",
      rule = "unique_request_names",
      observed_value = names(request)
    )
  }
  request
}

validate_request_members <- function(request, allowed, required = character()) {
  unknown <- setdiff(names(request), allowed)
  missing <- setdiff(required, names(request))
  if (length(unknown) > 0L || length(missing) > 0L) {
    abort_validation_error(
      "The query request has unknown or missing members.",
      field = "request",
      rule = "operation_request_shape",
      observed_value = names(request),
      allowed_members = allowed,
      missing_members = missing
    )
  }
  invisible(request)
}

request_value <- function(request, name, default = NULL) {
  if (name %in% names(request)) request[[name]] else default
}

graft_query_lookup <- function(store, request, limit) {
  validate_request_members(
    request,
    c("namespace", "value", "class"),
    c("namespace", "value")
  )
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$identifiers
  )
  result <- graft_lookup_engine(
    store,
    namespace = request$namespace,
    value = request$value,
    class = request_value(request, "class")
  )
  trim_bounded_rows(result, store, limit)
}

graft_query_identifiers <- function(store, request, limit) {
  validate_request_members(request, "id", "id")
  id <- validate_scalar_text(
    request$id,
    "request$id",
    condition = abort_reference_error
  )
  graft_identifier_rows(store, id, limit)
}

graft_query_claims <- function(store, request, limit) {
  validate_request_members(
    request,
    c("id", "predicate", "include_superseded"),
    "id"
  )
  id <- validate_scalar_text(
    request$id,
    "request$id",
    condition = abort_reference_error
  )
  graft_claim_rows(
    store,
    entity_id = id,
    predicate = request_value(request, "predicate"),
    include_superseded = request_value(request, "include_superseded", FALSE),
    limit = limit
  )
}

graft_query_evidence <- function(store, request, limit) {
  validate_request_members(
    request,
    c("statement_id", "source_id", "support_type")
  )
  statement_id <- request_value(request, "statement_id")
  source_id <- request_value(request, "source_id")
  if (is.null(statement_id) && is.null(source_id)) {
    abort_validation_error(
      "Evidence queries require `statement_id` or `source_id`.",
      field = "request",
      rule = "evidence_scope",
      observed_value = request
    )
  }
  if (!is.null(statement_id)) {
    statement_id <- validate_scalar_text(statement_id, "request$statement_id")
  }
  if (!is.null(source_id)) {
    source_id <- validate_scalar_text(source_id, "request$source_id")
  }
  graft_evidence_rows(
    store,
    statement_ids = statement_id,
    source_id = source_id,
    support_type = request_value(request, "support_type"),
    limit = limit
  )
}

graft_query_neighbors <- function(store, request) {
  allowed <- c(
    "id",
    "predicate",
    "direction",
    "hops",
    "projection",
    "max_nodes",
    "max_edges"
  )
  validate_request_members(request, allowed, "id")
  verify_projection_views(store$connection, store$schema)
  result <- graft_neighbors_engine(
    store,
    id = request$id,
    predicate = request_value(request, "predicate"),
    direction = request_value(request, "direction", "both"),
    hops = request_value(request, "hops", 1L),
    projection = request_value(request, "projection", "combined"),
    max_nodes = request_value(request, "max_nodes", graph_result_limits$nodes),
    max_edges = request_value(request, "max_edges", graph_result_limits$edges)
  )
  result
}

graft_query_traverse <- function(store, request) {
  allowed <- c(
    "from",
    "via",
    "direction",
    "max_hops",
    "projection",
    "max_nodes",
    "max_edges"
  )
  validate_request_members(request, allowed, c("from", "via"))
  verify_projection_views(store$connection, store$schema)
  result <- graft_traverse_engine(
    store,
    from = request$from,
    via = request$via,
    direction = request_value(request, "direction", "out"),
    max_hops = request_value(request, "max_hops", length(request$via)),
    projection = request_value(request, "projection", "combined"),
    max_nodes = request_value(request, "max_nodes", graph_result_limits$nodes),
    max_edges = request_value(request, "max_edges", graph_result_limits$edges)
  )
  result
}

graft_query_unresolved <- function(store, request, limit) {
  validate_request_members(request, c("class", "source_id"))
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$unresolved
  )
  classes <- if (is.null(request_value(request, "class"))) {
    role_classes(store, "mention")
  } else {
    validate_public_class(store, request$class, roles = "mention")
    request$class
  }
  source_id <- request_value(request, "source_id")
  if (!is.null(source_id)) {
    source_id <- validate_scalar_text(source_id, "request$source_id")
  }
  branches <- list()
  params <- list()
  for (record_class in sort(classes, method = "radix")) {
    contract <- store$schema$manifest$classes[[record_class]]
    if (!"entity_id" %in% names(contract$slots)) {
      next
    }
    where <- "current.payload_json LIKE '%\"entity_id\":null%'"
    if (!is.null(source_id) && "source_id" %in% names(contract$slots)) {
      where <- paste0(
        where,
        " AND LOWER(current.payload_json) LIKE ? ESCAPE '\\'"
      )
      params <- c(
        params,
        list(paste0(
          "%",
          escape_graft_like(tolower(canonical_json(source_id))),
          "%"
        ))
      )
    }
    branches[[length(branches) + 1L]] <- paste0(
      "SELECT current.record_id, current.class, current.revision_id, ",
      "current.payload_json, current.content_digest, current.recorded_at FROM (",
      graft_current_source_sql(store$connection),
      ") current WHERE current.class = ",
      graft_sql_string(store$connection, record_class),
      " AND ",
      where
    )
  }
  if (length(branches) == 0L) {
    result <- data.frame(id = character(), class = character())
    result$record <- I(list())
    return(bounded_data_frame(result, store, limit, FALSE))
  }
  rows <- graft_collect_candidate_rows(
    store,
    branches,
    params,
    limit,
    function(page) {
      records <- lapply(seq_len(nrow(page)), function(index) {
        graft_public_current_record(store, page[index, , drop = FALSE])
      })
      vapply(
        records,
        function(record) {
          entity <- record$entity_id
          source <- as.character(retrieval_record_scalar(record, "source_id"))
          is.null(entity) &&
            (is.null(source_id) || identical(source, source_id))
        },
        logical(1)
      )
    }
  )
  records <- lapply(seq_len(nrow(rows)), function(index) {
    graft_public_current_record(store, rows[index, , drop = FALSE])
  })
  truncated <- nrow(rows) > limit
  if (nrow(rows) > limit) {
    rows <- rows[seq_len(limit), , drop = FALSE]
    records <- records[seq_len(limit)]
  }
  result <- data.frame(id = rows$record_id, class = rows$class)
  result$record <- I(records)
  bounded_data_frame(result, store, limit, truncated)
}
