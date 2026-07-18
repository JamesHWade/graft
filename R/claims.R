#' Retrieve evidence for one statement
#'
#' Evidence is joined to the exact stored source record. Citation and locator
#' fields are returned only from stored rows.
#'
#' @param store An initialized `kg_store`.
#' @param statement_id One internal statement identifier.
#' @param support_type Optional evidence support type.
#' @param limit Maximum evidence records to return.
#'
#' @return A bounded data frame of evidence and source details.
#' @export
kg_evidence <- function(
  store,
  statement_id,
  support_type = NULL,
  limit = 100
) {
  validate_retrieval_store(store)
  statement_id <- validate_scalar_text(
    statement_id,
    "statement_id",
    condition = abort_reference_error
  )
  support_type <- validate_optional_scalar_text(
    support_type,
    "support_type"
  )
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$evidence
  )
  evidence_rows(
    store,
    field = "statement_id",
    value = statement_id,
    support_type = support_type,
    limit = limit
  )
}

evidence_rows <- function(
  store,
  field,
  value,
  support_type = NULL,
  limit
) {
  classes <- role_classes(store, "evidence")
  rows <- list()
  for (record_class in classes) {
    contract <- validate_public_class(store, record_class, roles = "evidence")
    fields <- public_slot_names(contract)
    if (!field %in% fields) {
      next
    }
    if (
      !is.null(support_type) &&
        !"support_type" %in% fields
    ) {
      next
    }
    selected <- vapply(
      fields,
      function(slot) {
        column <- quote_identifier(
          store$connection,
          slot_column(contract, slot)
        )
        if (identical(slot, slot_column(contract, slot))) {
          return(column)
        }
        paste0(
          column,
          " AS ",
          quote_identifier(store$connection, slot)
        )
      },
      character(1)
    )
    where <- paste0(
      quote_identifier(store$connection, slot_column(contract, field)),
      " = ?"
    )
    params <- list(value)
    if (!is.null(support_type)) {
      validate_evidence_support_type(store, contract, support_type)
      where <- paste0(
        where,
        " AND ",
        quote_identifier(
          store$connection,
          slot_column(contract, "support_type")
        ),
        " = ?"
      )
      params <- c(params, list(support_type))
    }
    sql <- paste0(
      "SELECT ",
      as.character(DBI::dbQuoteString(store$connection, record_class)),
      " AS evidence_class, ",
      paste(selected, collapse = ", "),
      " FROM ",
      quote_identifier(store$connection, scalar_character(contract$table)),
      " WHERE ",
      where,
      " ORDER BY ",
      quote_identifier(store$connection, slot_column(contract, "id")),
      " LIMIT ",
      limit + 1L
    )
    rows[[record_class]] <- with_duckdb_error(
      "evidence_records",
      DBI::dbGetQuery(store$connection, sql, params = params)
    )
  }
  result <- bind_public_rows(rows)
  if (nrow(result) == 0L) {
    result$source_class <- character()
    result$source_uri <- character()
    result$source_title <- character()
    return(bounded_data_frame(result, store, limit, FALSE))
  }
  result <- hydrate_evidence_sources(store, result)
  result <- result[
    order(result$evidence_class, result$id),
    ,
    drop = FALSE
  ]
  trim_bounded_rows(result, store, limit)
}

