#' Load a compiled graft schema manifest
#'
#' Loading a manifest is implemented entirely in R and does not initialize
#' Python or require `linkml_runtime`.
#'
#' @param path Path to a compiled `.graft.json` manifest.
#'
#' @return An immutable `kg_schema` S3 object.
#' @export
kg_schema <- function(path) {
  if (
    !is.character(path) ||
      length(path) != 1L ||
      is.na(path) ||
      !nzchar(path)
  ) {
    abort_schema_error(
      "`path` must be one non-empty manifest path.",
      argument = "path"
    )
  }
  if (!file.exists(path)) {
    abort_schema_error(
      paste0("Schema manifest does not exist: `", path, "`."),
      manifest_path = path
    )
  }
  normalized_path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  manifest <- tryCatch(
    jsonlite::fromJSON(normalized_path, simplifyVector = FALSE),
    error = function(error) {
      abort_schema_error(
        paste0(
          "Could not parse schema manifest `",
          normalized_path,
          "`: ",
          conditionMessage(error)
        ),
        manifest_path = normalized_path,
        parent = error
      )
    }
  )
  validate_manifest_header(manifest, normalized_path)
  new_kg_schema(manifest, normalized_path)
}

validate_manifest_header <- function(manifest, path) {
  required <- c(
    "manifest_version",
    "relational_mapping_version",
    "schema",
    "classes",
    "slots",
    "enums",
    "tables",
    "relations",
    "graph_projections",
    "validation_invariants",
    "compiler",
    "fingerprints"
  )
  missing <- setdiff(required, names(manifest))
  if (length(missing) > 0L) {
    abort_schema_error(
      paste0(
        "Schema manifest `",
        path,
        "` is missing required field(s): ",
        paste(missing, collapse = ", "),
        "."
      ),
      manifest_path = path,
      missing_fields = missing
    )
  }
  digests <- manifest$fingerprints
  required_digests <- c(
    "structural_digest",
    "source_digest",
    "build_digest"
  )
  missing_digests <- setdiff(required_digests, names(digests))
  if (length(missing_digests) > 0L) {
    abort_schema_error(
      paste0(
        "Schema manifest `",
        path,
        "` is missing fingerprint(s): ",
        paste(missing_digests, collapse = ", "),
        "."
      ),
      manifest_path = path,
      missing_fingerprints = missing_digests
    )
  }
  invisible(manifest)
}

validate_manifest_integrity <- function(schema, subclass = NULL) {
  if (!inherits(schema, "kg_schema") || !is.list(schema$manifest)) {
    abort_schema_integrity(
      "Schema integrity validation requires a kg_schema object.",
      subclass = subclass
    )
  }
  manifest <- schema$manifest
  fingerprints <- manifest$fingerprints
  fingerprint_names <- c(
    "structural_digest",
    "source_digest",
    "build_digest"
  )
  invalid_fingerprints <- fingerprint_names[
    !vapply(
      fingerprints[fingerprint_names],
      \(.x) {
        value <- scalar_character(.x)
        !is.na(value) && grepl("^sha256:[0-9a-f]{64}$", value)
      },
      logical(1)
    )
  ]
  if (length(invalid_fingerprints) > 0L) {
    abort_schema_integrity(
      paste0(
        "Schema fingerprint(s) are not canonical SHA-256 digests: ",
        paste(invalid_fingerprints, collapse = ", "),
        "."
      ),
      invalid_fingerprints = invalid_fingerprints,
      rule = "canonical_schema_fingerprints",
      subclass = subclass
    )
  }

  declared_digest <- scalar_character(fingerprints$structural_digest)
  computed_digest <- manifest_structural_digest(manifest)
  if (!identical(declared_digest, computed_digest)) {
    abort_schema_integrity(
      paste0(
        "The declared structural digest does not match the manifest ",
        "content."
      ),
      declared_structural_digest = declared_digest,
      computed_structural_digest = computed_digest,
      rule = "structural_digest_content_mismatch",
      subclass = subclass
    )
  }

  validate_global_slot_types(manifest, subclass)
  validate_manifest_physical_contracts(manifest, subclass)
  invisible(schema)
}

