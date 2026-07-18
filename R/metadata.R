graft_store_format_version <- "1.0.0"

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
        ddl_column("source_digest", "VARCHAR", nullable = FALSE),
        ddl_column("build_digest", "VARCHAR", nullable = FALSE),
        ddl_column("manifest_json", "VARCHAR", nullable = FALSE),
        ddl_column("created_at", "TIMESTAMP", nullable = FALSE),
        ddl_column("updated_at", "TIMESTAMP", nullable = FALSE)
      )
    ),
    `_graft_batches` = list(
      columns = list(
        ddl_column("batch_id", "VARCHAR", nullable = FALSE, primary_key = TRUE),
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
        c("producer", "idempotency_key")
      ),
      indexes = list(
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
        ddl_column("observed_at", "TIMESTAMP", nullable = FALSE)
      ),
      constraints = list(
        c("record_id", "class", "batch_id")
      ),
      indexes = list(
        c("batch_id")
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
    source_digest = scalar_character(fingerprints$source_digest),
    build_digest = scalar_character(fingerprints$build_digest),
    manifest_json = canonical_manifest_json(manifest),
    created_at = now,
    updated_at = now,
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(store$connection, "_graft_store", row)
  invisible(store)
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

verify_initialized_store <- function(store) {
  metadata <- read_store_metadata(store$connection)
  old_schema <- schema_from_manifest_json(metadata$manifest_json)
  diff <- kg_schema_diff(old_schema, store$schema)
  if (!isTRUE(diff$compatible)) {
    abort_schema_mismatch(diff)
  }

  fingerprints <- store$schema$manifest$fingerprints
  source_digest <- scalar_character(fingerprints$source_digest)
  build_digest <- scalar_character(fingerprints$build_digest)
  manifest_json <- canonical_manifest_json(store$schema$manifest)
  changed <- !identical(
    scalar_character(metadata$source_digest),
    source_digest
  ) ||
    !identical(scalar_character(metadata$build_digest), build_digest) ||
    !identical(scalar_character(metadata$manifest_json), manifest_json)

  if (changed && !isTRUE(store$read_only)) {
    update_store_metadata(
      store$connection,
      source_digest,
      build_digest,
      manifest_json
    )
  }
  invisible(store)
}

update_store_metadata <- function(
  connection,
  source_digest,
  build_digest,
  manifest_json
) {
  sql <- paste0(
    "UPDATE ",
    quote_identifier(connection, "_graft_store"),
    " SET ",
    quote_identifier(connection, "source_digest"),
    " = ?, ",
    quote_identifier(connection, "build_digest"),
    " = ?, ",
    quote_identifier(connection, "manifest_json"),
    " = ?, ",
    quote_identifier(connection, "updated_at"),
    " = ?"
  )
  with_duckdb_error(
    "update_store_metadata",
    DBI::dbExecute(
      connection,
      sql,
      params = list(
        source_digest,
        build_digest,
        manifest_json,
        as.POSIXct(Sys.time(), tz = "UTC")
      )
    )
  )
  invisible(connection)
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
  as.character(jsonlite::toJSON(
    manifest,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    POSIXt = "ISO8601",
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