validate_evidence_support_type <- function(store, contract, support_type) {
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

hydrate_evidence_sources <- function(store, evidence) {
  source_ids <- unique(as.character(evidence$source_id))
  source_map <- list()
  source_classes <- role_classes(store, "source")
  for (source_id in source_ids) {
    locations <- record_locations(store, source_id, source_classes)
    if (length(locations) == 0L) {
      abort_reference_error(
        paste0(
          "Evidence refers to missing source record `",
          source_id,
          "`."
        ),
        record_id = source_id,
        field = "source_id",
        rule = "source_exists",
        observed_value = source_id
      )
    }
    if (length(locations) != 1L || unname(locations[[1L]]) != 1L) {
      abort_identity_error(
        paste0("Source record `", source_id, "` is ambiguous."),
        record_id = source_id,
        field = "source_id",
        rule = "unique_source_location",
        observed_value = source_id,
        matched_classes = names(locations)
      )
    }
    source_class <- names(locations)[[1L]]
    contract <- validate_public_class(
      store,
      source_class,
      roles = "source"
    )
    fields <- public_slot_names(contract)
    uri_slot <- source_uri_slot(contract)
    title_slot <- source_title_slot(contract)
    selected_slots <- unique(c("id", uri_slot, title_slot))
    selected_slots <- selected_slots[
      !is.na(selected_slots) & selected_slots %in% fields
    ]
    selected <- vapply(
      selected_slots,
      function(slot) {
        column <- quote_identifier(
          store$connection,
          slot_column(contract, slot)
        )
        if (identical(slot, slot_column(contract, slot))) {
          return(column)
        }
        paste0(
          column,
          " AS ",
          quote_identifier(store$connection, slot)
        )
      },
      character(1)
    )
    sql <- paste0(
      "SELECT ",
      paste(selected, collapse = ", "),
      " FROM ",
      quote_identifier(store$connection, scalar_character(contract$table)),
      " WHERE ",
      quote_identifier(store$connection, slot_column(contract, "id")),
      " = ?"
    )
    row <- with_duckdb_error(
      "evidence_source",
      DBI::dbGetQuery(
        store$connection,
        sql,
        params = list(source_id)
      )
    )
    source_map[[source_id]] <- list(
      class = source_class,
      uri = if (!is.na(uri_slot) && uri_slot %in% names(row)) {
        as.character(row[[uri_slot]][[1L]])
      } else {
        NA_character_
      },
      title = if (!is.na(title_slot) && title_slot %in% names(row)) {
        as.character(row[[title_slot]][[1L]])
      } else {
        NA_character_
      }
    )
  }
  evidence$source_class <- vapply(
    evidence$source_id,
    \(.x) source_map[[as.character(.x)]]$class,
    character(1)
  )
  evidence$source_uri <- vapply(
    evidence$source_id,
    \(.x) source_map[[as.character(.x)]]$uri,
    character(1)
  )
  evidence$source_title <- vapply(
    evidence$source_id,
    \(.x) source_map[[as.character(.x)]]$title,
    character(1)
  )
  evidence
}

source_uri_slot <- function(contract) {
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

source_title_slot <- function(contract) {
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

#' Retrieve narrative and semantic claims about an entity
#'
#' Narrative statements are discovered through `primary_subject` and generated
#' `about` relations. Semantic statements are discovered through `subject` and
#' `object_entity`. Narrative statements are never assigned fabricated
#' predicates.
#'
#' @param store An initialized `kg_store`.
#' @param entity_id One internal entity identifier.
#' @param predicate Optional semantic predicate restriction.
#' @param include_superseded Whether non-active statements may be returned.
#' @param limit Maximum statements to return.
#'
#' @return A bounded data frame. `qualifiers`, ordinary `attributes`, and
#'   hydrated `evidence` are separate list-columns.
#' @export
kg_claims <- function(
  store,
  entity_id,
  predicate = NULL,
  include_superseded = FALSE,
  limit = 100
) {
  validate_retrieval_store(store)
  entity_id <- validate_scalar_text(
    entity_id,
    "entity_id",
    condition = abort_reference_error
  )
  predicate <- validate_optional_scalar_text(predicate, "predicate")
  include_superseded <- validate_include_superseded(include_superseded)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$claims
  )
  rows <- list()
  if (is.null(predicate)) {
    for (record_class in statement_classes(store, "narrative")) {
      rows[[record_class]] <- narrative_claim_rows(
        store,
        record_class,
        entity_id,
        include_superseded,
        limit
      )
    }
  }
  for (record_class in statement_classes(store, "semantic")) {
    rows[[record_class]] <- semantic_claim_rows(
      store,
      record_class,
      entity_id,
      predicate,
      include_superseded,
      limit
    )
  }
  rows <- Filter(\(.x) nrow(.x) > 0L, rows)
  if (length(rows) == 0L) {
    return(empty_claim_result(store, limit))
  }
  raw <- bind_public_rows(rows)
  raw <- raw[
    order(raw$statement_shape, raw$class, raw$id),
    ,
    drop = FALSE
  ]
  claim_truncated <- nrow(raw) > limit
  if (claim_truncated) {
    raw <- raw[seq_len(limit), , drop = FALSE]
  }
  evidence_limit <- max(
    1L,
    min(
      100L,
      floor(graft_retrieval_limits$evidence / max(1L, nrow(raw)))
    )
  )
  result_rows <- lapply(seq_len(nrow(raw)), function(index) {
    claim_result_row(
      store,
      raw$class[[index]],
      raw[index, , drop = FALSE],
      evidence_limit
    )
  })
  result <- bind_public_rows(result_rows)
  rownames(result) <- NULL
  result <- bounded_data_frame(result, store, limit, claim_truncated)
  attr(result, "evidence_limit_per_statement") <- evidence_limit
  attr(result, "evidence_truncated") <- any(vapply(
    result$evidence,
    \(.x) isTRUE(attr(.x, "truncated")),
    logical(1)
  ))
  result
}

validate_include_superseded <- function(include_superseded) {
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

narrative_claim_rows <- function(
  store,
  record_class,
  entity_id,
  include_superseded,
  limit
) {
  contract <- validate_public_class(
    store,
    record_class,
    roles = "statement"
  )
  fields <- public_slot_names(contract)
  references <- character()
  params <- list()
  if ("primary_subject" %in% fields) {
    references <- c(
      references,
      paste0(
        quote_identifier(
          store$connection,
          slot_column(contract, "primary_subject")
        ),
        " = ?"
      )
    )
    params <- c(params, list(entity_id))
  }
  about_relation <- manifest_relation_for_slot(
    store,
    record_class,
    "about"
  )
  if (!is.null(about_relation)) {
    references <- c(
      references,
      paste0(
        "EXISTS (SELECT 1 FROM ",
        quote_identifier(
          store$connection,
          scalar_character(about_relation$table)
        ),
        " AS graft_about WHERE graft_about.",
        quote_identifier(store$connection, "subject"),
        " = ",
        quote_identifier(store$connection, scalar_character(contract$table)),
        ".",
        quote_identifier(store$connection, slot_column(contract, "id")),
        " AND graft_about.",
        quote_identifier(store$connection, "object"),
        " = ?)"
      )
    )
    params <- c(params, list(entity_id))
  }
  if (length(references) == 0L) {
    return(data.frame())
  }
  statement_query(
    store,
    contract,
    record_class,
    shape = "narrative",
    where = paste0("(", paste(references, collapse = " OR "), ")"),
    params = params,
    include_superseded = include_superseded,
    limit = limit
  )
}

semantic_claim_rows <- function(
  store,
  record_class,
  entity_id,
  predicate,
  include_superseded,
  limit
) {
  contract <- validate_public_class(
    store,
    record_class,
    roles = "statement"
  )
  fields <- public_slot_names(contract)
  references <- character()
  params <- list()
  for (field in intersect(c("subject", "object_entity"), fields)) {
    references <- c(
      references,
      paste0(
        quote_identifier(store$connection, slot_column(contract, field)),
        " = ?"
      )
    )
    params <- c(params, list(entity_id))
  }
  if (length(references) == 0L) {
    return(data.frame())
  }
  where <- paste0("(", paste(references, collapse = " OR "), ")")
  if (!is.null(predicate)) {
    if (!"predicate" %in% fields) {
      return(data.frame())
    }
    where <- paste0(
      where,
      " AND ",
      quote_identifier(store$connection, slot_column(contract, "predicate")),
      " = ?"
    )
    params <- c(params, list(predicate))
  }
  statement_query(
    store,
    contract,
    record_class,
    shape = "semantic",
    where = where,
    params = params,
    include_superseded = include_superseded,
    limit = limit
  )
}

statement_query <- function(
  store,
  contract,
  record_class,
  shape,
  where,
  params,
  include_superseded,
  limit
) {
  fields <- public_slot_names(contract)
  selected <- vapply(
    fields,
    function(slot) {
      column <- quote_identifier(
        store$connection,
        slot_column(contract, slot)
      )
      if (identical(slot, slot_column(contract, slot))) {
        return(column)
      }
      paste0(
        column,
        " AS ",
        quote_identifier(store$connection, slot)
      )
    },
    character(1)
  )
  if (!include_superseded) {
    where <- paste0(
      "(",
      where,
      ") AND ",
      is_active_statement_sql(store, contract)
    )
  }
  sql <- paste0(
    "SELECT ",
    as.character(DBI::dbQuoteString(store$connection, record_class)),
    " AS class, ",
    as.character(DBI::dbQuoteString(store$connection, shape)),
    " AS statement_shape, ",
    paste(selected, collapse = ", "),
    " FROM ",
    quote_identifier(store$connection, scalar_character(contract$table)),
    " WHERE ",
    where,
    " ORDER BY ",
    quote_identifier(store$connection, slot_column(contract, "id")),
    " LIMIT ",
    limit + 1L
  )
  with_duckdb_error(
    "claim_records",
    DBI::dbGetQuery(store$connection, sql, params = params)
  )
}

claim_result_row <- function(
  store,
  record_class,
  raw,
  evidence_limit,
  include_evidence = TRUE
) {
  contract <- validate_public_class(
    store,
    record_class,
    roles = "statement"
  )
  record <- hydrate_public_record(store, record_class, raw)
  core <- c(
    "id",
    "polarity",
    "confidence",
    "status",
    "valid_from",
    "valid_to",
    "asserted_at",
    "superseded_by",
    "created_at",
    "updated_at"
  )
  shape_fields <- if (
    identical(scalar_character(contract$statement_shape), "narrative")
  ) {
    c("statement_text", "primary_subject", "about")
  } else {
    c(
      "subject",
      "predicate",
      "object_entity",
      "object_value",
      "object_datatype",
      "derived_from_statement"
    )
  }
  qualifiers <- empty_character(contract$qualifier_slots)
  public <- names(record)
  attribute_fields <- setdiff(
    public,
    c(core, shape_fields, qualifiers)
  )
  ordinary_attributes <- record[intersect(attribute_fields, names(record))]
  qualifier_values <- record[intersect(qualifiers, names(record))]
  scalar <- function(field, default = NA_character_) {
    value <- record[[field]]
    if (is.null(value) || length(value) == 0L) {
      return(default)
    }
    value[[1L]]
  }
  data <- data.frame(
    id = as.character(scalar("id")),
    class = record_class,
    statement_shape = scalar_character(contract$statement_shape),
    statement_text = as.character(scalar("statement_text")),
    primary_subject = as.character(scalar("primary_subject")),
    subject = as.character(scalar("subject")),
    predicate = as.character(scalar("predicate")),
    object_entity = as.character(scalar("object_entity")),
    object_value = as.character(scalar("object_value")),
    object_datatype = as.character(scalar("object_datatype")),
    polarity = as.character(scalar("polarity")),
    confidence = suppressWarnings(as.numeric(scalar("confidence", NA_real_))),
    status = as.character(scalar("status")),
    valid_from = as.POSIXct(
      scalar("valid_from", as.POSIXct(NA_real_, origin = "1970-01-01")),
      origin = "1970-01-01",
      tz = "UTC"
    ),
    valid_to = as.POSIXct(
      scalar("valid_to", as.POSIXct(NA_real_, origin = "1970-01-01")),
      origin = "1970-01-01",
      tz = "UTC"
    ),
    asserted_at = as.POSIXct(
      scalar("asserted_at", as.POSIXct(NA_real_, origin = "1970-01-01")),
      origin = "1970-01-01",
      tz = "UTC"
    ),
    superseded_by = as.character(scalar("superseded_by")),
    derived_from_statement = as.character(scalar("derived_from_statement")),
    stringsAsFactors = FALSE
  )
  about <- record$about
  if (is.null(about)) {
    about <- character()
  }
  data$about <- I(list(about))
  data$record <- I(list(record))
  data$qualifiers <- I(list(qualifier_values))
  data$attributes <- I(list(ordinary_attributes))
  evidence <- if (include_evidence) {
    kg_evidence(
      store,
      data$id[[1L]],
      limit = evidence_limit
    )
  } else {
    empty_evidence_result(store, evidence_limit)
  }
  data$evidence <- I(list(evidence))
  data
}

empty_claim_result <- function(store, limit) {
  data <- data.frame(
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
    valid_from = as.POSIXct(
      numeric(),
      origin = "1970-01-01",
      tz = "UTC"
    ),
    valid_to = as.POSIXct(
      numeric(),
      origin = "1970-01-01",
      tz = "UTC"
    ),
    asserted_at = as.POSIXct(
      numeric(),
      origin = "1970-01-01",
      tz = "UTC"
    ),
    superseded_by = character(),
    derived_from_statement = character(),
    stringsAsFactors = FALSE
  )
  data$about <- I(list())
  data$record <- I(list())
  data$qualifiers <- I(list())
  data$attributes <- I(list())
  data$evidence <- I(list())
  bounded_data_frame(data, store, limit, FALSE)
}

evidence_related_to_record <- function(
  store,
  id,
  record_class,
  claims,
  limit
) {
  contract <- validate_public_class(store, record_class)
  role <- scalar_character(contract$role)
  if (identical(role, "statement")) {
    return(kg_evidence(store, id, limit = limit))
  }
  if (identical(role, "source")) {
    return(evidence_rows(
      store,
      field = "source_id",
      value = id,
      limit = limit
    ))
  }
  if (is.null(claims) || nrow(claims) == 0L) {
    return(empty_evidence_result(store, limit))
  }
  evidence <- bind_public_rows(unclass(claims$evidence))
  if (nrow(evidence) == 0L) {
    return(empty_evidence_result(store, limit))
  }
  evidence <- evidence[
    !duplicated(paste(evidence$evidence_class, evidence$id)),
    ,
    drop = FALSE
  ]
  evidence <- evidence[
    order(evidence$evidence_class, evidence$id),
    ,
    drop = FALSE
  ]
  evidence <- trim_bounded_rows(evidence, store, limit)
  if (isTRUE(attr(claims, "truncated"))) {
    attr(evidence, "truncated") <- TRUE
  }
  evidence
}

empty_evidence_result <- function(store, limit) {
  data <- data.frame(
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
  bounded_data_frame(data, store, limit, FALSE)
}

#' Group candidate competing claims
#'
#' The result contains comparison sets only. It preserves statement wording,
#' status, polarity, time fields, qualifiers, and attributes without deciding
#' whether any pair is contradictory.
#'
#' @param store An initialized `kg_store`.
#' @param class One concrete statement class.
#' @param key One or more public scalar grouping fields.
#' @param include_superseded Whether non-active statements may be candidates.
#' @param limit Maximum comparison groups to return.
#'
#' @return A bounded data frame with one list-column of candidate records.
#' @export
kg_competing_claims <- function(
  store,
  class = "Claim",
  key = c("primary_subject"),
  include_superseded = FALSE,
  limit = 100
) {
  contract <- validate_public_class(store, class, roles = "statement")
  include_superseded <- validate_include_superseded(include_superseded)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$competing_claims
  )
  key <- validate_select_fields(contract, key)
  key_columns <- vapply(
    key,
    \(.x) slot_column(contract, .x),
    character(1)
  )
  selected <- vapply(
    seq_along(key),
    function(index) {
      column <- quote_identifier(store$connection, key_columns[[index]])
      if (identical(key[[index]], key_columns[[index]])) {
        return(column)
      }
      paste0(
        column,
        " AS ",
        quote_identifier(store$connection, key[[index]])
      )
    },
    character(1)
  )
  group_conditions <- paste0(
    quote_identifier(store$connection, key_columns),
    " IS NOT NULL"
  )
  if (!include_superseded) {
    group_conditions <- c(
      group_conditions,
      is_active_statement_sql(store, contract)
    )
  }
  where <- paste0(
    " WHERE ",
    paste(group_conditions, collapse = " AND ")
  )
  group_columns <- paste(
    quote_identifier(store$connection, key_columns),
    collapse = ", "
  )
  ordering <- paste(
    quote_identifier(store$connection, key_columns),
    collapse = ", "
  )
  sql <- paste0(
    "SELECT ",
    paste(selected, collapse = ", "),
    ", COUNT(*) AS candidate_count FROM ",
    quote_identifier(store$connection, scalar_character(contract$table)),
    where,
    " GROUP BY ",
    group_columns,
    " HAVING COUNT(*) > 1 ORDER BY ",
    ordering,
    " LIMIT ",
    limit + 1L
  )
  groups <- with_duckdb_error(
    "competing_claim_groups",
    DBI::dbGetQuery(store$connection, sql)
  )
  truncated <- nrow(groups) > limit
  if (truncated) {
    groups <- groups[seq_len(limit), , drop = FALSE]
  }
  if (nrow(groups) == 0L) {
    result <- data.frame(
      group_id = character(),
      class = character(),
      candidate_count = integer(),
      returned_count = integer(),
      candidates_truncated = logical(),
      stringsAsFactors = FALSE
    )
    result$key <- I(list())
    result$claims <- I(list())
    return(bounded_data_frame(result, store, limit, FALSE))
  }
  remaining_candidates <- graft_retrieval_limits$competing_claims
  result_rows <- list()
  for (index in seq_len(nrow(groups))) {
    if (remaining_candidates < 2L) {
      truncated <- TRUE
      break
    }
    values <- as.list(groups[index, key, drop = FALSE])
    candidate_count <- as.integer(groups$candidate_count[[index]])
    candidate_limit <- min(candidate_count, remaining_candidates)
    candidates <- competing_group_rows(
      store,
      class,
      contract,
      values,
      include_superseded,
      candidate_limit
    )
    remaining_candidates <- remaining_candidates - nrow(candidates)
    data <- data.frame(
      group_id = paste0(
        "sha256:",
        digest::digest(
          canonical_identity_value(values),
          algo = "sha256",
          serialize = FALSE
        )
      ),
      class = class,
      candidate_count = candidate_count,
      returned_count = nrow(candidates),
      candidates_truncated = candidate_count > nrow(candidates),
      stringsAsFactors = FALSE
    )
    data$key <- I(list(values))
    data$claims <- I(list(candidates))
    result_rows[[length(result_rows) + 1L]] <- data
  }
  result <- bind_public_rows(result_rows)
  if (any(result$candidates_truncated)) {
    truncated <- TRUE
  }
  bounded_data_frame(result, store, limit, truncated)
}

competing_group_rows <- function(
  store,
  class,
  contract,
  key_values,
  include_superseded,
  candidate_limit
) {
  filters <- lapply(names(key_values), function(field) {
    value <- key_values[[field]][[1L]]
    if (is.na(value)) {
      return(list(
        sql = paste0(
          quote_identifier(
            store$connection,
            slot_column(contract, field)
          ),
          " IS NULL"
        ),
        params = list()
      ))
    }
    list(
      sql = paste0(
        quote_identifier(
          store$connection,
          slot_column(contract, field)
        ),
        " = ?"
      ),
      params = list(value)
    )
  })
  fields <- public_slot_names(contract)
  selected <- vapply(
    fields,
    function(field) {
      column <- quote_identifier(
        store$connection,
        slot_column(contract, field)
      )
      if (identical(field, slot_column(contract, field))) {
        return(column)
      }
      paste0(
        column,
        " AS ",
        quote_identifier(store$connection, field)
      )
    },
    character(1)
  )
  where <- paste(vapply(filters, `[[`, "", "sql"), collapse = " AND ")
  if (!include_superseded) {
    where <- paste0(
      where,
      " AND ",
      is_active_statement_sql(store, contract)
    )
  }
  sql <- paste0(
    "SELECT ",
    paste(selected, collapse = ", "),
    " FROM ",
    quote_identifier(store$connection, scalar_character(contract$table)),
    " WHERE ",
    where,
    " ORDER BY ",
    quote_identifier(store$connection, slot_column(contract, "id")),
    " LIMIT ",
    candidate_limit + 1L
  )
  params <- unlist(
    lapply(filters, `[[`, "params"),
    recursive = FALSE,
    use.names = FALSE
  )
  raw <- with_duckdb_error(
    "competing_claim_candidates",
    DBI::dbGetQuery(store$connection, sql, params = params)
  )
  if (nrow(raw) > candidate_limit) {
    raw <- raw[seq_len(candidate_limit), , drop = FALSE]
  }
  rows <- lapply(seq_len(nrow(raw)), function(index) {
    claim_result_row(
      store,
      class,
      data.frame(
        class = class,
        statement_shape = scalar_character(contract$statement_shape),
        raw[index, , drop = FALSE],
        stringsAsFactors = FALSE,
        check.names = FALSE
      ),
      evidence_limit = 1L,
      include_evidence = FALSE
    )
  })
  bind_public_rows(rows)
}
