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