validate_global_slot_types <- function(manifest, subclass) {
  for (slot_name in names(manifest$slots)) {
    validate_compiler_slot_type(
      manifest$slots[[slot_name]],
      slot_name = slot_name,
      subclass = subclass
    )
  }
  invisible(manifest)
}

validate_compiler_slot_type <- function(
  slot,
  slot_name,
  record_class = NULL,
  subclass = NULL
) {
  range <- scalar_character(slot$range, "string")
  object_reference <- scalar_logical(slot$object_reference)
  expected <- if (object_reference) {
    "VARCHAR"
  } else {
    switch(
      range,
      boolean = "BOOLEAN",
      date = "DATE",
      datetime = "TIMESTAMP",
      decimal = "DECIMAL",
      double = "DOUBLE",
      float = "DOUBLE",
      integer = "BIGINT",
      time = "TIME",
      "VARCHAR"
    )
  }
  observed <- scalar_character(slot$relational_type)
  if (!identical(observed, expected)) {
    qualified <- if (is.null(record_class)) {
      slot_name
    } else {
      paste(record_class, slot_name, sep = ".")
    }
    abort_schema_integrity(
      paste0(
        if (object_reference) "Object-reference slot `" else "Slot `",
        qualified,
        "` must use relational type `",
        expected,
        "`."
      ),
      record_class = record_class,
      slot = slot_name,
      range = range,
      observed_type = observed,
      expected_type = expected,
      rule = if (object_reference) {
        "object_reference_varchar"
      } else {
        "slot_relational_type_contract"
      },
      subclass = subclass
    )
  }
  invisible(slot)
}

validate_manifest_physical_contracts <- function(manifest, subclass) {
  class_names <- names(manifest$classes)
  if (!setequal(class_names, names(manifest$tables))) {
    abort_schema_integrity(
      "Concrete classes and manifest tables must correspond exactly.",
      classes = sort(class_names),
      tables = sort(names(manifest$tables)),
      rule = "class_table_correspondence",
      subclass = subclass
    )
  }

  expected_relations <- character()
  for (record_class in class_names) {
    contract <- manifest$classes[[record_class]]
    table <- manifest$tables[[record_class]]
    if (
      !identical(scalar_character(table$class), record_class) ||
        !identical(
          scalar_character(table$name),
          scalar_character(contract$table)
        ) ||
        !identical(
          scalar_character(table$role),
          scalar_character(contract$role)
        )
    ) {
      abort_schema_integrity(
        paste0(
          "Class `",
          record_class,
          "` and its physical table metadata disagree."
        ),
        record_class = record_class,
        rule = "class_table_metadata",
        subclass = subclass
      )
    }

    slots <- contract$slots
    for (slot_name in names(slots)) {
      validate_compiler_slot_type(
        slots[[slot_name]],
        slot_name,
        record_class,
        subclass
      )
    }
    scalar_slots <- Filter(
      \(.x) !scalar_logical(.x$multivalued),
      slots
    )
    columns <- table$columns
    column_names <- vapply(
      columns,
      \(.x) scalar_character(.x$name),
      character(1)
    )
    if (anyNA(column_names) || anyDuplicated(column_names)) {
      abort_schema_integrity(
        paste0("Table for class `", record_class, "` has invalid columns."),
        record_class = record_class,
        rule = "unique_table_columns",
        subclass = subclass
      )
    }
    column_map <- stats::setNames(columns, column_names)
    expected_columns <- vapply(
      scalar_slots,
      \(.x) scalar_character(.x$column),
      character(1)
    )
    if (
      anyNA(expected_columns) ||
        anyDuplicated(expected_columns) ||
        !setequal(column_names, expected_columns)
    ) {
      abort_schema_integrity(
        paste0(
          "Scalar slots for class `",
          record_class,
          "` must correspond exactly to physical columns."
        ),
        record_class = record_class,
        rule = "scalar_column_correspondence",
        subclass = subclass
      )
    }

    for (slot_name in names(scalar_slots)) {
      validate_manifest_scalar_slot(
        scalar_slots[[slot_name]],
        column_map[[expected_columns[[slot_name]]]],
        record_class,
        slot_name,
        subclass
      )
    }

    multivalue_slots <- Filter(
      \(.x) scalar_logical(.x$multivalued),
      slots
    )
    relation_names <- character()
    for (slot_name in names(multivalue_slots)) {
      relation <- validate_manifest_relation_contract(
        manifest,
        record_class,
        slot_name,
        subclass
      )
      relation_names <- c(relation_names, scalar_character(relation$name))
    }
    declared_relations <- empty_character(contract$relations)
    if (
      anyDuplicated(declared_relations) ||
        !setequal(declared_relations, relation_names)
    ) {
      abort_schema_integrity(
        paste0(
          "Class `",
          record_class,
          "` relation metadata does not match its multivalued slots."
        ),
        record_class = record_class,
        rule = "class_relation_correspondence",
        subclass = subclass
      )
    }
    expected_relations <- c(expected_relations, relation_names)
  }

  observed_relations <- vapply(
    manifest$relations,
    \(.x) scalar_character(.x$name),
    character(1)
  )
  if (
    anyNA(observed_relations) ||
      anyDuplicated(observed_relations) ||
      !setequal(observed_relations, expected_relations)
  ) {
    abort_schema_integrity(
      "Generated relations must correspond exactly to multivalued slots.",
      expected_relations = sort(expected_relations),
      observed_relations = sort(observed_relations),
      rule = "generated_relation_correspondence",
      subclass = subclass
    )
  }
  invisible(manifest)
}

