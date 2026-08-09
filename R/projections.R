graft_current_view_name <- "_graft_current_records"
graft_projection_state_id <- "active"

generated_projection_view_names <- function(schema) {
  class_views <- vapply(
    schema$manifest$classes,
    \(.x) scalar_character(.x$view),
    character(1)
  )
  relation_views <- vapply(
    schema$manifest$relations,
    \(.x) scalar_character(.x$view),
    character(1)
  )
  c(
    graft_current_view_name,
    sort(class_views),
    sort(relation_views),
    graft_graph_view_names
  )
}

generated_projection_table_names <- function(schema) {
  views <- c(
    vapply(
      schema$manifest$classes,
      \(.x) scalar_character(.x$view),
      character(1)
    ),
    vapply(
      schema$manifest$relations,
      \(.x) scalar_character(.x$view),
      character(1)
    )
  )
  sort(vapply(views, projection_cache_table_name, character(1)))
}

projection_cache_table_name <- function(view) {
  paste0("_graft_projection_", view)
}

rebuild_store_projections <- function(store) {
  validate_store_writable(store, "rebuild_projections")
  validate_manifest_integrity(store$schema)
  if (!duckdb_table_exists(store$connection, "_graft_store")) {
    abort_backend_error(
      "Projection rebuild requires an initialized store.",
      operation = "rebuild_projections"
    )
  }
  with_duckdb_error(
    "rebuild_projections",
    DBI::dbWithTransaction(store$connection, {
      rebuild_projection_views(store$connection, store$schema)
    })
  )
  invisible(store)
}

rebuild_projection_views <- function(connection, schema) {
  validate_projection_head_integrity(connection)
  drop_projection_views(connection, schema)
  drop_projection_cache_tables(connection, schema)
  drop_projection_object(connection, graft_projection_metadata_table_names)
  create_current_record_view(connection)
  create_projection_cache_tables(connection, schema)
  populate_projection_cache_tables(connection, schema)
  create_public_projection_views(connection, schema)
  create_graph_views(connection, schema)
  create_projection_state_table(connection)
  write_projection_state(connection, schema)
  invisible(connection)
}

drop_projection_views <- function(connection, schema) {
  names <- rev(generated_projection_view_names(schema))
  for (name in names) {
    drop_projection_object(connection, name)
  }
  invisible(connection)
}

drop_projection_cache_tables <- function(connection, schema) {
  for (name in generated_projection_table_names(schema)) {
    drop_projection_object(connection, name)
  }
  invisible(connection)
}

drop_projection_object <- function(connection, name) {
  type <- projection_object_type(connection, name)
  if (is.na(type)) {
    return(invisible(connection))
  }
  kind <- if (identical(type, "VIEW")) "VIEW" else "TABLE"
  DBI::dbExecute(
    connection,
    paste0(
      "DROP ",
      kind,
      " ",
      quote_identifier(connection, name)
    )
  )
  invisible(connection)
}

verify_projection_views <- function(connection, schema) {
  validate_projection_head_integrity(connection)
  expected <- c(
    stats::setNames(
      rep("VIEW", length(generated_projection_view_names(schema))),
      generated_projection_view_names(schema)
    ),
    stats::setNames(
      rep("BASE TABLE", length(generated_projection_table_names(schema))),
      generated_projection_table_names(schema)
    ),
    stats::setNames(
      rep("BASE TABLE", length(graft_projection_metadata_table_names)),
      graft_projection_metadata_table_names
    )
  )
  catalog <- projection_object_catalog(connection)
  observed <- stats::setNames(catalog$table_type, catalog$table_name)
  invalid <- names(expected)[
    is.na(observed[names(expected)]) |
      observed[names(expected)] != expected
  ]
  if (length(invalid) > 0L) {
    details <- vapply(
      invalid,
      function(name) {
        type <- observed[[name]]
        if (is.null(type) || is.na(type)) {
          type <- "missing"
        }
        paste0(name, " (expected ", expected[[name]], ", found ", type, ")")
      },
      character(1)
    )
    abort_backend_error(
      paste0(
        "The initialized read-only store has invalid generated projection ",
        "object(s): ",
        paste(details, collapse = ", "),
        ". Reopen it writable with `graft_open()`."
      ),
      operation = "verify_projection_views",
      invalid_projections = invalid
    )
  }
  verify_projection_state(connection, schema)
  invisible(connection)
}

