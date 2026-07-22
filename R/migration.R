graft_migration_plan_version <- "1.0.0"

#' Plan an additive schema migration
#'
#' Creates a deterministic, serializable plan bound to the initialized store's
#' identity, format, and exact active schema. Planning is read-only. The first
#' migration version supports compatible schema activations, new concrete
#' classes, nullable scalar slots, generated relation tables, and enum
#' additions. The plan includes deterministic schema-change details and
#' physical operations so schema-only changes remain reviewable.
#'
#' @param store An initialized `kg_store`.
#' @param new_schema A `kg_schema` object or manifest path.
#'
#' @return A deterministic, tamper-evident `kg_migration_plan` object. Its
#'   digest is revalidated before application.
#' @export
kg_plan_migration <- function(store, new_schema) {
  validate_migration_store(store)
  new_schema <- as_kg_schema(new_schema, "new_schema")
  validate_manifest_integrity(new_schema)
  validate_manifest_physical_names(new_schema)

  metadata <- read_store_metadata(store$connection)
  verify_store_format(metadata)
  verify_metadata_structure(store$connection)
  validate_active_store_schema(store, metadata)

  old_schema <- schema_from_manifest_json(metadata$manifest_json)
  diff <- kg_schema_diff(old_schema, new_schema)
  validate_supported_migration(diff)
  validate_additive_schema_shape(old_schema, new_schema, diff)
  validate_migration_transition(
    store$connection,
    old_schema,
    new_schema
  )
  operations <- migration_operations(old_schema, new_schema)
  validate_migration_operations(operations)

  data <- migration_plan_data(
    store_id = scalar_character(metadata$store_id),
    store_format_version = scalar_character(metadata$store_format_version),
    from_build_digest = scalar_character(metadata$active_build_digest),
    from_structural_digest = scalar_character(
      metadata$active_structural_digest
    ),
    to_build_digest = scalar_character(
      new_schema$manifest$fingerprints$build_digest
    ),
    to_structural_digest = scalar_character(
      new_schema$manifest$fingerprints$structural_digest
    ),
    classification = diff$classification,
    changes = migration_change_details(diff),
    operations = operations,
    manifest_json = canonical_manifest_json(new_schema$manifest)
  )
  digest <- migration_plan_digest(data)
  do.call(
    new_kg_migration_plan,
    c(
      data,
      list(
        plan_digest = digest,
        migration_id = migration_id_from_digest(digest)
      )
    )
  )
}

#' Apply a planned additive schema migration
#'
#' Revalidates the plan and its store preconditions before changing the store.
#' Supported DDL, schema registration and activation, graph-view recreation,
#' catalog verification, and migration recording commit in one DuckDB
#' transaction. The in-process store schema changes only after that commit.
#'
#' @param store An initialized, writable `kg_store`.
#' @param plan A `kg_migration_plan` returned by [kg_plan_migration()].
#'
#' @return `store`, invisibly, with its active schema updated.
#' @export
kg_apply_migration <- function(store, plan) {
  validate_migration_store(store)
  new_schema <- validate_migration_plan(plan)
  if (isTRUE(store$read_only)) {
    abort_migration_error(
      "graft_migration_read_only",
      "A read-only store cannot apply a schema migration.",
      store_path = store$path
    )
  }

  metadata <- read_store_metadata(store$connection)
  verify_store_format(metadata)
  verify_metadata_structure(store$connection)
  validate_migration_preconditions(store, plan, new_schema, metadata)

  with_duckdb_error(
    "apply_migration",
    DBI::dbWithTransaction(store$connection, {
      current <- read_store_metadata(store$connection)
      verify_store_format(current)
      verify_metadata_structure(store$connection)
      validate_migration_preconditions(store, plan, new_schema, current)
      refuse_applied_migration(store$connection, plan)

      drop_graph_views(store$connection)
      apply_migration_operations(store$connection, plan$operations)
      now <- as.POSIXct(Sys.time(), tz = "UTC")
      activate_schema(
        store$connection,
        new_schema,
        reason = "migration",
        now = now
      )
      create_graph_views(store$connection, new_schema)
      verify_manifest_physical_schema(store$connection, new_schema)
      verify_graph_views(store$connection)
      record_migration(store$connection, plan, now)
    })
  )
  store$schema <- new_schema
  invisible(store)
}

