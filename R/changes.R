# Store-wide accepted changes between two committed boundaries

#' List accepted changes between two boundaries
#'
#' `graft_changes()` compares accepted knowledge at two committed boundaries
#' and returns one row per record whose accepted revision differs between
#' them. It answers "what was accepted since this snapshot" for a whole store
#' in one bounded table, where [graft_history()] answers the same question for
#' one record.
#'
#' Each boundary may be a [graft_snapshot()] captured from the same store, a
#' committed batch ID, or a scalar `POSIXt` time. `since` defaults to the
#' store's origin, so every accepted record is reported as an insert. `until`
#' defaults to the store's current head, or to the pinned boundary of a
#' `GraftView`; a view rejects any later boundary.
#'
#' @param store An initialized `GraftStore` or immutable `GraftView`.
#' @param since Optional lower boundary, exclusive.
#' @param until Optional upper boundary, inclusive.
#' @param class Optional concrete class restriction.
#' @param limit Maximum changed records to return, up to the package hard
#'   limit.
#' @param record_ids Optional character vector of at most 5,000 record IDs.
#'   Restricts changes before applying `limit`, intersecting any `class`
#'   restriction. `NULL` selects all IDs; `character()` selects none.
#'   Duplicate IDs are ignored. Unknown IDs return no rows. This selects
#'   identities, including delete tombstones, without following references
#'   or granting access. An empty change result does not prove that the
#'   selected records exist or that a saved reuse basis is complete.
#'
#' @return A bounded data frame ordered by class and record ID with columns
#'   `class`, `record_id`, `action` (`"insert"` when the record had no
#'   accepted revision at `since`, `"delete"` when its latest revision at
#'   `until` is a deletion, otherwise `"update"`), `revisions`
#'   (accepted revisions inside the window), `changed_fields` (a list-column
#'   with the public fields whose values differ between the record's accepted
#'   revision at `since` and at `until`), and the `revision_id`,
#'   `revision_number`, `batch_id`, `commit_order`, `committed_at`, and public
#'   `record` list-column of the latest revision at `until` (`NULL` for a
#'   deletion, whose `changed_fields` are empty). Only the two
#'   boundary revisions of each changed record are read, so a long revision
#'   history does not grow the result. Attributes `since_commit_order`,
#'   `since_batch_id`, `until_commit_order`, and `until_batch_id` identify the
#'   compared boundaries.
#' @export
graft_changes <- function(
  store,
  since = NULL,
  until = NULL,
  class = NULL,
  limit = 1000L,
  record_ids = NULL
) {
  store <- as_graft_read_store_internal(store, "store")
  validate_graft_retrieval(store)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$changes
  )
  classes <- validate_changes_classes(store, class)
  record_ids <- validate_changes_record_ids(record_ids)
  lower <- resolve_changes_boundary(store, since, "since", origin = TRUE)
  upper <- resolve_changes_boundary(store, until, "until", origin = FALSE)
  if (lower$commit_order > upper$commit_order) {
    abort_validation_error(
      "`since` must not be later than `until`.",
      field = "since",
      rule = "ordered_boundaries",
      observed_value = list(
        since_commit_order = lower$commit_order,
        until_commit_order = upper$commit_order
      )
    )
  }
  rows <- query_changed_revisions(
    store,
    lower$commit_order,
    upper$commit_order,
    classes,
    limit,
    record_ids
  )
  result <- summarize_changed_revisions(rows, store, limit)
  attr(result, "since_commit_order") <- lower$commit_order
  attr(result, "since_batch_id") <- lower$batch_id
  attr(result, "until_commit_order") <- upper$commit_order
  attr(result, "until_batch_id") <- upper$batch_id
  result
}

validate_changes_record_ids <- function(record_ids) {
  if (is.null(record_ids)) {
    return(NULL)
  }
  if (
    !is.character(record_ids) ||
      !is.null(dim(record_ids)) ||
      anyNA(record_ids) ||
      !all(nzchar(record_ids))
  ) {
    abort_validation_error(
      "`record_ids` must be a character vector of non-empty, non-missing IDs.",
      field = "record_ids",
      rule = "record_ids"
    )
  }
  if (length(record_ids) > graft_retrieval_limits$changes) {
    abort_limit_error(
      "`record_ids` must contain at most 5,000 IDs.",
      field = "record_ids",
      requested_limit = length(record_ids),
      hard_limit = graft_retrieval_limits$changes
    )
  }
  unique(unname(record_ids))
}

validate_changes_classes <- function(store, class) {
  if (is.null(class)) {
    return(NULL)
  }
  known <- public_class_names(store)
  if (
    !is.character(class) ||
      length(class) == 0L ||
      anyNA(class) ||
      !all(class %in% known)
  ) {
    abort_validation_error(
      "`class` must name concrete public classes in the store schema.",
      field = "class",
      rule = "known_public_class",
      observed_value = class
    )
  }
  unique(class)
}