projection_object_catalog <- function(connection) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT table_name, table_type FROM information_schema.tables",
      "WHERE table_schema = 'main' ORDER BY table_name"
    )
  )
}

projection_object_type <- function(connection, name) {
  catalog <- projection_object_catalog(connection)
  indexes <- which(catalog$table_name == name)
  if (length(indexes) != 1L) {
    return(NA_character_)
  }
  catalog$table_type[[indexes]]
}

validate_projection_head_integrity <- function(connection) {
  head <- quote_identifier(connection, "_graft_record_heads")
  revision <- quote_identifier(connection, "_graft_record_revisions")
  invalid <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT h.record_id, h.class, h.revision_id, ",
      "CAST(h.revision_number AS VARCHAR) AS revision_number, ",
      "COUNT(r.revision_id) AS matching_revision_count FROM ",
      head,
      " AS h LEFT JOIN ",
      revision,
      " AS r ON h.record_id = r.record_id AND h.class = r.class ",
      "AND h.revision_id = r.revision_id ",
      "AND h.revision_number = r.revision_number ",
      "GROUP BY h.record_id, h.class, h.revision_id, h.revision_number ",
      "HAVING COUNT(r.revision_id) <> 1 ORDER BY h.class, h.record_id"
    )
  )
  if (nrow(invalid) > 0L) {
    abort_backend_error(
      paste0(
        "Projection rebuild requires every record head to match exactly one ",
        "revision on record ID, class, revision ID, and revision number; ",
        "found ",
        nrow(invalid),
        " invalid head(s)."
      ),
      operation = "validate_projection_heads",
      invalid_heads = invalid
    )
  }
  invisible(connection)
}