validate_migration_store <- function(store) {
  validate_kg_store(store)
  if (!duckdb_table_exists(store$connection, "_graft_store")) {
    abort_migration_error(
      "graft_migration_store_error",
      "The kg_store must be initialized before planning a migration.",
      store_path = store$path
    )
  }
  invisible(store)
}

validate_active_store_schema <- function(store, metadata) {
  active_build <- scalar_character(metadata$active_build_digest)
  active_structural <- scalar_character(metadata$active_structural_digest)
  active_manifest <- tryCatch(
    schema_from_manifest_json(metadata$manifest_json),
    error = function(error) {
      abort_migration_error(
        "graft_migration_store_error",
        "The active store manifest cannot be verified.",
        parent = error
      )
    }
  )
  validate_manifest_integrity(
    active_manifest,
    subclass = "graft_migration_store_error"
  )
  validate_manifest_integrity(
    store$schema,
    subclass = "graft_migration_store_error"
  )
  fingerprints <- active_manifest$manifest$fingerprints
  metadata_matches <- identical(
    scalar_character(fingerprints$build_digest),
    active_build
  ) &&
    identical(
      scalar_character(fingerprints$structural_digest),
      active_structural
    ) &&
    identical(scalar_character(metadata$build_digest), active_build) &&
    identical(
      scalar_character(metadata$source_digest),
      scalar_character(fingerprints$source_digest)
    )
  registered <- read_schema_version(store$connection, active_build)
  registry_matches <- nrow(registered) == 1L &&
    identical(
      registered$manifest_json[[1L]],
      scalar_character(metadata$manifest_json)
    )
  if (!metadata_matches || !registry_matches) {
    abort_migration_error(
      "graft_migration_store_error",
      "The active schema fingerprints, manifest, and registry disagree.",
      active_build_digest = active_build
    )
  }
  attached_build <- scalar_character(
    store$schema$manifest$fingerprints$build_digest
  )
  if (!identical(active_build, attached_build)) {
    abort_migration_error(
      "graft_migration_stale",
      paste0(
        "The store object is attached to schema `",
        attached_build,
        "`, but the active store schema is `",
        active_build,
        "`."
      ),
      expected_build_digest = active_build,
      observed_build_digest = attached_build
    )
  }
  invisible(store)
}

migration_plan_data <- function(
  store_id,
  store_format_version,
  from_build_digest,
  from_structural_digest,
  to_build_digest,
  to_structural_digest,
  classification,
  changes,
  operations,
  manifest_json
) {
  list(
    plan_version = graft_migration_plan_version,
    store_id = store_id,
    store_format_version = store_format_version,
    from_build_digest = from_build_digest,
    from_structural_digest = from_structural_digest,
    to_build_digest = to_build_digest,
    to_structural_digest = to_structural_digest,
    classification = classification,
    changes = changes,
    operations = operations,
    manifest_json = manifest_json
  )
}

migration_plan_digest <- function(data) {
  paste0(
    "sha256:",
    digest::digest(
      canonical_json(data),
      algo = "sha256",
      serialize = FALSE
    )
  )
}

migration_id_from_digest <- function(plan_digest) {
  paste0("graft-migration-", sub("^sha256:", "", plan_digest))
}

migration_plan_field_names <- function() {
  c(
    names(migration_plan_data(
      store_id = "",
      store_format_version = "",
      from_build_digest = "",
      from_structural_digest = "",
      to_build_digest = "",
      to_structural_digest = "",
      classification = "",
      changes = empty_schema_change_details(),
      operations = list(),
      manifest_json = ""
    )),
    "plan_digest",
    "migration_id"
  )
}