readable_changes_boundary <- function(store) {
  boundary <- resolve_effective_history_boundary(store, NULL)
  if (!is.null(boundary$commit_order)) {
    return(list(
      commit_order = as.numeric(boundary$commit_order),
      batch_id = boundary$batch_id
    ))
  }
  row <- with_duckdb_error(
    "graft_changes",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT batch_id, commit_order FROM ",
        quote_identifier(store$connection, "_graft_batches"),
        " WHERE status = 'committed' ORDER BY commit_order DESC, ",
        "batch_id ASC LIMIT 1"
      )
    )
  )
  if (nrow(row) == 0L) {
    return(list(commit_order = 0, batch_id = NA_character_))
  }
  list(
    commit_order = as.numeric(row$commit_order[[1L]]),
    batch_id = row$batch_id[[1L]]
  )
}

resolve_changes_boundary <- function(store, value, argument, origin) {
  readable <- readable_changes_boundary(store)
  if (is.null(value)) {
    if (origin) {
      return(list(commit_order = 0, batch_id = NA_character_))
    }
    return(readable)
  }
  if (S7::S7_inherits(value, GraftSnapshot)) {
    value <- as_graft_snapshot(value, argument)
    # The same validation graft_at() applies: store identity, format, and the
    # exact commit-order to batch and timestamp mapping, so a snapshot from a
    # divergent copy of the database cannot select the wrong boundary.
    source <- if (is_graft_snapshot_backend(store)) {
      store$source_backend
    } else {
      store
    }
    validate_graft_snapshot_mapping(source, value)
    if (value@commit_order > readable$commit_order) {
      abort_snapshot_error(
        c("graft_snapshot_boundary_error", "graft_history_boundary_error"),
        paste0("`", argument, "` is later than the readable boundary."),
        argument = argument,
        requested_commit_order = value@commit_order,
        readable_commit_order = readable$commit_order
      )
    }
    return(list(
      commit_order = as.numeric(value@commit_order),
      batch_id = value@batch_id
    ))
  }
  boundary <- resolve_effective_history_boundary(store, value)
  batch_id <- boundary$batch_id
  list(
    commit_order = as.numeric(boundary$commit_order),
    batch_id = if (is.null(batch_id)) NA_character_ else batch_id
  )
}

query_changed_revisions <- function(
  store,
  lower,
  upper,
  classes,
  limit,
  record_ids
) {
  connection <- store$connection
  revisions <- quote_identifier(connection, "_graft_record_revisions")
  batches <- quote_identifier(connection, "_graft_batches")
  class_sql <- ""
  class_params <- list()
  if (!is.null(classes)) {
    class_sql <- paste0(
      " AND r.class IN (",
      paste(rep("?", length(classes)), collapse = ", "),
      ")"
    )
    class_params <- as.list(classes)
  }
  id_sql <- ""
  id_params <- list()
  if (!is.null(record_ids)) {
    id_sql <- if (length(record_ids) == 0L) {
      " AND FALSE"
    } else {
      paste0(
        " AND r.record_id IN (",
        paste(rep("?", length(record_ids)), collapse = ", "),
        ")"
      )
    }
    id_params <- as.list(record_ids)
  }
  committed <- paste0(
    " INNER JOIN ",
    batches,
    " b ON r.batch_id = b.batch_id WHERE b.status = 'committed'"
  )
  window_sql <- paste0(
    committed,
    " AND r.commit_order > ? AND r.commit_order <= ?",
    class_sql,
    id_sql
  )
  window_params <- c(list(lower, upper), class_params, id_params)
  order_sql <- "ORDER BY r.commit_order DESC, r.revision_number DESC, r.revision_id DESC"
  # Changed keys are bounded first; only the aggregate, the latest revision at
  # `until`, and the latest revision at `since` are then read for those keys.
  sql <- paste0(
    "WITH changed AS (SELECT r.class, r.record_id, COUNT(*) AS revisions FROM ",
    revisions,
    " r",
    window_sql,
    " GROUP BY r.class, r.record_id ORDER BY r.class, r.record_id LIMIT ",
    limit + 1L,
    "), latest AS (SELECT * FROM (SELECT r.revision_id, r.record_id, r.class, ",
    "r.batch_id, r.schema_build_digest, r.revision_number, r.operation, ",
    "r.payload_json, r.content_digest, r.commit_order, b.committed_at, ",
    "ROW_NUMBER() OVER (PARTITION BY r.class, r.record_id ",
    order_sql,
    ") AS rn FROM ",
    revisions,
    " r INNER JOIN changed k ON k.class = r.class AND k.record_id = r.record_id",
    window_sql,
    ") WHERE rn = 1), prior AS (SELECT * FROM (SELECT r.record_id, r.class, ",
    "r.schema_build_digest AS prior_schema_build_digest, ",
    "r.revision_id AS prior_revision_id, ",
    "r.content_digest AS prior_content_digest, ",
    "r.payload_json AS prior_payload_json, r.operation AS prior_operation, ",
    "ROW_NUMBER() OVER (PARTITION BY r.class, r.record_id ",
    order_sql,
    ") AS rn FROM ",
    revisions,
    " r INNER JOIN changed k ON k.class = r.class AND k.record_id = r.record_id",
    committed,
    " AND r.commit_order <= ?) WHERE rn = 1) ",
    "SELECT latest.*, changed.revisions, prior.prior_schema_build_digest, ",
    "prior.prior_revision_id, prior.prior_content_digest, ",
    "prior.prior_payload_json, prior.prior_operation FROM latest ",
    "INNER JOIN changed ON changed.class = latest.class ",
    "AND changed.record_id = latest.record_id ",
    "LEFT JOIN prior ON prior.class = latest.class ",
    "AND prior.record_id = latest.record_id ",
    "ORDER BY latest.class, latest.record_id"
  )
  with_duckdb_error(
    "graft_changes",
    DBI::dbGetQuery(
      connection,
      sql,
      params = c(window_params, window_params, list(lower))
    )
  )
}