write_projection_state <- function(connection, schema) {
  values <- projection_state_values(connection, schema)
  DBI::dbExecute(
    connection,
    paste0(
      "DELETE FROM ",
      quote_identifier(connection, graft_projection_metadata_table_names)
    )
  )
  row <- data.frame(
    state_id = graft_projection_state_id,
    schema_build_digest = values$schema_build_digest,
    head_source_digest = values$head_source_digest,
    cache_digest = values$cache_digest,
    object_digest = values$object_digest,
    rebuilt_at = as.POSIXct(Sys.time(), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(
    connection,
    graft_projection_metadata_table_names,
    row
  )
  invisible(connection)
}

create_projection_state_table <- function(connection) {
  create_table(
    connection,
    graft_projection_metadata_table_names,
    list(
      ddl_column(
        "state_id",
        "VARCHAR",
        nullable = FALSE,
        primary_key = TRUE
      ),
      ddl_column("schema_build_digest", "VARCHAR", nullable = FALSE),
      ddl_column("head_source_digest", "VARCHAR", nullable = FALSE),
      ddl_column("cache_digest", "VARCHAR", nullable = FALSE),
      ddl_column("object_digest", "VARCHAR", nullable = FALSE),
      ddl_column("rebuilt_at", "TIMESTAMP", nullable = FALSE)
    )
  )
  invisible(connection)
}

verify_projection_state <- function(connection, schema) {
  expected_columns <- c(
    "state_id",
    "schema_build_digest",
    "head_source_digest",
    "cache_digest",
    "object_digest",
    "rebuilt_at"
  )
  missing_columns <- setdiff(
    expected_columns,
    DBI::dbListFields(connection, graft_projection_metadata_table_names)
  )
  if (length(missing_columns) > 0L) {
    abort_backend_error(
      paste0(
        "The derived projection state is missing column(s): ",
        paste(missing_columns, collapse = ", "),
        ". Reopen the store writable with `graft_open()`."
      ),
      operation = "verify_projection_state",
      missing_columns = missing_columns
    )
  }
  state <- DBI::dbReadTable(
    connection,
    graft_projection_metadata_table_names
  )
  if (
    nrow(state) != 1L ||
      !identical(state$state_id[[1L]], graft_projection_state_id)
  ) {
    abort_backend_error(
      paste0(
        "The derived projection state must contain exactly one active row; ",
        "found ",
        nrow(state),
        ". Reopen the store writable with `graft_open()`."
      ),
      operation = "verify_projection_state",
      row_count = nrow(state)
    )
  }
  expected <- projection_state_values(connection, schema)
  fields <- names(expected)
  stale <- fields[vapply(
    fields,
    \(field) !identical(state[[field]][[1L]], expected[[field]]),
    logical(1)
  )]
  if (length(stale) > 0L) {
    abort_backend_error(
      paste0(
        "The generated projections are stale or altered in: ",
        paste(stale, collapse = ", "),
        ". Reopen the store writable with `graft_open()`."
      ),
      operation = "verify_projection_state",
      stale_fields = stale
    )
  }
  invisible(connection)
}

projection_state_values <- function(connection, schema) {
  list(
    schema_build_digest = scalar_character(
      schema$manifest$fingerprints$build_digest
    ),
    head_source_digest = projection_head_source_digest(connection),
    cache_digest = projection_cache_digest(connection, schema),
    object_digest = projection_object_digest(connection, schema)
  )
}

projection_head_source_digest <- function(connection) {
  head <- quote_identifier(connection, "_graft_record_heads")
  revision <- quote_identifier(connection, "_graft_record_revisions")
  rows <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT CAST(h.record_id AS VARCHAR) AS head_record_id, ",
      "CAST(h.class AS VARCHAR) AS head_class, ",
      "CAST(h.revision_id AS VARCHAR) AS head_revision_id, ",
      "CAST(h.revision_number AS VARCHAR) AS head_revision_number, ",
      "CAST(h.updated_at AS VARCHAR) AS head_updated_at, ",
      "CAST(r.batch_id AS VARCHAR) AS batch_id, ",
      "CAST(r.schema_build_digest AS VARCHAR) AS schema_build_digest, ",
      "CAST(r.operation AS VARCHAR) AS operation, ",
      "CAST(r.payload_json AS VARCHAR) AS payload_json, ",
      "CAST(r.content_digest AS VARCHAR) AS content_digest, ",
      "CAST(r.changed_fields_json AS VARCHAR) AS changed_fields_json, ",
      "CAST(r.prior_revision_id AS VARCHAR) AS prior_revision_id, ",
      "CAST(r.recorded_at AS VARCHAR) AS recorded_at, ",
      "CAST(r.commit_order AS VARCHAR) AS commit_order FROM ",
      head,
      " AS h INNER JOIN ",
      revision,
      " AS r ON h.record_id = r.record_id AND h.class = r.class ",
      "AND h.revision_id = r.revision_id ",
      "AND h.revision_number = r.revision_number"
    )
  )
  projection_data_digest("headed_revision_source", rows)
}

projection_cache_digest <- function(connection, schema) {
  tables <- generated_projection_table_names(schema)
  digests <- vapply(
    tables,
    \(table) projection_table_content_digest(connection, table),
    character(1)
  )
  projection_data_digest(
    "projection_caches",
    data.frame(
      table_name = tables,
      content_digest = unname(digests),
      stringsAsFactors = FALSE
    )
  )
}

projection_table_content_digest <- function(connection, table) {
  fields <- DBI::dbListFields(connection, table)
  columns <- vapply(
    fields,
    function(field) {
      identifier <- quote_identifier(connection, field)
      paste0("CAST(", identifier, " AS VARCHAR) AS ", identifier)
    },
    character(1)
  )
  rows <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT ",
      paste(columns, collapse = ", "),
      " FROM ",
      quote_identifier(connection, table)
    )
  )
  projection_data_digest(table, rows)
}