validate_migration_plan <- function(plan) {
  if (
    !inherits(plan, "kg_migration_plan") ||
      !is.list(plan) ||
      !identical(names(plan), migration_plan_field_names())
  ) {
    abort_migration_error(
      "graft_migration_plan_error",
      "`plan` must be an unmodified kg_migration_plan object."
    )
  }
  scalar_fields <- setdiff(
    migration_plan_field_names(),
    c("changes", "operations")
  )
  valid_scalars <- vapply(
    plan[scalar_fields],
    \(.x) is.character(.x) && length(.x) == 1L && !is.na(.x),
    logical(1)
  )
  if (
    !all(valid_scalars) ||
      !is.data.frame(plan$changes) ||
      !identical(names(plan$changes), names(empty_schema_change_details())) ||
      !all(vapply(plan$changes, is.character, logical(1))) ||
      !is.list(plan$operations)
  ) {
    abort_migration_error(
      "graft_migration_plan_error",
      "The migration plan contains invalid fields."
    )
  }
  if (!identical(plan$plan_version, graft_migration_plan_version)) {
    abort_migration_error(
      "graft_migration_plan_error",
      paste0(
        "Unsupported migration plan version `",
        plan$plan_version,
        "`."
      ),
      observed_version = plan$plan_version,
      supported_version = graft_migration_plan_version
    )
  }
  data <- unclass(plan)[names(plan)[
    !names(plan) %in%
      c(
        "plan_digest",
        "migration_id"
      )
  ]]
  expected_digest <- tryCatch(
    migration_plan_digest(data),
    error = function(error) {
      abort_migration_error(
        "graft_migration_plan_error",
        "The migration plan contains data that cannot be verified.",
        parent = error
      )
    }
  )
  expected_id <- migration_id_from_digest(expected_digest)
  if (
    !identical(plan$plan_digest, expected_digest) ||
      !identical(plan$migration_id, expected_id)
  ) {
    abort_migration_error(
      "graft_migration_plan_error",
      "The migration plan digest is invalid; the plan may have been modified.",
      expected_digest = expected_digest,
      observed_digest = plan$plan_digest
    )
  }

  schema <- tryCatch(
    schema_from_manifest_json(plan$manifest_json),
    error = function(error) {
      abort_migration_error(
        "graft_migration_plan_error",
        "The migration plan contains an invalid target manifest.",
        parent = error
      )
    }
  )
  if (
    !identical(canonical_manifest_json(schema$manifest), plan$manifest_json)
  ) {
    abort_migration_error(
      "graft_migration_plan_error",
      "The target manifest JSON is not in Graft's canonical form."
    )
  }
  validate_manifest_integrity(schema)
  fingerprints <- schema$manifest$fingerprints
  if (
    !identical(
      scalar_character(fingerprints$build_digest),
      plan$to_build_digest
    ) ||
      !identical(
        scalar_character(fingerprints$structural_digest),
        plan$to_structural_digest
      )
  ) {
    abort_migration_error(
      "graft_migration_plan_error",
      "The target manifest fingerprints do not match the migration plan."
    )
  }
  validate_manifest_physical_names(schema)
  schema
}

validate_supported_migration <- function(diff) {
  if (!diff$classification %in% c("compatible", "additive")) {
    abort_migration_error(
      "graft_migration_unsupported",
      paste0(
        "Cannot plan a `",
        diff$classification,
        "` schema change; only compatible and additive changes are supported."
      ),
      classification = diff$classification,
      schema_diff = diff
    )
  }
  supported_rules <- c(
    "optional_class_added",
    "optional_slot_added",
    "table_added",
    "nullable_column_added",
    "relation_added",
    "enum_added",
    "enum_value_added",
    "new_class_validation_added",
    "graph_projection_added",
    "graph_projection_value_added"
  )
  unsupported <- setdiff(unique(diff$details$rule), supported_rules)
  if (length(unsupported) > 0L) {
    abort_migration_error(
      "graft_migration_unsupported",
      paste0(
        "The additive schema change contains unsupported rule(s): ",
        paste(sort(unsupported), collapse = ", "),
        "."
      ),
      classification = diff$classification,
      unsupported_rules = sort(unsupported),
      schema_diff = diff
    )
  }
  invisible(diff)
}

migration_change_details <- function(diff) {
  changes <- diff$details
  rownames(changes) <- NULL
  changes
}

