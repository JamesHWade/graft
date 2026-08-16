graft_snapshot_schema_version <- 1L

GraftSnapshot <- S7::new_class(
  "GraftSnapshot",
  package = "graft",
  properties = list(
    schema_version = S7::new_property(
      S7::class_integer,
      getter = \(self) snapshot_data(self)$schema_version
    ),
    snapshot_id = S7::new_property(
      S7::class_character,
      getter = \(self) snapshot_data(self)$snapshot_id
    ),
    store_id = S7::new_property(
      S7::class_character,
      getter = \(self) snapshot_data(self)$store_id
    ),
    store_format_version = S7::new_property(
      S7::class_character,
      getter = \(self) snapshot_data(self)$store_format_version
    ),
    schema_build_digest = S7::new_property(
      S7::class_character,
      getter = \(self) snapshot_data(self)$schema_build_digest
    ),
    commit_order = S7::new_property(
      S7::class_double,
      getter = \(self) snapshot_data(self)$commit_order
    ),
    batch_id = S7::new_property(
      S7::class_character,
      getter = \(self) snapshot_data(self)$batch_id
    ),
    committed_at = S7::new_property(
      S7::class_character,
      getter = \(self) snapshot_data(self)$committed_at
    ),
    history_complete = S7::new_property(
      S7::class_logical,
      getter = \(self) snapshot_data(self)$history_complete
    )
  ),
  constructor = function(data) {
    S7::new_object(S7::S7_object(), .data = data)
  },
  validator = function(self) snapshot_validation_problem(snapshot_data(self))
)

GraftView <- S7::new_class(
  "GraftView",
  package = "graft",
  properties = list(
    snapshot_id = S7::new_property(
      S7::class_character,
      getter = \(self) graft_view_state(self)$snapshot@snapshot_id
    ),
    store_id = S7::new_property(
      S7::class_character,
      getter = \(self) graft_view_state(self)$snapshot@store_id
    ),
    schema_build_digest = S7::new_property(
      S7::class_character,
      getter = \(self) graft_view_state(self)$snapshot@schema_build_digest
    ),
    commit_order = S7::new_property(
      S7::class_double,
      getter = \(self) graft_view_state(self)$snapshot@commit_order
    ),
    batch_id = S7::new_property(
      S7::class_character,
      getter = \(self) graft_view_state(self)$snapshot@batch_id
    ),
    history_complete = S7::new_property(
      S7::class_logical,
      getter = \(self) graft_view_state(self)$snapshot@history_complete
    )
  ),
  constructor = function(state) {
    S7::new_object(S7::S7_object(), .state = state)
  },
  validator = function(self) validate_graft_view_s7(self)
)

#' Capture an immutable knowledge snapshot
#'
#' `graft_snapshot()` records the active schema build and latest committed
#' knowledge boundary of a Graft store. The returned value is serializable and
#' path-free: it contains no database connection, backend, or filesystem path.
#'
#' @param store An initialized, open `GraftStore`.
#'
#' @return An immutable, serializable `GraftSnapshot` S7 object.
#' @export
graft_snapshot <- function(store) {
  store <- as_graft_store_internal(store, "store")
  validate_initialized_store(store, write = FALSE, refresh = TRUE)
  row <- snapshot_capture_row(store)
  new_graft_snapshot(
    store_id = scalar_character(row$store_id),
    store_format_version = scalar_character(row$store_format_version),
    schema_build_digest = scalar_character(row$schema_build_digest),
    commit_order = snapshot_capture_order(row$commit_order),
    batch_id = scalar_character(row$batch_id),
    committed_at = snapshot_timestamp(row$committed_at),
    history_complete = snapshot_capture_history(row$history_complete)
  )
}