summarize_changed_revisions <- function(rows, store, limit) {
  truncated <- nrow(rows) > limit
  if (truncated) {
    rows <- rows[seq_len(limit), , drop = FALSE]
  }
  digests <- unique(c(
    rows$schema_build_digest,
    rows$prior_schema_build_digest[!is.na(rows$prior_schema_build_digest)]
  ))
  schemas <- historical_schemas(store, digests)
  n <- nrow(rows)
  contract_for <- function(digest, record_class, record_id) {
    contract <- schemas[[digest]]$manifest$classes[[record_class]]
    if (is.null(contract)) {
      abort_backend_error(
        "A revision class is absent from its historical manifest.",
        operation = "graft_changes",
        record_id = record_id,
        record_class = record_class,
        build_digest = digest
      )
    }
    contract
  }
  out_action <- character(n)
  out_changed <- vector("list", n)
  out_record <- vector("list", n)
  for (index in seq_len(n)) {
    record_class <- rows$class[[index]]
    record_id <- rows$record_id[[index]]
    contract <- contract_for(
      rows$schema_build_digest[[index]],
      record_class,
      record_id
    )
    prior_json <- rows$prior_payload_json[[index]]
    if (!is.na(prior_json)) {
      # Every selected lower-boundary revision is validated against its own
      # historical contract and stored digest, deletions included; only a
      # live prior takes part in the field diff.
      validated_public_revision_record(
        prior_json,
        rows$prior_content_digest[[index]],
        contract_for(
          rows$prior_schema_build_digest[[index]],
          record_class,
          record_id
        ),
        record_id = record_id,
        revision_id = rows$prior_revision_id[[index]]
      )
    }
    has_prior <- !is.na(prior_json) &&
      !identical(rows$prior_operation[[index]], "delete")
    if (identical(rows$operation[[index]], "delete")) {
      # A removal is reported explicitly; the retained payload of a deleted
      # revision is validated like any other but never exposed as current
      # knowledge.
      validated_public_revision_record(
        rows$payload_json[[index]],
        rows$content_digest[[index]],
        contract,
        record_id = record_id,
        revision_id = rows$revision_id[[index]]
      )
      out_action[[index]] <- "delete"
      out_changed[[index]] <- character()
      out_record[index] <- list(NULL)
      next
    }
    payload <- parse_revision_payload(rows$payload_json[[index]])
    prior <- if (has_prior) parse_revision_payload(prior_json) else NULL
    out_action[[index]] <- if (has_prior) "update" else "insert"
    out_changed[[index]] <- public_changed_fields(
      changed_fields_json(logical_record_changed_fields(payload, prior)),
      contract
    )
    out_record[[index]] <- validated_public_revision_record(
      rows$payload_json[[index]],
      rows$content_digest[[index]],
      contract,
      record_id = record_id,
      revision_id = rows$revision_id[[index]]
    )
  }
  result <- data.frame(
    class = as.character(rows$class),
    record_id = as.character(rows$record_id),
    action = out_action,
    revisions = as.integer(rows$revisions),
    revision_id = as.character(rows$revision_id),
    revision_number = as.numeric(rows$revision_number),
    batch_id = as.character(rows$batch_id),
    commit_order = as.numeric(rows$commit_order),
    stringsAsFactors = FALSE
  )
  result$committed_at <- rows$committed_at
  result$changed_fields <- I(out_changed)
  result$record <- I(out_record)
  result <- result[
    c(
      "class",
      "record_id",
      "action",
      "revisions",
      "changed_fields",
      "revision_id",
      "revision_number",
      "batch_id",
      "commit_order",
      "committed_at",
      "record"
    )
  ]
  rownames(result) <- NULL
  bounded_data_frame(result, store, limit, truncated)
}