validate_additive_schema_shape <- function(old_schema, new_schema, diff) {
  if (identical(diff$classification, "compatible")) {
    return(invisible(new_schema))
  }
  old <- old_schema$manifest
  new <- new_schema$manifest
  added_classes <- sort(setdiff(names(new$classes), names(old$classes)))
  added_tables <- sort(setdiff(names(new$tables), names(old$tables)))
  old_relation_names <- names(relation_map(old$relations))
  new_relation_names <- names(relation_map(new$relations))
  added_relation_names <- sort(setdiff(
    new_relation_names,
    old_relation_names
  ))
  if (!setequal(added_classes, added_tables)) {
    abort_additive_shape(
      "New physical tables must correspond exactly to new concrete classes.",
      added_classes = added_classes,
      added_tables = added_tables
    )
  }
  validate_graph_projection_changes(
    diff,
    added_classes,
    added_relation_names
  )

  expected_relations <- character()
  for (record_class in added_classes) {
    validate_new_class_table(new, record_class)
    slots <- new$classes[[record_class]]$slots
    multivalue_slots <- names(Filter(
      \(.x) scalar_logical(.x$multivalued),
      slots
    ))
    for (slot_name in multivalue_slots) {
      expected_relations <- c(
        expected_relations,
        validate_new_relation_mapping(new, record_class, slot_name)
      )
    }
  }

  common_classes <- sort(intersect(names(old$classes), names(new$classes)))
  for (record_class in common_classes) {
    old_slots <- old$classes[[record_class]]$slots
    new_slots <- new$classes[[record_class]]$slots
    added_slots <- sort(setdiff(names(new_slots), names(old_slots)))
    old_columns <- schema_column_map(old$tables[[record_class]]$columns)
    new_columns <- schema_column_map(new$tables[[record_class]]$columns)
    added_columns <- sort(setdiff(names(new_columns), names(old_columns)))
    expected_columns <- character()
    for (slot_name in added_slots) {
      slot <- new_slots[[slot_name]]
      if (scalar_logical(slot$multivalued)) {
        expected_relations <- c(
          expected_relations,
          validate_new_relation_mapping(new, record_class, slot_name)
        )
        next
      }
      column_name <- scalar_character(slot$column)
      if (is.na(column_name) || !nzchar(column_name)) {
        abort_additive_shape(
          "A new scalar slot must declare one physical column.",
          record_class = record_class,
          slot = slot_name
        )
      }
      expected_columns <- c(expected_columns, column_name)
      validate_slot_column_mapping(
        slot,
        new_columns[[column_name]],
        record_class,
        slot_name
      )
    }
    if (!setequal(expected_columns, added_columns)) {
      abort_additive_shape(
        paste0(
          "Added columns for class `",
          record_class,
          "` must correspond exactly to its new scalar slots."
        ),
        record_class = record_class,
        expected_columns = sort(expected_columns),
        added_columns = added_columns
      )
    }
  }

  old_relations <- relation_map(old$relations)
  new_relations <- relation_map(new$relations)
  added_relations <- sort(setdiff(names(new_relations), names(old_relations)))
  if (!setequal(expected_relations, added_relations)) {
    abort_additive_shape(
      paste0(
        "New relation tables must correspond exactly to new multivalued ",
        "class slots."
      ),
      expected_relations = sort(expected_relations),
      added_relations = added_relations
    )
  }
  invisible(new_schema)
}

validate_graph_projection_changes <- function(
  diff,
  added_classes,
  added_relations
) {
  changes <- diff$details[
    diff$details$object_type == "graph_projection",
    ,
    drop = FALSE
  ]
  if (nrow(changes) == 0L) {
    return(invisible(diff))
  }
  for (index in seq_len(nrow(changes))) {
    value <- tryCatch(
      jsonlite::fromJSON(
        changes$new_summary[[index]],
        simplifyVector = FALSE
      ),
      error = \(.x) NULL
    )
    values <- empty_character(value)
    allowed <- if (grepl("/object_relations", changes$path[[index]])) {
      added_relations
    } else {
      added_classes
    }
    if (
      length(values) == 0L ||
        !all(values %in% allowed)
    ) {
      abort_additive_shape(
        paste0(
          "Graph-projection additions must be derived from newly added ",
          "concrete classes or generated relations."
        ),
        path = changes$path[[index]],
        projected_values = values,
        added_classes = added_classes,
        added_relations = added_relations
      )
    }
  }
  invisible(diff)
}