#' Open an immutable read view
#'
#' `graft_at()` binds a live store connection to a previously captured
#' [graft_snapshot()]. Reads through the returned view remain fixed at the
#' snapshot's committed boundary even after later commits. The view is
#' connection-bound and cannot outlive or close its underlying store.
#'
#' @param store An initialized, open `GraftStore` containing the snapshot.
#' @param snapshot A `GraftSnapshot` returned by [graft_snapshot()].
#'
#' @return A read-only, connection-bound `GraftView` S7 object.
#' @export
graft_at <- function(store, snapshot) {
  store_object <- store
  store <- as_graft_store_internal(store, "store")
  snapshot <- as_graft_snapshot(snapshot, "snapshot")
  schema <- validate_graft_snapshot_mapping(store, snapshot)
  GraftView(list(
    store = store_object,
    snapshot = snapshot,
    schema = schema
  ))
}

#' Recover the immutable snapshot retained by a view
#'
#' `graft_view_snapshot()` returns the exact path-free [graft_snapshot()]
#' retained by a `GraftView`. The returned snapshot is an isolated value:
#' changing its internal representation cannot change the view's pinned
#' boundary.
#'
#' This accessor reads only the snapshot already owned by the view. It does not
#' inspect the live store or advance the view to a later commit.
#'
#' @param view A `GraftView` returned by [graft_at()].
#'
#' @return An immutable, serializable `GraftSnapshot` S7 object.
#' @export
graft_view_snapshot <- function(view) {
  view <- as_graft_view(view, "view")
  snapshot <- graft_view_state(view)$snapshot
  data <- unserialize(serialize(snapshot_data(snapshot), NULL))
  GraftSnapshot(data)
}

new_graft_snapshot <- function(
  store_id,
  store_format_version,
  schema_build_digest,
  commit_order,
  batch_id,
  committed_at,
  history_complete
) {
  data <- list(
    schema_version = graft_snapshot_schema_version,
    snapshot_id = "",
    store_id = store_id,
    store_format_version = store_format_version,
    schema_build_digest = schema_build_digest,
    commit_order = as.numeric(commit_order),
    batch_id = batch_id,
    committed_at = committed_at,
    history_complete = history_complete
  )
  data$snapshot_id <- snapshot_digest(data)
  GraftSnapshot(data)
}

snapshot_field_names <- function() {
  c(
    "schema_version",
    "snapshot_id",
    "store_id",
    "store_format_version",
    "schema_build_digest",
    "commit_order",
    "batch_id",
    "committed_at",
    "history_complete"
  )
}

snapshot_identity_field_names <- function() {
  setdiff(snapshot_field_names(), "snapshot_id")
}

snapshot_data <- function(snapshot) {
  attr(snapshot, ".data", exact = TRUE)
}

snapshot_identity_data <- function(data) {
  data[snapshot_identity_field_names()]
}

snapshot_digest <- function(data) {
  graft_sha256(canonical_json(snapshot_identity_data(data)))
}

snapshot_validation_problem <- function(data) {
  if (
    !is.list(data) ||
      is.object(data) ||
      !identical(names(data), snapshot_field_names()) ||
      !all(vapply(
        data,
        \(value) is.atomic(value) && !is.object(value) && length(value) == 1L,
        logical(1)
      ))
  ) {
    return("internal snapshot fields are invalid")
  }
  if (!identical(data$schema_version, graft_snapshot_schema_version)) {
    return("@schema_version is not supported")
  }
  if (!is_graft_digest(data$snapshot_id)) {
    return("@snapshot_id must be a canonical SHA-256 value")
  }
  if (!is_nonempty_string(data$store_id)) {
    return("@store_id must be one non-empty string")
  }
  if (!is_nonempty_string(data$store_format_version)) {
    return("@store_format_version must be one non-empty string")
  }
  if (!is_graft_digest(data$schema_build_digest)) {
    return("@schema_build_digest must be a canonical SHA-256 value")
  }
  valid_order <- is.double(data$commit_order) &&
    !is.na(data$commit_order) &&
    is.finite(data$commit_order) &&
    data$commit_order >= 0 &&
    data$commit_order == floor(data$commit_order) &&
    data$commit_order < 2^53
  if (!valid_order) {
    return("@commit_order must be one non-negative exact whole number")
  }
  if (!is_optional_string(data$batch_id)) {
    return("@batch_id must be one non-empty string or missing")
  }
  if (!is_optional_string(data$committed_at)) {
    return("@committed_at must be one canonical UTC string or missing")
  }
  if (
    !is.na(data$committed_at) &&
      !is_canonical_snapshot_timestamp(data$committed_at)
  ) {
    return("@committed_at must use canonical microsecond UTC syntax")
  }
  if (!is_scalar_flag(data$history_complete)) {
    return("@history_complete must be TRUE or FALSE")
  }
  empty <- identical(data$commit_order, 0)
  if (empty && (!is.na(data$batch_id) || !is.na(data$committed_at))) {
    return("an empty snapshot must not name a batch or committed time")
  }
  if (!empty && (is.na(data$batch_id) || is.na(data$committed_at))) {
    return("a committed snapshot must name its batch and committed time")
  }
  expected <- tryCatch(snapshot_digest(data), error = \(error) NA_character_)
  if (!identical(data$snapshot_id, expected)) {
    return("@snapshot_id does not match the immutable snapshot fields")
  }
  NULL
}

