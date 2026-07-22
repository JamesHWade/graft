graft_store_format_version <- "2.0.0"

metadata_table_definitions <- function() {
  list(
    `_graft_store` = list(
      columns = list(
        ddl_column("store_id", "VARCHAR", nullable = FALSE, primary_key = TRUE),
        ddl_column("store_format_version", "VARCHAR", nullable = FALSE),
        ddl_column(
          "active_structural_digest",
          "VARCHAR",
          nullable = FALSE
        ),
        ddl_column("active_build_digest", "VARCHAR", nullable = FALSE),
        ddl_column("source_digest", "VARCHAR", nullable = FALSE),
        ddl_column("build_digest", "VARCHAR", nullable = FALSE),
        ddl_column("manifest_json", "VARCHAR", nullable = FALSE),
        ddl_column("history_started_at", "TIMESTAMP", nullable = FALSE),
        ddl_column("history_complete", "BOOLEAN", nullable = FALSE),
        ddl_column("created_at", "TIMESTAMP", nullable = FALSE),
        ddl_column("updated_at", "TIMESTAMP", nullable = FALSE)
      )
    ),
    `_graft_schema_versions` = list(
      columns = list(
        ddl_column(
          "build_digest",
          "VARCHAR",
          nullable = FALSE,
          primary_key = TRUE
        ),
        ddl_column("structural_digest", "VARCHAR", nullable = FALSE),
        ddl_column("source_digest", "VARCHAR", nullable = FALSE),
        ddl_column("manifest_json", "VARCHAR", nullable = FALSE),
        ddl_column("compiler_json", "VARCHAR", nullable = FALSE),
        ddl_column("registered_at", "TIMESTAMP", nullable = FALSE)
      ),
      indexes = list(
        c("structural_digest"),
        c("source_digest")
      )
    ),
    `_graft_schema_activations` = list(
      columns = list(
        ddl_column(
          "activation_id",
          "VARCHAR",
          nullable = FALSE,
          primary_key = TRUE
        ),
        ddl_column("build_digest", "VARCHAR", nullable = FALSE),
        ddl_column("previous_build_digest", "VARCHAR"),
        ddl_column("reason", "VARCHAR", nullable = FALSE),
        ddl_column("activation_order", "BIGINT", nullable = FALSE),
        ddl_column("activated_at", "TIMESTAMP", nullable = FALSE)
      ),
      constraints = list(
        c("activation_order")
      ),
      indexes = list(
        c("build_digest")
      )
    ),
    `_graft_migrations` = list(
      columns = list(
        ddl_column(
          "migration_id",
          "VARCHAR",
          nullable = FALSE,
          primary_key = TRUE
        ),
        ddl_column("plan_digest", "VARCHAR", nullable = FALSE),
        ddl_column("from_build_digest", "VARCHAR", nullable = FALSE),
        ddl_column("to_build_digest", "VARCHAR", nullable = FALSE),
        ddl_column(
          "from_structural_digest",
          "VARCHAR",
          nullable = FALSE
        ),
        ddl_column(
          "to_structural_digest",
          "VARCHAR",
          nullable = FALSE
        ),
        ddl_column("classification", "VARCHAR", nullable = FALSE),
        ddl_column("changes_json", "VARCHAR", nullable = FALSE),
        ddl_column("operations_json", "VARCHAR", nullable = FALSE),
        ddl_column("application_order", "BIGINT", nullable = FALSE),
        ddl_column("applied_at", "TIMESTAMP", nullable = FALSE)
      ),
      constraints = list(
        c("plan_digest"),
        c("application_order")
      ),
      indexes = list(
        c("from_build_digest"),
        c("to_build_digest")
      )
    ),
    `_graft_batches` = list(
      columns = list(
        ddl_column("batch_id", "VARCHAR", nullable = FALSE, primary_key = TRUE),
        ddl_column("schema_build_digest", "VARCHAR", nullable = FALSE),
        ddl_column("commit_order", "BIGINT", nullable = FALSE),
        ddl_column("producer", "VARCHAR", nullable = FALSE),
        ddl_column("producer_version", "VARCHAR"),
        ddl_column("source_run_id", "VARCHAR"),
        ddl_column("idempotency_key", "VARCHAR"),
        ddl_column("metadata_json", "VARCHAR"),
        ddl_column("started_at", "TIMESTAMP", nullable = FALSE),
        ddl_column("committed_at", "TIMESTAMP"),
        ddl_column("status", "VARCHAR", nullable = FALSE)
      ),
      constraints = list(
        c("producer", "idempotency_key"),
        c("commit_order")
      ),
      indexes = list(
        c("schema_build_digest"),
        c("source_run_id"),
        c("status")
      )
    ),
    `_graft_record_origins` = list(
      columns = list(
        ddl_column("record_id", "VARCHAR", nullable = FALSE),
        ddl_column("class", "VARCHAR", nullable = FALSE),
        ddl_column("producer", "VARCHAR", nullable = FALSE),
        ddl_column("origin_key", "VARCHAR", nullable = FALSE),
        ddl_column("first_batch_id", "VARCHAR", nullable = FALSE),
        ddl_column("created_at", "TIMESTAMP", nullable = FALSE)
      ),
      constraints = list(
        c("class", "producer", "origin_key")
      ),
      indexes = list(
        c("first_batch_id")
      )
    ),
    `_graft_record_observations` = list(
      columns = list(
        ddl_column("record_id", "VARCHAR", nullable = FALSE),
        ddl_column("class", "VARCHAR", nullable = FALSE),
        ddl_column("batch_id", "VARCHAR", nullable = FALSE),
        ddl_column("disposition", "VARCHAR", nullable = FALSE),
        ddl_column("revision_id", "VARCHAR", nullable = FALSE),
        ddl_column("observed_at", "TIMESTAMP", nullable = FALSE)
      ),
      constraints = list(
        c("record_id", "class", "batch_id")
      ),
      indexes = list(
        c("batch_id"),
        c("revision_id")
      )
    ),
    `_graft_record_revisions` = list(
      columns = list(
        ddl_column(
          "revision_id",
          "VARCHAR",
          nullable = FALSE,
          primary_key = TRUE
        ),
        ddl_column("record_id", "VARCHAR", nullable = FALSE),
        ddl_column("class", "VARCHAR", nullable = FALSE),
        ddl_column("batch_id", "VARCHAR", nullable = FALSE),
        ddl_column("schema_build_digest", "VARCHAR", nullable = FALSE),
        ddl_column("revision_number", "BIGINT", nullable = FALSE),
        ddl_column("operation", "VARCHAR", nullable = FALSE),
        ddl_column("payload_json", "VARCHAR", nullable = FALSE),
        ddl_column("content_digest", "VARCHAR", nullable = FALSE),
        ddl_column("changed_fields_json", "VARCHAR", nullable = FALSE),
        ddl_column("prior_revision_id", "VARCHAR"),
        ddl_column("recorded_at", "TIMESTAMP", nullable = FALSE),
        ddl_column("commit_order", "BIGINT", nullable = FALSE)
      ),
      constraints = list(
        c("record_id", "class", "revision_number"),
        c("record_id", "class", "batch_id")
      ),
      indexes = list(
        c("record_id", "class"),
        c("batch_id"),
        c("schema_build_digest"),
        c("commit_order")
      )
    ),
    `_graft_record_heads` = list(
      columns = list(
        ddl_column(
          "record_id",
          "VARCHAR",
          nullable = FALSE,
          primary_key = TRUE
        ),
        ddl_column("class", "VARCHAR", nullable = FALSE),
        ddl_column("revision_id", "VARCHAR", nullable = FALSE),
        ddl_column("revision_number", "BIGINT", nullable = FALSE),
        ddl_column("updated_at", "TIMESTAMP", nullable = FALSE)
      ),
      indexes = list(
        c("class"),
        c("revision_id")
      )
    ),
    `_graft_identifiers` = list(
      columns = list(
        ddl_column("record_id", "VARCHAR", nullable = FALSE),
        ddl_column("class", "VARCHAR", nullable = FALSE),
        ddl_column("namespace", "VARCHAR", nullable = FALSE),
        ddl_column("value", "VARCHAR", nullable = FALSE),
        ddl_column("normalized_value", "VARCHAR", nullable = FALSE),
        ddl_column("status", "VARCHAR", nullable = FALSE),
        ddl_column("assigned_by", "VARCHAR", nullable = FALSE),
        ddl_column("confidence", "DOUBLE"),
        ddl_column("created_at", "TIMESTAMP", nullable = FALSE)
      ),
      constraints = list(
        c("class", "namespace", "normalized_value")
      ),
      indexes = list(
        c("record_id", "class"),
        c("status")
      )
    )
  )
}