validate_new_class_table <- function(manifest, record_class) {
  contract <- manifest$classes[[record_class]]
  table <- manifest$tables[[record_class]]
  if (
    is.null(table) ||
      !identical(scalar_character(table$class), record_class) ||
      !identical(
        scalar_character(table$name),
        scalar_character(contract$table)
      )
  ) {
    abort_additive_shape(
      "A new concrete class must have one matching manifest table.",
      record_class = record_class
    )
  }
  scalar_slots <- Filter(
    \(.x) !scalar_logical(.x$multivalued),
    contract$slots
  )
  columns <- schema_column_map(table$columns)
  column_slots <- vapply(
    columns,
    \(.x) scalar_character(.x$slot),
    character(1)
  )
  if (!setequal(names(scalar_slots), column_slots)) {
    abort_additive_shape(
      "A new class table must materialize every scalar class slot exactly once.",
      record_class = record_class
    )
  }
  for (slot_name in names(scalar_slots)) {
    slot <- scalar_slots[[slot_name]]
    column_name <- scalar_character(slot$column)
    validate_slot_column_mapping(
      slot,
      columns[[column_name]],
      record_class,
      slot_name
    )
  }
  invisible(table)
}

validate_slot_column_mapping <- function(
  slot,
  column,
  record_class,
  slot_name
) {
  column_name <- scalar_character(slot$column)
  types_match <- tryCatch(
    identical(
      safe_duckdb_type(scalar_character(column$type)),
      safe_duckdb_type(scalar_character(slot$relational_type))
    ),
    error = function(error) {
      abort_additive_shape(
        "A new scalar slot uses an unsupported physical type.",
        record_class = record_class,
        slot = slot_name,
        column = column_name,
        parent = error
      )
    }
  )
  matches <- !is.null(column) &&
    identical(scalar_character(column$name), column_name) &&
    identical(scalar_character(column$slot), slot_name) &&
    types_match &&
    identical(
      scalar_logical(column$nullable, default = TRUE),
      !scalar_logical(slot$required)
    ) &&
    identical(
      scalar_logical(column$primary_key),
      scalar_logical(slot$identifier)
    ) &&
    identical(column$foreign_key, slot$foreign_key)
  if (!matches) {
    abort_additive_shape(
      "A new scalar slot and its physical column definition disagree.",
      record_class = record_class,
      slot = slot_name,
      column = column_name
    )
  }
  invisible(column)
}

validate_new_relation_mapping <- function(manifest, record_class, slot_name) {
  relation <- tryCatch(
    validate_manifest_relation_contract(
      manifest,
      record_class,
      slot_name
    ),
    graft_schema_integrity_error = function(error) {
      abort_additive_shape(
        conditionMessage(error),
        record_class = record_class,
        slot = slot_name,
        parent = error
      )
    }
  )
  scalar_character(relation$name)
}

generated_relation_table_name <- function(owner_table, slot_name) {
  snake_slot <- gsub(
    "([a-z0-9])([A-Z])",
    "\\1_\\2",
    slot_name,
    perl = TRUE
  )
  snake_slot <- gsub("[^A-Za-z0-9]+", "_", snake_slot, perl = TRUE)
  snake_slot <- gsub("^_+|_+$", "", snake_slot, perl = TRUE)
  paste0(owner_table, "__", tolower(snake_slot))
}

generated_relation_columns <- function(record_class, slot, kind) {
  if (identical(kind, "object")) {
    return(list(
      list(
        name = "id",
        type = "VARCHAR",
        nullable = FALSE,
        primary_key = TRUE
      ),
      list(
        name = "subject",
        type = "VARCHAR",
        nullable = FALSE,
        foreign_key = list(class = record_class, slot = "id")
      ),
      list(
        name = "object",
        type = "VARCHAR",
        nullable = FALSE,
        foreign_key = list(
          class = scalar_character(slot$range),
          slot = "id"
        )
      ),
      list(name = "position", type = "BIGINT", nullable = TRUE),
      list(name = "created_at", type = "TIMESTAMP", nullable = TRUE)
    ))
  }
  list(
    list(
      name = "owner_id",
      type = "VARCHAR",
      nullable = FALSE,
      foreign_key = list(class = record_class, slot = "id")
    ),
    list(name = "position", type = "BIGINT", nullable = TRUE),
    list(
      name = "value",
      type = scalar_character(slot$relational_type),
      nullable = FALSE
    )
  )
}

