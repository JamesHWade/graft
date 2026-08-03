load_schema_manifest <- function(path) {
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
  new_compiled_schema(manifest, normalized_path)
}

validate_manifest_header <- function(manifest, path) {
  required <- c(
    "manifest_version",
    "projection_mapping_version",
    "schema",
    "classes",
    "slots",
    "enums",
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
  if (!is_compiled_schema(schema)) {
    abort_schema_integrity(
      "Schema integrity validation requires a compiled schema.",
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
  validate_manifest_projection_contracts(manifest, subclass)
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
  observed <- scalar_character(slot$duckdb_type)
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
        "` must use DuckDB type `",
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
        "slot_duckdb_type_contract"
      },
      subclass = subclass
    )
  }
  invisible(slot)
}

validate_manifest_projection_contracts <- function(manifest, subclass) {
  class_names <- names(manifest$classes)
  expected_relations <- character()
  projection_names <- character()
  for (record_class in class_names) {
    contract <- manifest$classes[[record_class]]
    view <- scalar_character(contract$view)
    if (
      !identical(scalar_character(contract$name), record_class) ||
        is.na(view) ||
        !nzchar(view)
    ) {
      abort_schema_integrity(
        paste0(
          "Class `",
          record_class,
          "` has invalid projection metadata."
        ),
        record_class = record_class,
        rule = "class_projection_metadata",
        subclass = subclass
      )
    }
    projection_names <- c(projection_names, view)

    slots <- contract$slots
    for (slot_name in names(slots)) {
      slot <- slots[[slot_name]]
      if (!identical(scalar_character(slot$name), slot_name)) {
        abort_schema_integrity(
          paste0(
            "Slot `",
            record_class,
            ".",
            slot_name,
            "` name must match its manifest key."
          ),
          record_class = record_class,
          slot = slot_name,
          declared_name = scalar_character(slot$name),
          rule = "slot_name_contract",
          subclass = subclass
        )
      }
      validate_compiler_slot_type(
        slot,
        slot_name,
        record_class,
        subclass
      )
    }
    scalar_slots <- Filter(
      \(.x) !scalar_logical(.x$multivalued),
      slots
    )
    view_columns <- vapply(
      scalar_slots,
      \(.x) scalar_character(.x$view_column),
      character(1)
    )
    if (
      anyNA(view_columns) ||
        any(!nzchar(view_columns)) ||
        anyDuplicated(tolower(view_columns))
    ) {
      abort_schema_integrity(
        paste0(
          "Scalar slots for class `",
          record_class,
          "` must use unique projection columns."
        ),
        record_class = record_class,
        rule = "unique_projection_columns",
        subclass = subclass
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
      projection_names <- c(
        projection_names,
        scalar_character(relation$view)
      )
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
  invalid_projection_names <- is.na(projection_names) |
    !nzchar(projection_names) |
    startsWith(tolower(projection_names), "_graft_")
  if (
    any(invalid_projection_names) ||
      anyDuplicated(tolower(projection_names))
  ) {
    abort_schema_integrity(
      "Class and relation projection names must be valid and unique.",
      projection_names = projection_names,
      rule = "unique_projection_names",
      subclass = subclass
    )
  }
  invisible(manifest)
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
  kind <- if (object_reference) "object" else "value"
  predicate <- scalar_character(relation$predicate)
  valid <- identical(scalar_character(slot$name), slot_name) &&
    is.null(slot$view_column) &&
    scalar_logical(slot$multivalued) &&
    !scalar_logical(slot$identifier) &&
    setequal(
      names(relation),
      c(
        "name",
        "view",
        "owner_class",
        "owner_view",
        "slot",
        "kind",
        "ordered",
        "predicate"
      )
    ) &&
    identical(
      scalar_character(relation$name),
      paste(record_class, slot_name, sep = ".")
    ) &&
    identical(
      scalar_character(relation$owner_view),
      scalar_character(contract$view)
    ) &&
    identical(
      scalar_character(relation$view),
      paste0(contract$view, "__", projection_snake_case(slot_name))
    ) &&
    identical(scalar_character(relation$kind), kind) &&
    identical(
      scalar_logical(relation$ordered),
      scalar_logical(slot$ordered)
    ) &&
    !is.na(predicate) &&
    nzchar(predicate)
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

projection_snake_case <- function(value) {
  value <- gsub(
    "([a-z0-9])([A-Z])",
    "\\1_\\2",
    value,
    perl = TRUE
  )
  value <- gsub("[^A-Za-z0-9]+", "_", value)
  tolower(gsub("^_+|_+$", "", value))
}