projection_object_digest <- function(connection, schema) {
  names <- c(
    generated_projection_view_names(schema),
    generated_projection_table_names(schema),
    graft_projection_metadata_table_names
  )
  catalog <- projection_object_catalog(connection)
  catalog <- catalog[match(names, catalog$table_name), , drop = FALSE]
  projection_data_digest("projection_objects", catalog)
}

projection_data_digest <- function(label, data) {
  columns <- names(data)
  rows <- character(nrow(data))
  if (nrow(data) > 0L) {
    for (index in seq_len(nrow(data))) {
      values <- vapply(
        columns,
        function(column) {
          projection_encode_digest_value(data[[column]][[index]])
        },
        character(1)
      )
      rows[[index]] <- paste(values, collapse = "")
    }
  }
  rows <- sort(rows, method = "radix")
  payload <- paste0(
    projection_encode_digest_value(label),
    projection_encode_digest_value(paste(columns, collapse = "\n")),
    paste(rows, collapse = "")
  )
  paste0(
    "sha256:",
    digest::digest(payload, algo = "sha256", serialize = FALSE)
  )
}

projection_encode_digest_value <- function(value) {
  if (length(value) == 0L || is.na(value[[1L]])) {
    return("-1:")
  }
  value <- enc2utf8(as.character(value[[1L]]))
  paste0(nchar(value, type = "bytes"), ":", value)
}

create_current_record_view <- function(connection) {
  head <- quote_identifier(connection, "_graft_record_heads")
  revision <- quote_identifier(connection, "_graft_record_revisions")
  sql <- paste0(
    "CREATE VIEW ",
    quote_identifier(connection, graft_current_view_name),
    " AS SELECT r.revision_id, r.record_id, r.class, r.batch_id, ",
    "r.schema_build_digest, r.revision_number, r.operation, ",
    "r.payload_json, r.content_digest, r.changed_fields_json, ",
    "r.prior_revision_id, r.recorded_at, r.commit_order, ",
    "h.updated_at AS head_updated_at FROM ",
    revision,
    " AS r INNER JOIN ",
    head,
    " AS h ON h.revision_id = r.revision_id ",
    "AND h.record_id = r.record_id AND h.class = r.class ",
    "AND h.revision_number = r.revision_number ",
    "WHERE r.operation <> 'delete'"
  )
  DBI::dbExecute(connection, sql)
  invisible(connection)
}

create_projection_cache_tables <- function(connection, schema) {
  for (contract in schema$manifest$classes) {
    create_class_projection_cache(connection, contract)
  }
  for (relation in schema$manifest$relations) {
    create_multivalue_projection_cache(connection, schema, relation)
  }
  invisible(connection)
}

create_class_projection_cache <- function(connection, contract) {
  scalar_slots <- Filter(
    \(.x) !scalar_logical(.x$multivalued),
    contract$slots
  )
  columns <- lapply(scalar_slots, function(slot) {
    ddl_column(
      scalar_character(slot$view_column),
      scalar_character(slot$duckdb_type),
      nullable = !scalar_logical(slot$required),
      primary_key = scalar_logical(slot$identifier)
    )
  })
  table <- projection_cache_table_name(scalar_character(contract$view))
  create_table(connection, table, columns)
  references <- Filter(\(.x) scalar_logical(.x$object_reference), scalar_slots)
  create_table_indexes(
    connection,
    table,
    lapply(references, \(.x) scalar_character(.x$view_column))
  )
  invisible(connection)
}

create_multivalue_projection_cache <- function(connection, schema, relation) {
  record_class <- scalar_character(relation$owner_class)
  slot_name <- scalar_character(relation$slot)
  slot <- schema$manifest$classes[[record_class]]$slots[[slot_name]]
  kind <- scalar_character(relation$kind)
  columns <- if (identical(kind, "object")) {
    list(
      ddl_column("id", "VARCHAR", nullable = FALSE, primary_key = TRUE),
      ddl_column("subject", "VARCHAR", nullable = FALSE),
      ddl_column("object", "VARCHAR", nullable = FALSE),
      ddl_column("position", "BIGINT"),
      ddl_column("created_at", "TIMESTAMP", nullable = FALSE)
    )
  } else {
    list(
      ddl_column("owner_id", "VARCHAR", nullable = FALSE),
      ddl_column("position", "BIGINT"),
      ddl_column("value", scalar_character(slot$duckdb_type), nullable = FALSE)
    )
  }
  table <- projection_cache_table_name(scalar_character(relation$view))
  create_table(connection, table, columns)
  owner <- if (identical(kind, "object")) "subject" else "owner_id"
  create_table_indexes(connection, table, list(owner))
  invisible(connection)
}