validate_manifest_scalar_slot <- function(
  slot,
  column,
  record_class,
  slot_name,
  subclass
) {
  object_reference <- scalar_logical(slot$object_reference)
  relational_type <- scalar_character(slot$relational_type)
  expected_foreign_key <- if (object_reference) {
    list(class = scalar_character(slot$range), slot = "id")
  } else {
    NULL
  }
  if (object_reference && !identical(relational_type, "VARCHAR")) {
    abort_schema_integrity(
      paste0(
        "Object-reference slot `",
        record_class,
        ".",
        slot_name,
        "` must use relational type `VARCHAR`."
      ),
      record_class = record_class,
      slot = slot_name,
      observed_type = relational_type,
      rule = "object_reference_varchar",
      subclass = subclass
    )
  }
  expected_column <- list(
    name = scalar_character(slot$column),
    slot = slot_name,
    type = relational_type,
    nullable = !scalar_logical(slot$required),
    primary_key = scalar_logical(slot$identifier),
    foreign_key = expected_foreign_key
  )
  if (
    !identical(scalar_character(slot$name), slot_name) ||
      !manifest_contract_identical(slot$foreign_key, expected_foreign_key) ||
      !manifest_contract_identical(column, expected_column)
  ) {
    abort_schema_integrity(
      paste0(
        "Slot `",
        record_class,
        ".",
        slot_name,
        "` and its physical column definition disagree."
      ),
      record_class = record_class,
      slot = slot_name,
      rule = "scalar_column_contract",
      subclass = subclass
    )
  }
  invisible(slot)
}