is_canonical_snapshot_timestamp <- function(value) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !grepl(
        paste0(
          "^[0-9]{4}-[0-9]{2}-[0-9]{2}T",
          "[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$"
        ),
        value
      )
  ) {
    return(FALSE)
  }
  whole_seconds <- substr(value, 1L, 19L)
  parsed <- suppressWarnings(as.POSIXct(
    whole_seconds,
    format = "%Y-%m-%dT%H:%M:%S",
    tz = "UTC"
  ))
  !is.na(parsed) &&
    identical(
      format(parsed, "%Y-%m-%dT%H:%M:%S", tz = "UTC"),
      whole_seconds
    )
}

as_graft_snapshot <- function(x, arg = rlang::caller_arg(x)) {
  if (!S7::S7_inherits(x, GraftSnapshot)) {
    abort_snapshot_error(
      "graft_snapshot_invalid",
      paste0("`", arg, "` must be a GraftSnapshot object."),
      argument = arg
    )
  }
  data <- snapshot_data(x)
  shape_valid <- is.list(data) &&
    !is.object(data) &&
    identical(names(data), snapshot_field_names())
  expected <- if (shape_valid) {
    tryCatch(snapshot_digest(data), error = \(error) NA_character_)
  } else {
    NA_character_
  }
  observed <- if (shape_valid) data$snapshot_id else NA_character_
  if (shape_valid && !identical(observed, expected)) {
    abort_snapshot_error(
      "graft_snapshot_tampered",
      "The snapshot digest is invalid; create a new snapshot.",
      expected_snapshot_id = expected,
      observed_snapshot_id = observed
    )
  }
  error <- tryCatch(
    {
      S7::validate(x)
      NULL
    },
    error = identity
  )
  if (!is.null(error)) {
    abort_snapshot_error(
      "graft_snapshot_invalid",
      paste0("`", arg, "` is invalid; create a new snapshot."),
      argument = arg,
      parent = error
    )
  }
  x
}

abort_snapshot_error <- function(
  subclass,
  message,
  ...,
  call = rlang::caller_env()
) {
  graft_abort(
    c(subclass, "graft_snapshot_error"),
    message,
    ...,
    call = call
  )
}

snapshot_capture_row <- function(store) {
  row <- with_duckdb_error(
    "graft_snapshot",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT s.store_id, s.store_format_version, ",
        "s.active_build_digest AS schema_build_digest, ",
        "s.history_complete, b.batch_id, b.commit_order, ",
        "strftime(b.committed_at, '%Y-%m-%dT%H:%M:%S.%fZ') ",
        "AS committed_at ",
        "FROM ",
        quote_identifier(store$connection, "_graft_store"),
        " AS s LEFT JOIN (SELECT batch_id, commit_order, committed_at FROM ",
        quote_identifier(store$connection, "_graft_batches"),
        " WHERE status = 'committed' ORDER BY commit_order DESC, ",
        "batch_id ASC LIMIT 1) AS b ON TRUE"
      )
    )
  )
  if (nrow(row) != 1L) {
    abort_backend_error(
      "A snapshot requires exactly one store metadata row.",
      operation = "graft_snapshot",
      row_count = nrow(row)
    )
  }
  row
}