populate_projection_cache_tables <- function(connection, schema) {
  current <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT record_id, class, payload_json, recorded_at FROM ",
      quote_identifier(connection, graft_current_view_name),
      " ORDER BY class, record_id"
    )
  )
  payloads <- lapply(current$payload_json, projection_parse_payload)
  for (record_class in names(schema$manifest$classes)) {
    contract <- schema$manifest$classes[[record_class]]
    indexes <- which(current$class == record_class)
    rows <- projection_class_rows(
      current[indexes, , drop = FALSE],
      payloads[indexes],
      contract
    )
    if (nrow(rows) > 0L) {
      DBI::dbAppendTable(
        connection,
        projection_cache_table_name(scalar_character(contract$view)),
        rows
      )
    }
  }
  for (relation in schema$manifest$relations) {
    record_class <- scalar_character(relation$owner_class)
    indexes <- which(current$class == record_class)
    rows <- projection_multivalue_rows(
      current[indexes, , drop = FALSE],
      payloads[indexes],
      schema,
      relation
    )
    if (nrow(rows) > 0L) {
      DBI::dbAppendTable(
        connection,
        projection_cache_table_name(scalar_character(relation$view)),
        rows
      )
    }
  }
  invisible(connection)
}

projection_parse_payload <- function(payload_json) {
  tryCatch(
    jsonlite::fromJSON(
      payload_json,
      simplifyVector = FALSE,
      bigint_as_char = TRUE
    ),
    error = function(error) {
      abort_backend_error(
        paste0(
          "Could not rebuild projections from revision payload JSON: ",
          conditionMessage(error)
        ),
        operation = "rebuild_projections",
        parent = error
      )
    }
  )
}

projection_class_rows <- function(current, payloads, contract) {
  slots <- Filter(
    \(.x) !scalar_logical(.x$multivalued),
    contract$slots
  )
  rows <- data.frame(row.names = seq_len(nrow(current)))
  for (slot_name in names(slots)) {
    slot <- slots[[slot_name]]
    values <- if (
      scalar_logical(slot$identifier) && identical(slot_name, "id")
    ) {
      as.list(current$record_id)
    } else {
      lapply(payloads, \(.x) .x[[slot_name]])
    }
    rows[[scalar_character(slot$view_column)]] <-
      projection_coerce_values(values, scalar_character(slot$duckdb_type))
  }
  rows
}

