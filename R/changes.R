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
#'
#' @return A bounded data frame ordered by class and record ID with columns
#'   `class`, `record_id`, `action` (`"insert"` when the record first appeared
#'   inside the window, otherwise `"update"`), `revisions` (accepted revisions
#'   inside the window), `changed_fields` (a list-column with the union of
#'   public fields changed inside the window), and the `revision_id`,
#'   `revision_number`, `batch_id`, `commit_order`, `committed_at`, and public
#'   `record` list-column of the latest revision at `until`. Attributes
#'   `since_commit_order`, `since_batch_id`, `until_commit_order`, and
#'   `until_batch_id` identify the compared boundaries.
#' @export
graft_changes <- function(
  store,
  since = NULL,
  until = NULL,
  class = NULL,
  limit = 1000L
) {
  store <- as_graft_read_store_internal(store, "store")
  validate_graft_retrieval(store)
  limit <- validate_result_limit(
    limit,
    hard_limit = graft_retrieval_limits$changes
  )
  classes <- validate_changes_classes(store, class)
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
    limit
  )
  result <- summarize_changed_revisions(rows, store, limit)
  attr(result, "since_commit_order") <- lower$commit_order
  attr(result, "since_batch_id") <- lower$batch_id
  attr(result, "until_commit_order") <- upper$commit_order
  attr(result, "until_batch_id") <- upper$batch_id
  result
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
    metadata <- read_store_metadata(store$connection)
    if (!identical(value@store_id, scalar_character(metadata$store_id))) {
      abort_snapshot_error(
        "graft_snapshot_store_error",
        paste0("`", argument, "` was captured from a different store."),
        argument = argument,
        snapshot_store_id = value@store_id,
        store_id = scalar_character(metadata$store_id)
      )
    }
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

query_changed_revisions <- function(store, lower, upper, classes, limit) {
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
  window_sql <- paste0(
    " INNER JOIN ",
    batches,
    " b ON r.batch_id = b.batch_id WHERE b.status = 'committed' ",
    "AND r.commit_order > ? AND r.commit_order <= ?",
    class_sql
  )
  window_params <- c(list(lower, upper), class_params)
  sql <- paste0(
    "SELECT r.revision_id, r.record_id, r.class, r.batch_id, ",
    "r.schema_build_digest, r.revision_number, r.operation, ",
    "r.payload_json, r.content_digest, r.changed_fields_json, ",
    "r.commit_order, b.committed_at FROM ",
    revisions,
    " r INNER JOIN (SELECT r.class, r.record_id FROM ",
    revisions,
    " r",
    window_sql,
    " GROUP BY r.class, r.record_id ORDER BY r.class, r.record_id LIMIT ",
    limit + 1L,
    ") k ON k.class = r.class AND k.record_id = r.record_id",
    window_sql,
    " ORDER BY r.class, r.record_id, r.commit_order, r.revision_number, ",
    "r.revision_id"
  )
  with_duckdb_error(
    "graft_changes",
    DBI::dbGetQuery(
      connection,
      sql,
      params = c(window_params, window_params)
    )
  )
}

summarize_changed_revisions <- function(rows, store, limit) {
  keys <- paste(rows$class, rows$record_id, sep = "")
  groups <- unique(keys)
  truncated <- length(groups) > limit
  if (truncated) {
    groups <- groups[seq_len(limit)]
    keep <- keys %in% groups
    rows <- rows[keep, , drop = FALSE]
    keys <- keys[keep]
  }
  schemas <- historical_schemas(store, unique(rows$schema_build_digest))
  n <- length(groups)
  out_class <- character(n)
  out_record_id <- character(n)
  out_action <- character(n)
  out_revisions <- integer(n)
  out_changed <- vector("list", n)
  out_revision_id <- character(n)
  out_revision_number <- numeric(n)
  out_batch_id <- character(n)
  out_commit_order <- numeric(n)
  out_committed_at <- rows$committed_at[rep(NA_integer_, n)]
  out_record <- vector("list", n)
  for (index in seq_len(n)) {
    group <- rows[keys == groups[[index]], , drop = FALSE]
    latest <- group[nrow(group), , drop = FALSE]
    contract_for <- function(digest) {
      contract <- schemas[[digest]]$manifest$classes[[latest$class[[1L]]]]
      if (is.null(contract)) {
        abort_backend_error(
          "A revision class is absent from its historical manifest.",
          operation = "graft_changes",
          record_id = latest$record_id[[1L]],
          record_class = latest$class[[1L]],
          build_digest = digest
        )
      }
      contract
    }
    changed <- character()
    for (row in seq_len(nrow(group))) {
      changed <- union(
        changed,
        public_changed_fields(
          group$changed_fields_json[[row]],
          contract_for(group$schema_build_digest[[row]])
        )
      )
    }
    out_class[[index]] <- latest$class[[1L]]
    out_record_id[[index]] <- latest$record_id[[1L]]
    out_action[[index]] <- if (any(group$revision_number == 1)) {
      "insert"
    } else {
      "update"
    }
    out_revisions[[index]] <- nrow(group)
    out_changed[[index]] <- sort(changed, method = "radix")
    out_revision_id[[index]] <- latest$revision_id[[1L]]
    out_revision_number[[index]] <- as.numeric(latest$revision_number[[1L]])
    out_batch_id[[index]] <- latest$batch_id[[1L]]
    out_commit_order[[index]] <- as.numeric(latest$commit_order[[1L]])
    out_committed_at[[index]] <- latest$committed_at[[1L]]
    out_record[[index]] <- validated_public_revision_record(
      latest$payload_json[[1L]],
      latest$content_digest[[1L]],
      contract_for(latest$schema_build_digest[[1L]]),
      record_id = latest$record_id[[1L]],
      revision_id = latest$revision_id[[1L]]
    )
  }
  result <- data.frame(
    class = out_class,
    record_id = out_record_id,
    action = out_action,
    revisions = out_revisions,
    revision_id = out_revision_id,
    revision_number = out_revision_number,
    batch_id = out_batch_id,
    commit_order = out_commit_order,
    stringsAsFactors = FALSE
  )
  result$committed_at <- out_committed_at
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