abort_additive_shape <- function(message, ...) {
  abort_migration_error(
    "graft_migration_unsupported",
    message,
    ...
  )
}

validate_migration_transition <- function(
  connection,
  old_schema,
  new_schema
) {
  old_build <- scalar_character(
    old_schema$manifest$fingerprints$build_digest
  )
  new_build <- scalar_character(
    new_schema$manifest$fingerprints$build_digest
  )
  old_manifest <- canonical_manifest_json(old_schema$manifest)
  new_manifest <- canonical_manifest_json(new_schema$manifest)
  if (identical(old_build, new_build)) {
    if (identical(old_manifest, new_manifest)) {
      abort_migration_error(
        "graft_migration_noop",
        "The target schema is already active; there is nothing to migrate.",
        build_digest = new_build
      )
    }
    abort_migration_error(
      "graft_migration_plan_error",
      paste0(
        "The target reuses active build digest `",
        new_build,
        "` for different manifest content."
      ),
      build_digest = new_build
    )
  }

  registered <- read_schema_version(connection, new_build)
  if (
    nrow(registered) > 1L ||
      (nrow(registered) == 1L &&
        !identical(registered$manifest_json[[1L]], new_manifest))
  ) {
    abort_migration_error(
      "graft_migration_plan_error",
      paste0(
        "Target build digest `",
        new_build,
        "` is registered with different manifest content."
      ),
      build_digest = new_build
    )
  }
  invisible(new_schema)
}

migration_operations <- function(old_schema, new_schema) {
  old <- old_schema$manifest
  new <- new_schema$manifest
  operations <- list()

  added_tables <- sort(setdiff(names(new$tables), names(old$tables)))
  for (class_name in added_tables) {
    operations[[length(operations) + 1L]] <- list(
      kind = "create_table",
      class = class_name,
      table = scalar_character(new$tables[[class_name]]$name),
      definition = canonical_schema_change_value(new$tables[[class_name]])
    )
  }

  common_tables <- sort(intersect(names(old$tables), names(new$tables)))
  for (class_name in common_tables) {
    old_columns <- schema_column_map(old$tables[[class_name]]$columns)
    new_columns <- schema_column_map(new$tables[[class_name]]$columns)
    added_columns <- sort(setdiff(names(new_columns), names(old_columns)))
    for (column_name in added_columns) {
      operations[[length(operations) + 1L]] <- list(
        kind = "add_column",
        class = class_name,
        table = scalar_character(new$tables[[class_name]]$name),
        column = canonical_schema_change_value(new_columns[[column_name]])
      )
    }
  }

  old_relations <- relation_map(old$relations)
  new_relations <- relation_map(new$relations)
  added_relations <- sort(setdiff(names(new_relations), names(old_relations)))
  for (relation_name in added_relations) {
    operations[[length(operations) + 1L]] <- list(
      kind = "create_relation",
      relation = relation_name,
      table = scalar_character(new_relations[[relation_name]]$table),
      definition = canonical_schema_change_value(
        new_relations[[relation_name]]
      )
    )
  }

  if (length(operations) == 0L) {
    return(list())
  }
  keys <- vapply(operations, canonical_json, character(1))
  unname(operations[order(keys, method = "radix")])
}