snapshot_capture_order <- function(value) {
  if (length(value) == 0L || is.na(value[[1L]])) {
    return(0)
  }
  order <- as.numeric(value[[1L]])
  if (
    !is.finite(order) ||
      order <= 0 ||
      order != floor(order) ||
      order >= 2^53
  ) {
    abort_backend_error(
      "The latest committed batch has an invalid commit order.",
      operation = "graft_snapshot",
      commit_order = order
    )
  }
  order
}

snapshot_capture_history <- function(value) {
  history_complete <- if (length(value) == 0L) NA else value[[1L]]
  if (!is_scalar_flag(history_complete)) {
    abort_backend_error(
      "The store has invalid history completeness metadata.",
      operation = "graft_snapshot",
      history_complete = history_complete
    )
  }
  history_complete
}

snapshot_timestamp <- function(value) {
  if (length(value) == 0L || is.na(value[[1L]])) {
    return(NA_character_)
  }
  timestamp <- value[[1L]]
  if (!is_canonical_snapshot_timestamp(timestamp)) {
    abort_backend_error(
      "A committed snapshot boundary has an invalid timestamp.",
      operation = "graft_snapshot"
    )
  }
  timestamp
}

validate_graft_snapshot_mapping <- function(store, snapshot) {
  validate_initialized_store(store, write = FALSE, refresh = TRUE)
  data <- snapshot_data(snapshot)
  row <- snapshot_mapping_row(store, data$commit_order)
  validate_snapshot_store_mapping(row, data)
  schemas <- snapshot_required_schemas(store, data)
  schemas[[data$schema_build_digest]]
}

snapshot_mapping_row <- function(store, commit_order) {
  row <- with_duckdb_error(
    "graft_at",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT s.store_id, s.store_format_version, s.history_complete, ",
        "latest.commit_order AS latest_commit_order, ",
        "boundary.batch_id AS boundary_batch_id, ",
        "strftime(boundary.committed_at, ",
        "'%Y-%m-%dT%H:%M:%S.%fZ') AS boundary_committed_at FROM ",
        quote_identifier(store$connection, "_graft_store"),
        " AS s LEFT JOIN (SELECT commit_order FROM ",
        quote_identifier(store$connection, "_graft_batches"),
        " WHERE status = 'committed' ORDER BY commit_order DESC, ",
        "batch_id ASC LIMIT 1) AS latest ON TRUE LEFT JOIN ",
        "(SELECT batch_id, committed_at FROM ",
        quote_identifier(store$connection, "_graft_batches"),
        " WHERE status = 'committed' AND commit_order = ?) AS boundary ",
        "ON TRUE"
      ),
      params = list(commit_order)
    )
  )
  if (nrow(row) != 1L) {
    abort_snapshot_error(
      "graft_snapshot_boundary_error",
      "The snapshot boundary does not resolve uniquely in the store.",
      boundary_commit_order = commit_order,
      row_count = nrow(row)
    )
  }
  row
}

validate_snapshot_store_mapping <- function(row, data) {
  observed_store_id <- scalar_character(row$store_id)
  observed_format <- scalar_character(row$store_format_version)
  observed_history <- if (length(row$history_complete) == 0L) {
    NA
  } else {
    row$history_complete[[1L]]
  }
  if (!identical(observed_store_id, data$store_id)) {
    abort_snapshot_error(
      "graft_snapshot_store_mismatch",
      "The snapshot belongs to a different Graft store.",
      expected_store_id = data$store_id,
      observed_store_id = observed_store_id
    )
  }
  if (
    !identical(observed_format, data$store_format_version) ||
      !identical(observed_history, data$history_complete)
  ) {
    abort_snapshot_error(
      "graft_snapshot_store_mismatch",
      "The store format or history coverage does not match the snapshot.",
      expected_store_format_version = data$store_format_version,
      observed_store_format_version = observed_format,
      expected_history_complete = data$history_complete,
      observed_history_complete = observed_history
    )
  }
  latest <- if (
    length(row$latest_commit_order) == 0L ||
      is.na(row$latest_commit_order[[1L]])
  ) {
    0
  } else {
    as.numeric(row$latest_commit_order[[1L]])
  }
  if (data$commit_order > latest) {
    abort_snapshot_error(
      "graft_snapshot_boundary_error",
      "The snapshot boundary is newer than the current store.",
      snapshot_commit_order = data$commit_order,
      latest_commit_order = latest
    )
  }
  if (identical(data$commit_order, 0)) {
    return(invisible(data))
  }
  observed_batch <- scalar_character(row$boundary_batch_id)
  observed_time <- snapshot_timestamp(row$boundary_committed_at)
  if (
    !identical(observed_batch, data$batch_id) ||
      !identical(observed_time, data$committed_at)
  ) {
    abort_snapshot_error(
      "graft_snapshot_boundary_error",
      "The snapshot boundary does not match its committed batch.",
      snapshot_commit_order = data$commit_order,
      expected_batch_id = data$batch_id,
      observed_batch_id = observed_batch,
      expected_committed_at = data$committed_at,
      observed_committed_at = observed_time
    )
  }
  invisible(data)
}