projection_multivalue_rows <- function(
  current,
  payloads,
  schema,
  relation
) {
  record_class <- scalar_character(relation$owner_class)
  slot_name <- scalar_character(relation$slot)
  slot <- schema$manifest$classes[[record_class]]$slots[[slot_name]]
  kind <- scalar_character(relation$kind)
  owner <- character()
  values <- list()
  positions <- numeric()
  recorded_at <- as.POSIXct(
    character(),
    origin = "1970-01-01",
    tz = "UTC"
  )
  for (index in seq_along(payloads)) {
    items <- payloads[[index]][[slot_name]]
    if (is.null(items) || length(items) == 0L) {
      next
    }
    owner <- c(owner, rep(current$record_id[[index]], length(items)))
    values <- c(values, items)
    positions <- c(positions, seq_along(items))
    recorded_at <- c(
      recorded_at,
      rep(current$recorded_at[[index]], length(items))
    )
  }
  position <- if (scalar_logical(relation$ordered)) {
    positions
  } else {
    rep(NA_real_, length(owner))
  }
  coerced <- projection_coerce_values(
    values,
    scalar_character(slot$duckdb_type)
  )
  if (identical(kind, "object")) {
    if (length(owner) == 0L) {
      return(data.frame(
        id = character(),
        subject = character(),
        object = character(),
        position = numeric(),
        created_at = as.POSIXct(
          numeric(),
          origin = "1970-01-01",
          tz = "UTC"
        ),
        stringsAsFactors = FALSE
      ))
    }
    return(data.frame(
      id = paste0(owner, "#", slot_name, ":", positions),
      subject = owner,
      object = coerced,
      position = position,
      created_at = recorded_at,
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    owner_id = owner,
    position = position,
    value = coerced,
    stringsAsFactors = FALSE
  )
}

projection_coerce_values <- function(values, type) {
  type <- safe_duckdb_type(type)
  if (identical(type, "BIGINT")) {
    return(projection_coerce_exact_numbers(values, type))
  }
  if (identical(type, "DECIMAL")) {
    return(projection_coerce_exact_numbers(values, type))
  }
  text <- projection_text_values(values)
  switch(
    type,
    BOOLEAN = as.logical(text),
    DOUBLE = as.numeric(text),
    DATE = as.Date(text),
    TIMESTAMP = projection_coerce_timestamps(text),
    text
  )
}

projection_text_values <- function(values) {
  vapply(
    values,
    function(value) {
      if (is.null(value) || length(value) == 0L || is.na(value[[1L]])) {
        NA_character_
      } else {
        as.character(value[[1L]])
      }
    },
    character(1)
  )
}

projection_coerce_exact_numbers <- function(values, type) {
  vapply(
    values,
    function(value) {
      if (is.null(value) || length(value) == 0L || is.na(value[[1L]])) {
        return(NA_character_)
      }
      item <- value[[1L]]
      if (is.character(item)) {
        return(item)
      }
      if (is.integer(item)) {
        return(as.character(item))
      }
      if (
        is.numeric(item) &&
          length(item) == 1L &&
          is.finite(item) &&
          item == trunc(item) &&
          abs(item) < 2^53
      ) {
        return(sprintf("%.0f", item))
      }
      abort_backend_error(
        paste0(
          "Cannot rebuild an exact ",
          type,
          " projection from a JSON number that may already have lost ",
          "precision. Encode ",
          type,
          " payload values as JSON strings."
        ),
        operation = "rebuild_projections",
        duckdb_type = type,
        value = item
      )
    },
    character(1)
  )
}

projection_coerce_timestamps <- function(text) {
  present <- !is.na(text)
  canonical <- grepl(
    paste0(
      "^[0-9]{4}-[0-9]{2}-[0-9]{2}T",
      "[0-9]{2}:[0-9]{2}:[0-9]{2}",
      "(\\.[0-9]{1,6})?Z$"
    ),
    text
  )
  if (any(present & !canonical)) {
    abort_backend_error(
      paste0(
        "Projection timestamps must use canonical UTC ISO-8601 syntax ",
        "with at most six fractional digits."
      ),
      operation = "rebuild_projections",
      invalid_timestamps = unique(text[present & !canonical])
    )
  }
  result <- as.POSIXct(
    text,
    format = "%Y-%m-%dT%H:%M:%OSZ",
    tz = "UTC"
  )
  if (any(present & is.na(result))) {
    abort_backend_error(
      "Projection timestamps contain an invalid UTC date or time.",
      operation = "rebuild_projections",
      invalid_timestamps = unique(text[present & is.na(result)])
    )
  }
  result
}

create_public_projection_views <- function(connection, schema) {
  views <- c(
    vapply(
      schema$manifest$classes,
      \(.x) scalar_character(.x$view),
      character(1)
    ),
    vapply(
      schema$manifest$relations,
      \(.x) scalar_character(.x$view),
      character(1)
    )
  )
  for (view in views) {
    sql <- paste0(
      "CREATE VIEW ",
      quote_identifier(connection, view),
      " AS SELECT * FROM ",
      quote_identifier(connection, projection_cache_table_name(view))
    )
    DBI::dbExecute(connection, sql)
  }
  invisible(connection)
}