validate_manifest_relation_contract <- function(
  manifest,
  record_class,
  slot_name,
  subclass = NULL
) {
  contract <- manifest$classes[[record_class]]
  slot <- contract$slots[[slot_name]]
  matches <- Filter(
    \(.x) {
      identical(scalar_character(.x$owner_class), record_class) &&
        identical(scalar_character(.x$slot), slot_name)
    },
    manifest$relations
  )
  if (length(matches) != 1L) {
    abort_schema_integrity(
      "A multivalued slot must have exactly one generated relation.",
      record_class = record_class,
      slot = slot_name,
      relation_count = length(matches),
      rule = "generated_relation_count",
      subclass = subclass
    )
  }
  relation <- matches[[1L]]
  object_reference <- scalar_logical(slot$object_reference)
  relational_type <- scalar_character(slot$relational_type)
  kind <- if (object_reference) "object" else "value"
  expected_foreign_key <- if (object_reference) {
    list(class = scalar_character(slot$range), slot = "id")
  } else {
    NULL
  }
  if (object_reference && !identical(relational_type, "VARCHAR")) {
    abort_schema_integrity(
      paste0(
        "Object-reference slot `",
        record_class,
        ".",
        slot_name,
        "` must use relational type `VARCHAR`."
      ),
      record_class = record_class,
      slot = slot_name,
      observed_type = relational_type,
      rule = "object_reference_varchar",
      subclass = subclass
    )
  }
  predicate <- scalar_character(relation$predicate)
  valid <- identical(scalar_character(slot$name), slot_name) &&
    is.null(slot$column) &&
    scalar_logical(slot$multivalued) &&
    !scalar_logical(slot$identifier) &&
    manifest_contract_identical(slot$foreign_key, expected_foreign_key) &&
    setequal(
      names(relation),
      c(
        "name",
        "table",
        "owner_class",
        "owner_table",
        "slot",
        "kind",
        "ordered",
        "predicate",
        "columns"
      )
    ) &&
    identical(
      scalar_character(relation$name),
      paste(record_class, slot_name, sep = ".")
    ) &&
    identical(
      scalar_character(relation$owner_table),
      scalar_character(contract$table)
    ) &&
    identical(
      scalar_character(relation$table),
      generated_relation_table_name(contract$table, slot_name)
    ) &&
    identical(scalar_character(relation$kind), kind) &&
    identical(
      scalar_logical(relation$ordered),
      scalar_logical(slot$ordered)
    ) &&
    !is.na(predicate) &&
    nzchar(predicate) &&
    manifest_contract_identical(
      relation$columns,
      generated_relation_columns(record_class, slot, kind)
    )
  if (!valid) {
    abort_schema_integrity(
      paste0(
        "Generated relation `",
        record_class,
        ".",
        slot_name,
        "` does not match the compiler contract."
      ),
      record_class = record_class,
      slot = slot_name,
      relation = scalar_character(relation$name),
      rule = "generated_relation_contract",
      subclass = subclass
    )
  }
  invisible(relation)
}

manifest_contract_identical <- function(x, y) {
  identical(
    canonical_json(canonical_schema_change_value(x)),
    canonical_json(canonical_schema_change_value(y))
  )
}

#' List concrete classes in a graft schema
#'
#' @param schema A `kg_schema` object or manifest path.
#'
#' @return A data frame with one row per concrete class.
#' @export
kg_classes <- function(schema) {
  schema <- as_kg_schema(schema)
  classes <- schema$manifest$classes
  if (length(classes) == 0L) {
    return(data.frame(
      class = character(),
      role = character(),
      statement_shape = character(),
      table = character(),
      id_policy = character()
    ))
  }
  data.frame(
    class = names(classes),
    role = vapply(classes, \(.x) scalar_character(.x$role), character(1)),
    statement_shape = vapply(
      classes,
      \(.x) scalar_character(.x$statement_shape),
      character(1)
    ),
    table = vapply(classes, \(.x) scalar_character(.x$table), character(1)),
    id_policy = vapply(
      classes,
      \(.x) scalar_character(.x$id_policy),
      character(1)
    ),
    row.names = NULL,
    check.names = FALSE
  )
}