snapshot_required_schemas <- function(store, data) {
  batches <- with_duckdb_error(
    "graft_snapshot_schemas",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT DISTINCT schema_build_digest FROM ",
        quote_identifier(store$connection, "_graft_batches"),
        " WHERE status = 'committed' AND commit_order <= ? ",
        "ORDER BY schema_build_digest"
      ),
      params = list(data$commit_order)
    )
  )
  revisions <- with_duckdb_error(
    "graft_snapshot_schemas",
    DBI::dbGetQuery(
      store$connection,
      paste0(
        "SELECT DISTINCT r.schema_build_digest FROM ",
        quote_identifier(store$connection, "_graft_record_revisions"),
        " AS r INNER JOIN ",
        quote_identifier(store$connection, "_graft_batches"),
        " AS b ON r.batch_id = b.batch_id ",
        "WHERE b.status = 'committed' AND r.commit_order <= ? ",
        "ORDER BY r.schema_build_digest"
      ),
      params = list(data$commit_order)
    )
  )
  digests <- unique(c(
    data$schema_build_digest,
    as.character(batches$schema_build_digest),
    as.character(revisions$schema_build_digest)
  ))
  tryCatch(
    historical_schemas(store, digests),
    error = function(error) {
      abort_snapshot_error(
        "graft_snapshot_schema_error",
        paste0(
          "The snapshot requires unavailable or invalid historical schema ",
          "metadata."
        ),
        schema_build_digests = digests,
        parent = error
      )
    }
  )
}

graft_view_state <- function(view) {
  attr(view, ".state", exact = TRUE)
}

validate_graft_view_s7 <- function(self) {
  state <- graft_view_state(self)
  if (
    !is.list(state) ||
      is.object(state) ||
      !identical(names(state), c("store", "snapshot", "schema"))
  ) {
    return("internal view state is invalid")
  }
  if (!S7::S7_inherits(state$store, GraftStore)) {
    return("internal view store must be a GraftStore object")
  }
  store_error <- tryCatch(
    {
      S7::validate(state$store)
      NULL
    },
    error = conditionMessage
  )
  if (!is.null(store_error)) {
    return("internal view store is invalid")
  }
  if (!S7::S7_inherits(state$snapshot, GraftSnapshot)) {
    return("internal view snapshot must be a GraftSnapshot object")
  }
  snapshot_problem <- snapshot_validation_problem(snapshot_data(state$snapshot))
  if (!is.null(snapshot_problem)) {
    return("internal view snapshot is invalid")
  }
  store_id <- tryCatch(state$store@id, error = \(.x) NA_character_)
  if (!is_nonempty_string(store_id)) {
    return("internal view store identity is invalid")
  }
  if (!identical(state$snapshot@store_id, store_id)) {
    return("internal view snapshot does not match the store")
  }
  if (!is_compiled_schema(state$schema)) {
    return("internal view schema must be a compiled schema")
  }
  build_digest <- scalar_character(
    state$schema$manifest$fingerprints$build_digest
  )
  if (!identical(build_digest, state$snapshot@schema_build_digest)) {
    return("internal view schema does not match the snapshot")
  }
  NULL
}

is_graft_view <- function(x) {
  S7::S7_inherits(x, GraftView)
}