validate_migration_operations <- function(operations) {
  tryCatch(
    {
      for (operation in operations) {
        kind <- scalar_character(operation$kind)
        columns <- if (identical(kind, "add_column")) {
          list(operation$column)
        } else if (kind %in% c("create_table", "create_relation")) {
          operation$definition$columns
        } else {
          abort_schema_error(
            paste0("Unknown migration operation `", kind, "`.")
          )
        }
        for (column in columns) {
          safe_duckdb_type(scalar_character(column$type))
        }
        if (
          identical(kind, "add_column") &&
            (!scalar_logical(operation$column$nullable, default = TRUE) ||
              scalar_logical(operation$column$primary_key))
        ) {
          abort_schema_error(
            "Only nullable, non-primary-key columns can be added."
          )
        }
      }
    },
    error = function(error) {
      if (inherits(error, "graft_migration_unsupported")) {
        stop(error)
      }
      abort_migration_error(
        "graft_migration_unsupported",
        paste0(
          "The migration contains an invalid additive operation: ",
          conditionMessage(error)
        ),
        parent = error
      )
    }
  )
  invisible(operations)
}

validate_migration_preconditions <- function(
  store,
  plan,
  new_schema,
  metadata
) {
  observed <- list(
    store_id = scalar_character(metadata$store_id),
    store_format_version = scalar_character(metadata$store_format_version),
    from_build_digest = scalar_character(metadata$active_build_digest),
    from_structural_digest = scalar_character(
      metadata$active_structural_digest
    )
  )
  expected <- plan[names(observed)]
  matches <- vapply(
    names(observed),
    \(.x) identical(observed[[.x]], expected[[.x]]),
    logical(1)
  )
  if (!all(matches)) {
    field <- names(matches)[!matches][[1L]]
    abort_migration_error(
      "graft_migration_stale",
      paste0(
        "The migration plan is stale: `",
        field,
        "` no longer matches the store."
      ),
      field = field,
      expected = expected[[field]],
      observed = observed[[field]]
    )
  }
  validate_active_store_schema(store, metadata)

  old_schema <- schema_from_manifest_json(metadata$manifest_json)
  diff <- kg_schema_diff(old_schema, new_schema)
  validate_supported_migration(diff)
  validate_additive_schema_shape(old_schema, new_schema, diff)
  validate_migration_transition(
    store$connection,
    old_schema,
    new_schema
  )
  operations <- migration_operations(old_schema, new_schema)
  validate_migration_operations(operations)
  if (
    !identical(diff$classification, plan$classification) ||
      !identical(migration_change_details(diff), plan$changes) ||
      !identical(operations, plan$operations)
  ) {
    abort_migration_error(
      "graft_migration_plan_error",
      "The migration plan does not match its source and target schemas."
    )
  }
  invisible(plan)
}

refuse_applied_migration <- function(connection, plan) {
  rows <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT migration_id FROM ",
      quote_identifier(connection, "_graft_migrations"),
      " WHERE plan_digest = ?"
    ),
    params = list(plan$plan_digest)
  )
  if (nrow(rows) > 0L) {
    abort_migration_error(
      "graft_migration_stale",
      "The migration plan has already been applied.",
      migration_id = plan$migration_id
    )
  }
  invisible(plan)
}

apply_migration_operations <- function(connection, operations) {
  for (operation in operations) {
    kind <- scalar_character(operation$kind)
    if (identical(kind, "create_table")) {
      create_manifest_table(connection, operation$definition)
    } else if (identical(kind, "add_column")) {
      add_manifest_column(
        connection,
        scalar_character(operation$table),
        operation$column
      )
    } else if (identical(kind, "create_relation")) {
      create_manifest_relation_table(connection, operation$definition)
    } else {
      abort_migration_error(
        "graft_migration_plan_error",
        paste0("Unknown migration operation `", kind, "`."),
        operation = operation
      )
    }
  }
  invisible(connection)
}