#' List slots in a graft schema
#'
#' @param schema A `kg_schema` object or manifest path.
#' @param class Optional concrete class name. When supplied, class-induced slot
#'   usage is returned; otherwise global slot definitions are returned.
#'
#' @return A data frame with one row per slot.
#' @export
kg_slots <- function(schema, class = NULL) {
  schema <- as_kg_schema(schema)
  if (is.null(class)) {
    slots <- schema$manifest$slots
    class_value <- NA_character_
  } else {
    if (
      !is.character(class) ||
        length(class) != 1L ||
        is.na(class) ||
        !nzchar(class)
    ) {
      abort_schema_error(
        "`class` must be one concrete class name or `NULL`.",
        argument = "class"
      )
    }
    class_contract <- schema$manifest$classes[[class]]
    if (is.null(class_contract)) {
      abort_schema_error(
        paste0("Unknown concrete class `", class, "`."),
        record_class = class
      )
    }
    slots <- class_contract$slots
    class_value <- class
  }
  slots_data_frame(slots, class_value)
}

slots_data_frame <- function(slots, class) {
  if (length(slots) == 0L) {
    return(data.frame(
      class = character(),
      slot = character(),
      range = character(),
      relational_type = character(),
      required = logical(),
      multivalued = logical(),
      identifier = logical(),
      object_reference = logical(),
      enum = character(),
      column = character()
    ))
  }
  data.frame(
    class = rep(class, length(slots)),
    slot = names(slots),
    range = vapply(slots, \(.x) scalar_character(.x$range), character(1)),
    relational_type = vapply(
      slots,
      \(.x) scalar_character(.x$relational_type),
      character(1)
    ),
    required = vapply(
      slots,
      \(.x) scalar_logical(.x$required),
      logical(1)
    ),
    multivalued = vapply(
      slots,
      \(.x) scalar_logical(.x$multivalued),
      logical(1)
    ),
    identifier = vapply(
      slots,
      \(.x) scalar_logical(.x$identifier),
      logical(1)
    ),
    object_reference = vapply(
      slots,
      \(.x) scalar_logical(.x$object_reference),
      logical(1)
    ),
    enum = vapply(slots, \(.x) scalar_character(.x$enum), character(1)),
    column = vapply(slots, \(.x) scalar_character(.x$column), character(1)),
    row.names = NULL,
    check.names = FALSE
  )
}

#' List enum values in a graft schema
#'
#' @param schema A `kg_schema` object or manifest path.
#'
#' @return A data frame with one row per permissible enum value.
#' @export
kg_enums <- function(schema) {
  schema <- as_kg_schema(schema)
  enums <- schema$manifest$enums
  rows <- lapply(names(enums), function(name) {
    values <- enums[[name]]$permissible_values
    if (length(values) == 0L) {
      return(NULL)
    }
    data.frame(
      enum = rep(name, length(values)),
      value = vapply(
        values,
        \(.x) scalar_character(.x$value),
        character(1)
      ),
      meaning = vapply(
        values,
        \(.x) scalar_character(.x$meaning),
        character(1)
      ),
      description = vapply(
        values,
        \(.x) scalar_character(.x$description),
        character(1)
      ),
      row.names = NULL
    )
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0L) {
    return(data.frame(
      enum = character(),
      value = character(),
      meaning = character(),
      description = character()
    ))
  }
  do.call(rbind, rows)
}

#' Summarize a graft schema
#'
#' @param schema A `kg_schema` object or manifest path.
#'
#' @return A named list of schema metadata and fingerprints.
#' @export
kg_schema_info <- function(schema) {
  schema <- as_kg_schema(schema)
  manifest <- schema$manifest
  list(
    schema_id = scalar_character(manifest$schema$id),
    schema_name = scalar_character(manifest$schema$name),
    schema_version = scalar_character(manifest$schema$version),
    manifest_version = scalar_character(manifest$manifest_version),
    relational_mapping_version = scalar_character(
      manifest$relational_mapping_version
    ),
    structural_digest = scalar_character(
      manifest$fingerprints$structural_digest
    ),
    source_digest = scalar_character(manifest$fingerprints$source_digest),
    build_digest = scalar_character(manifest$fingerprints$build_digest),
    compiler = manifest$compiler,
    class_count = length(manifest$classes),
    relation_count = length(manifest$relations),
    source_files = manifest$schema$source_files,
    path = schema$path
  )
}