as_graft_view <- function(x, arg = rlang::caller_arg(x)) {
  if (!is_graft_view(x)) {
    abort_snapshot_error(
      "graft_snapshot_invalid",
      paste0("`", arg, "` must be a GraftView object."),
      argument = arg
    )
  }
  state <- graft_view_state(x)
  if (
    is.list(state) &&
      !is.object(state) &&
      identical(names(state), c("store", "snapshot", "schema")) &&
      S7::S7_inherits(state$snapshot, GraftSnapshot)
  ) {
    snapshot <- as_graft_snapshot(
      state$snapshot,
      paste0(arg, " snapshot")
    )
    if (S7::S7_inherits(state$store, GraftStore)) {
      store_id <- tryCatch(state$store@id, error = \(.x) NA_character_)
      if (
        is_nonempty_string(store_id) &&
          !identical(snapshot@store_id, store_id)
      ) {
        abort_snapshot_error(
          "graft_snapshot_store_mismatch",
          "The snapshot belongs to a different Graft store.",
          expected_store_id = snapshot@store_id,
          observed_store_id = store_id
        )
      }
    }
  }
  error <- tryCatch(
    {
      S7::validate(x)
      NULL
    },
    error = identity
  )
  if (!is.null(error)) {
    abort_snapshot_error(
      "graft_snapshot_invalid",
      paste0("`", arg, "` is an invalid GraftView object."),
      argument = arg,
      parent = error
    )
  }
  x
}

as_graft_read_store_internal <- function(
  x,
  arg = rlang::caller_arg(x)
) {
  if (S7::S7_inherits(x, GraftStore)) {
    return(as_graft_store_internal(x, arg))
  }
  if (!is_graft_view(x)) {
    abort_backend_error(
      paste0("`", arg, "` must be a GraftStore or GraftView object."),
      operation = "validate_read_store",
      argument = arg
    )
  }
  view <- as_graft_view(x, arg)
  state <- graft_view_state(view)
  source <- as_graft_store_internal(state$store, arg)
  snapshot <- as_graft_snapshot(state$snapshot, "view snapshot")
  schema <- validate_graft_snapshot_mapping(source, snapshot)
  if (
    !identical(
      canonical_manifest_json(schema$manifest),
      canonical_manifest_json(state$schema$manifest)
    )
  ) {
    abort_snapshot_error(
      "graft_snapshot_schema_error",
      "The view schema no longer matches its registered snapshot schema.",
      schema_build_digest = snapshot@schema_build_digest
    )
  }
  new_graft_snapshot_backend(source, schema, snapshot_data(snapshot))
}

new_graft_snapshot_backend <- function(source, schema, snapshot) {
  backend <- new_store_backend(
    schema = schema,
    connection = source$connection,
    owns_connection = FALSE,
    read_only = TRUE,
    path = source$path,
    capabilities = duckdb_capabilities(TRUE, FALSE),
    okf_mode = "disabled",
    okf_path = NULL
  )
  backend$snapshot <- snapshot
  backend$source_backend <- source
  backend
}

is_graft_snapshot_backend <- function(x) {
  if (!is_store_backend(x)) {
    return(FALSE)
  }
  fields <- c(
    "schema",
    "connection",
    "owns_connection",
    "read_only",
    "path",
    "closed",
    "capabilities",
    "okf_mode",
    "okf_path",
    "okf_expected",
    "verification",
    "snapshot",
    "source_backend"
  )
  if (!identical(sort(ls(x, all.names = TRUE)), sort(fields))) {
    return(FALSE)
  }
  if (
    !is_store_backend(x$source_backend) ||
      !identical(x$connection, x$source_backend$connection) ||
      !identical(x$read_only, TRUE) ||
      !identical(x$owns_connection, FALSE) ||
      !is.null(snapshot_validation_problem(x$snapshot))
  ) {
    return(FALSE)
  }
  identical(
    scalar_character(x$schema$manifest$fingerprints$build_digest),
    x$snapshot$schema_build_digest
  )
}

snapshot_backend_data <- function(x) {
  if (!is_graft_snapshot_backend(x)) {
    return(NULL)
  }
  x$snapshot
}