create_metadata_tables <- function(connection) {
  definitions <- metadata_table_definitions()
  for (name in names(definitions)) {
    definition <- definitions[[name]]
    create_table(
      connection,
      name,
      definition$columns,
      unique_constraints = definition$constraints
    )
    create_table_indexes(connection, name, definition$indexes)
  }
  invisible(connection)
}

insert_store_metadata <- function(store) {
  manifest <- store$schema$manifest
  fingerprints <- manifest$fingerprints
  now <- as.POSIXct(Sys.time(), tz = "UTC")
  row <- data.frame(
    store_id = new_store_id(),
    store_format_version = graft_store_format_version,
    active_structural_digest = scalar_character(
      fingerprints$structural_digest
    ),
    active_build_digest = scalar_character(fingerprints$build_digest),
    source_digest = scalar_character(fingerprints$source_digest),
    build_digest = scalar_character(fingerprints$build_digest),
    manifest_json = canonical_manifest_json(manifest),
    history_started_at = now,
    history_complete = TRUE,
    created_at = now,
    updated_at = now,
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(store$connection, "_graft_store", row)
  invisible(store)
}

register_initial_schema <- function(store) {
  now <- as.POSIXct(Sys.time(), tz = "UTC")
  register_schema_version(store$connection, store$schema, now)
  insert_schema_activation(
    store$connection,
    store$schema,
    previous_build_digest = NA_character_,
    reason = "initial",
    now = now
  )
  invisible(store)
}

register_schema_version <- function(connection, schema, now = Sys.time()) {
  manifest <- schema$manifest
  fingerprints <- manifest$fingerprints
  build_digest <- scalar_character(fingerprints$build_digest)
  existing <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT manifest_json FROM ",
      quote_identifier(connection, "_graft_schema_versions"),
      " WHERE build_digest = ?"
    ),
    params = list(build_digest)
  )
  manifest_json <- canonical_manifest_json(manifest)
  if (nrow(existing) == 1L) {
    if (!identical(existing$manifest_json[[1L]], manifest_json)) {
      abort_backend_error(
        "A schema build digest is registered with different manifest content.",
        operation = "register_schema_version",
        build_digest = build_digest
      )
    }
    return(invisible(schema))
  }
  if (nrow(existing) > 1L) {
    abort_backend_error(
      "A schema build digest has multiple registry entries.",
      operation = "register_schema_version",
      build_digest = build_digest
    )
  }
  row <- data.frame(
    build_digest = build_digest,
    structural_digest = scalar_character(fingerprints$structural_digest),
    source_digest = scalar_character(fingerprints$source_digest),
    manifest_json = manifest_json,
    compiler_json = canonical_json(manifest$compiler),
    registered_at = as.POSIXct(now, tz = "UTC"),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(connection, "_graft_schema_versions", row)
  invisible(schema)
}