verify_manifest_physical_schema <- function(connection, schema) {
  definitions <- c(
    lapply(schema$manifest$tables, function(table) {
      list(
        definition = table,
        unique_constraints = list(),
        indexes = manifest_table_indexes(table)
      )
    }),
    lapply(schema$manifest$relations, function(relation) {
      list(
        definition = list(
          name = relation$table,
          columns = relation$columns
        ),
        unique_constraints = relation_unique_constraints(relation),
        indexes = manifest_relation_indexes(relation)
      )
    })
  )
  for (entry in definitions) {
    definition <- entry$definition
    table <- scalar_character(definition$name)
    if (!duckdb_table_exists(connection, table)) {
      abort_backend_error(
        paste0("The migrated store is missing table `", table, "`."),
        operation = "verify_migration",
        table = table
      )
    }
    observed <- DBI::dbGetQuery(
      connection,
      paste0(
        "PRAGMA table_info(",
        as.character(DBI::dbQuoteString(connection, table)),
        ")"
      )
    )
    expected <- schema_column_map(definition$columns)
    observed_names <- observed$name
    if (!setequal(names(expected), observed_names)) {
      abort_backend_error(
        paste0("The migrated table `", table, "` has unexpected columns."),
        operation = "verify_migration",
        table = table,
        expected_columns = names(expected),
        observed_columns = observed_names
      )
    }
    for (column_name in names(expected)) {
      column <- expected[[column_name]]
      row <- observed[observed$name == column_name, , drop = FALSE]
      expected_type <- safe_duckdb_type(scalar_character(column$type))
      expected_nullable <- scalar_logical(column$nullable, default = TRUE)
      expected_primary <- scalar_logical(column$primary_key)
      observed_nullable <- !isTRUE(row$notnull[[1L]])
      if (
        nrow(row) != 1L ||
          !physical_type_matches(row$type[[1L]], expected_type) ||
          !identical(observed_nullable, expected_nullable) ||
          !identical(isTRUE(row$pk[[1L]]), expected_primary)
      ) {
        abort_backend_error(
          paste0(
            "The migrated column `",
            table,
            ".",
            column_name,
            "` does not match its manifest definition."
          ),
          operation = "verify_migration",
          table = table,
          column = column_name
        )
      }
    }
    verify_manifest_unique_constraints(
      connection,
      table,
      entry$unique_constraints
    )
    verify_manifest_indexes(connection, table, entry$indexes)
  }
  invisible(connection)
}

physical_type_matches <- function(observed, expected) {
  observed <- toupper(as.character(observed))
  identical(observed, expected) ||
    (identical(expected, "DECIMAL") && grepl("^DECIMAL\\(", observed))
}

verify_manifest_unique_constraints <- function(
  connection,
  table,
  expected
) {
  observed <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT constraint_column_names FROM duckdb_constraints() ",
      "WHERE schema_name = 'main' AND table_name = ? ",
      "AND constraint_type = 'UNIQUE'"
    ),
    params = list(table)
  )$constraint_column_names
  keys <- function(values) {
    sort(vapply(
      values,
      \(.x) paste(.x, collapse = "\r"),
      character(1)
    ))
  }
  if (!identical(keys(observed), keys(expected))) {
    abort_backend_error(
      paste0("The migrated table `", table, "` has unexpected constraints."),
      operation = "verify_migration",
      table = table,
      expected_unique_constraints = expected,
      observed_unique_constraints = observed
    )
  }
  invisible(connection)
}

verify_manifest_indexes <- function(connection, table, expected) {
  observed <- DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT index_name FROM duckdb_indexes() ",
      "WHERE schema_name = 'main' AND table_name = ?"
    ),
    params = list(table)
  )$index_name
  expected_names <- vapply(
    expected,
    \(.x) graft_index_name(table, as.character(.x)),
    character(1)
  )
  missing <- setdiff(expected_names, observed)
  if (length(missing) > 0L) {
    abort_backend_error(
      paste0("The migrated table `", table, "` is missing expected indexes."),
      operation = "verify_migration",
      table = table,
      missing_indexes = missing
    )
  }
  invisible(connection)
}

record_migration <- function(connection, plan, now) {
  row <- data.frame(
    migration_id = plan$migration_id,
    plan_digest = plan$plan_digest,
    from_build_digest = plan$from_build_digest,
    to_build_digest = plan$to_build_digest,
    from_structural_digest = plan$from_structural_digest,
    to_structural_digest = plan$to_structural_digest,
    classification = plan$classification,
    changes_json = canonical_json(plan$changes),
    operations_json = canonical_json(plan$operations),
    application_order = next_metadata_order(
      connection,
      "_graft_migrations",
      "application_order"
    ),
    applied_at = as.POSIXct(now, tz = "UTC"),
    stringsAsFactors = FALSE
  )
  DBI::dbAppendTable(connection, "_graft_migrations", row)
  invisible(plan)
}