insert_schema_activation <- function(
  connection,
  schema,
  previous_build_digest,
  reason,
  now = Sys.time()
) {
  activation_order <- next_metadata_order(
    connection,
    "_graft_schema_activations",
    "activation_order"
  )
  row <- data.frame(
    activation_id = new_graft_id(now),
    build_digest = scalar_character(schema$manifest$fingerprints$build_digest),
    previous_build_digest = previous_build_digest,
    reason = reason,
    activation_order = activation_order,
    activated_at = as.POSIXct(now, tz = "UTC"),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(connection, "_graft_schema_activations", row)
  invisible(schema)
}

activate_schema <- function(
  connection,
  schema,
  reason = "compatible_rebuild",
  now = Sys.time()
) {
  metadata <- read_store_metadata(connection)
  previous_build_digest <- scalar_character(metadata$active_build_digest)
  build_digest <- scalar_character(schema$manifest$fingerprints$build_digest)
  if (identical(previous_build_digest, build_digest)) {
    return(invisible(schema))
  }
  now <- as.POSIXct(now, tz = "UTC")
  register_schema_version(connection, schema, now)
  manifest <- schema$manifest
  fingerprints <- manifest$fingerprints
  sql <- paste0(
    "UPDATE ",
    quote_identifier(connection, "_graft_store"),
    " SET active_structural_digest = ?, active_build_digest = ?, ",
    "source_digest = ?, build_digest = ?, manifest_json = ?, updated_at = ?"
  )
  DBI::dbExecute(
    connection,
    sql,
    params = list(
      scalar_character(fingerprints$structural_digest),
      build_digest,
      scalar_character(fingerprints$source_digest),
      build_digest,
      canonical_manifest_json(manifest),
      now
    )
  )
  insert_schema_activation(
    connection,
    schema,
    previous_build_digest,
    reason,
    now
  )
  invisible(schema)
}

next_metadata_order <- function(connection, table, column) {
  sql <- paste0(
    "SELECT COALESCE(MAX(",
    quote_identifier(connection, column),
    "), 0) + 1 AS next_order FROM ",
    quote_identifier(connection, table)
  )
  as.numeric(DBI::dbGetQuery(connection, sql)$next_order[[1L]])
}

read_store_metadata <- function(connection) {
  table <- quote_identifier(connection, "_graft_store")
  rows <- with_duckdb_error(
    "read_store_metadata",
    DBI::dbGetQuery(connection, paste0("SELECT * FROM ", table))
  )
  if (nrow(rows) != 1L) {
    abort_backend_error(
      paste0(
        "`_graft_store` must contain exactly one row; found ",
        nrow(rows),
        "."
      ),
      operation = "read_store_metadata",
      row_count = nrow(rows)
    )
  }
  as.list(rows[1L, , drop = FALSE])
}

verify_initialized_store <- function(
  store,
  activate = !isTRUE(store$read_only)
) {
  metadata <- read_store_metadata(store$connection)
  verify_store_format(metadata)
  verify_metadata_structure(store$connection)
  old_schema <- schema_from_manifest_json(metadata$manifest_json)
  validate_manifest_integrity(old_schema)
  validate_manifest_integrity(store$schema)
  diff <- kg_schema_diff(old_schema, store$schema)
  if (!isTRUE(diff$compatible)) {
    abort_schema_mismatch(diff)
  }

  active_build_digest <- scalar_character(metadata$active_build_digest)
  registry <- read_schema_version(store$connection, active_build_digest)
  if (
    nrow(registry) != 1L ||
      !identical(registry$manifest_json[[1L]], metadata$manifest_json)
  ) {
    abort_backend_error(
      "The active schema metadata does not match its schema registry entry.",
      operation = "verify_store",
      build_digest = active_build_digest
    )
  }

  build_digest <- scalar_character(
    store$schema$manifest$fingerprints$build_digest
  )
  if (
    !identical(active_build_digest, build_digest) &&
      isTRUE(activate) &&
      !isTRUE(store$read_only)
  ) {
    activate_schema(store$connection, store$schema)
  }
  invisible(store)
}

mark_store_verified <- function(store) {
  metadata <- read_store_metadata(store$connection)
  active_build_digest <- scalar_character(metadata$active_build_digest)
  store$verification <- list(
    manifest = unserialize(serialize(store$schema$manifest, NULL)),
    metadata = metadata,
    active_schema_version = read_schema_version(
      store$connection,
      active_build_digest
    )
  )
  invisible(store)
}

clear_store_verification <- function(store) {
  store$verification <- NULL
  invisible(store)
}

store_schema_is_verified <- function(store) {
  !is.null(store$verification) &&
    identical(
      store$verification$manifest,
      store$schema$manifest
    )
}

store_metadata_is_verified <- function(store) {
  if (is.null(store$verification)) {
    return(FALSE)
  }
  metadata <- read_store_metadata(store$connection)
  active_build_digest <- scalar_character(metadata$active_build_digest)
  identical(store$verification$metadata, metadata) &&
    identical(
      store$verification$active_schema_version,
      read_schema_version(store$connection, active_build_digest)
    )
}

verify_store_format <- function(metadata) {
  observed <- scalar_character(metadata$store_format_version)
  if (!identical(observed, graft_store_format_version)) {
    graft_abort(
      "graft_store_format_error",
      paste0(
        "Unsupported graft store format `",
        observed,
        "`; this version requires `",
        graft_store_format_version,
        "`."
      ),
      observed_version = observed,
      supported_version = graft_store_format_version
    )
  }
  invisible(metadata)
}

verify_metadata_structure <- function(connection) {
  definitions <- metadata_table_definitions()
  available <- duckdb_table_names(connection)
  missing <- setdiff(names(definitions), available)
  if (length(missing) > 0L) {
    abort_backend_error(
      paste0(
        "The initialized store is missing required metadata table(s): ",
        paste(missing, collapse = ", "),
        "."
      ),
      operation = "verify_store",
      missing_tables = missing
    )
  }
  for (table in names(definitions)) {
    expected <- vapply(
      definitions[[table]]$columns,
      \(.x) scalar_character(.x$name),
      character(1)
    )
    observed <- DBI::dbListFields(connection, table)
    missing_columns <- setdiff(expected, observed)
    if (length(missing_columns) > 0L) {
      abort_backend_error(
        paste0(
          "Metadata table `",
          table,
          "` is missing required column(s): ",
          paste(missing_columns, collapse = ", "),
          "."
        ),
        operation = "verify_store",
        table = table,
        missing_columns = missing_columns
      )
    }
  }
  invisible(connection)
}

read_schema_version <- function(connection, build_digest) {
  DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT * FROM ",
      quote_identifier(connection, "_graft_schema_versions"),
      " WHERE build_digest = ?"
    ),
    params = list(build_digest)
  )
}

schema_from_manifest_json <- function(manifest_json) {
  manifest <- tryCatch(
    jsonlite::fromJSON(
      scalar_character(manifest_json),
      simplifyVector = FALSE
    ),
    error = function(error) {
      abort_backend_error(
        paste0(
          "Could not parse the stored manifest JSON: ",
          conditionMessage(error)
        ),
        operation = "read_store_metadata",
        parent = error
      )
    }
  )
  validate_manifest_header(manifest, "<stored manifest>")
  new_kg_schema(manifest)
}

canonical_manifest_json <- function(manifest) {
  canonical_json(manifest)
}

canonical_json <- function(x) {
  as.character(jsonlite::toJSON(
    x,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    POSIXt = "ISO8601",
    UTC = TRUE,
    pretty = FALSE
  ))
}

new_store_id <- function() {
  alphabet <- c(letters, 0:9)
  random <- paste0(sample(alphabet, 20L, replace = TRUE), collapse = "")
  paste0(
    "graft-store-",
    format(Sys.time(), "%Y%m%dT%H%M%OS6", tz = "UTC"),
    "-",
    random
  )
}
