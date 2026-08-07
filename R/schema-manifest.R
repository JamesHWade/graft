graft_manifest_version <- "2.0.0"
graft_projection_mapping_version <- "1"
graft_linkml_compiler_name <- "graft-linkml-compiler"
graft_linkml_compiler_version <- "0.3.0"

graft_linkml_compiler_digest <- function() {
  data_dict_file_digest(graft_compiler_path())
}

graft_linkml_source_digest <- function(source_files) {
  keys <- vapply(
    source_files,
    \(source_file) {
      paste0(
        if (is.null(source_file$schema_id)) "" else source_file$schema_id,
        "\r",
        source_file$name
      )
    },
    character(1)
  )
  source_files <- source_files[order(keys, method = "radix")]
  payload <- lapply(
    source_files,
    \(source_file) source_file[c("schema_id", "name", "content_digest")]
  )
  graft_sha256(canonical_json(canonical_schema_value(payload)))
}

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
  snapshot <- schema_manifest_source_snapshot(normalized_path)
  manifest <- tryCatch(
    jsonlite::fromJSON(snapshot$text, simplifyVector = FALSE),
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
  validate_data_dict_json_numbers(
    manifest,
    snapshot$text,
    normalized_path,
    subject = "schema manifest"
  )
  validate_manifest_header(manifest, normalized_path)
  new_compiled_schema(manifest, normalized_path)
}

schema_manifest_source_snapshot <- function(path) {
  connection <- tryCatch(
    file(path, open = "rb"),
    error = function(error) {
      abort_schema_error(
        paste0("Could not read schema manifest `", path, "`."),
        manifest_path = path,
        parent = error
      )
    }
  )
  connection_open <- TRUE
  on.exit(if (connection_open) close(connection), add = TRUE)
  chunks <- list()
  repeat {
    chunk <- tryCatch(
      readBin(connection, what = "raw", n = 65536L),
      error = function(error) {
        abort_schema_error(
          paste0("Could not read schema manifest `", path, "`."),
          manifest_path = path,
          parent = error
        )
      }
    )
    if (length(chunk) == 0L) {
      break
    }
    chunks[[length(chunks) + 1L]] <- chunk
  }
  close(connection)
  connection_open <- FALSE
  bytes <- if (length(chunks) == 0L) raw() else do.call(c, chunks)
  text <- tryCatch(
    rawToChar(bytes),
    error = function(error) {
      abort_schema_error(
        paste0("Schema manifest `", path, "` is not valid text."),
        manifest_path = path,
        parent = error
      )
    }
  )
  list(bytes = bytes, text = text)
}

duplicate_json_object_key <- function(value, path = "$") {
  if (!is.list(value) || is.null(value)) {
    return(NULL)
  }
  value_names <- names(value)
  if (!is.null(value_names)) {
    duplicate <- which(duplicated(value_names))
    if (length(duplicate) > 0L) {
      index <- duplicate[[1L]]
      return(list(
        key = value_names[[index]],
        path = paste0(path, ".", value_names[[index]])
      ))
    }
  }
  for (index in seq_along(value)) {
    child_path <- if (is.null(value_names)) {
      paste0(path, "[", index, "]")
    } else {
      paste0(path, ".", value_names[[index]])
    }
    duplicate <- duplicate_json_object_key(value[[index]], child_path)
    if (!is.null(duplicate)) {
      return(duplicate)
    }
  }
  NULL
}

manifest_json_object <- function(value) {
  is.list(value) && !is.object(value) && !is.null(names(value))
}

manifest_json_array <- function(value) {
  is.list(value) && !is.object(value) && is.null(names(value))
}

manifest_json_string <- function(value, nonempty = FALSE) {
  is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    (!nonempty || nzchar(trimws(value)))
}

manifest_json_nullable_string <- function(value) {
  is.null(value) || manifest_json_string(value)
}

manifest_json_nonblank_string <- function(value) {
  manifest_json_string(value, nonempty = TRUE)
}

manifest_json_nullable_nonblank_string <- function(value) {
  is.null(value) || manifest_json_nonblank_string(value)
}

manifest_json_linkml_reference <- function(value, range = "uriorcurie") {
  manifest_json_nonblank_string(value) &&
    linkml_reference_is_valid(value, range)
}

manifest_json_nullable_linkml_reference <- function(
  value,
  range = "uriorcurie"
) {
  is.null(value) || manifest_json_linkml_reference(value, range)
}

manifest_json_boolean <- function(value) {
  is.logical(value) && length(value) == 1L && !is.na(value)
}

manifest_json_nullable_number <- function(value) {
  is.null(value) ||
    (is.numeric(value) &&
      length(value) == 1L &&
      !is.na(value) &&
      is.finite(value))
}

manifest_json_nonblank_string_array <- function(value) {
  manifest_json_array(value) &&
    all(vapply(value, manifest_json_nonblank_string, logical(1)))
}

manifest_regex_is_valid <- function(pattern) {
  if (is.null(pattern)) {
    return(TRUE)
  }
  tryCatch(
    {
      grepl(pattern, "")
      TRUE
    },
    warning = \(warning) FALSE,
    error = \(error) FALSE
  )
}

manifest_contract_problem <- function(
  message,
  field,
  rule = "manifest_shape_contract"
) {
  list(message = message, field = field, rule = rule)
}

manifest_object_fields_problem <- function(
  value,
  field,
  required,
  allowed = required
) {
  if (!manifest_json_object(value)) {
    return(manifest_contract_problem(
      paste0("Manifest field `", field, "` must be a JSON object."),
      field
    ))
  }
  missing <- setdiff(required, names(value))
  unexpected <- setdiff(names(value), allowed)
  if (length(missing) > 0L || length(unexpected) > 0L) {
    return(manifest_contract_problem(
      paste0("Manifest field `", field, "` has invalid object fields."),
      field
    ))
  }
  NULL
}

manifest_slot_shape_problem <- function(slot, field) {
  required <- c(
    "name",
    "range",
    "duckdb_type",
    "required",
    "multivalued",
    "identifier",
    "object_reference"
  )
  allowed <- c(
    required,
    "view_column",
    "ordered",
    "enum",
    "meaning",
    "pattern",
    "datetime_format",
    "minimum_value",
    "maximum_value",
    "external_identifier",
    "search_weight",
    "sensitive"
  )
  problem <- manifest_object_fields_problem(slot, field, required, allowed)
  if (!is.null(problem)) {
    return(problem)
  }
  string_fields <- c("name", "range", "duckdb_type")
  if (
    !all(
      vapply(
        slot[string_fields],
        manifest_json_nonblank_string,
        logical(1)
      )
    )
  ) {
    return(manifest_contract_problem(
      "Manifest slot identity and type fields must be nonblank strings.",
      field
    ))
  }
  if (
    "meaning" %in%
      names(slot) &&
      !manifest_json_nullable_linkml_reference(slot$meaning)
  ) {
    return(manifest_contract_problem(
      "Manifest slot meaning must be a valid URI or CURIE.",
      paste0(field, ".meaning"),
      "manifest_reference_contract"
    ))
  }
  boolean_fields <- intersect(
    c(
      "required",
      "multivalued",
      "ordered",
      "identifier",
      "object_reference",
      "sensitive"
    ),
    names(slot)
  )
  if (!all(vapply(slot[boolean_fields], manifest_json_boolean, logical(1)))) {
    return(manifest_contract_problem(
      "Manifest slot flags must be JSON booleans.",
      field
    ))
  }
  nullable_strings <- intersect(
    c(
      "view_column",
      "enum",
      "meaning",
      "pattern",
      "external_identifier"
    ),
    names(slot)
  )
  if (
    !all(
      vapply(
        slot[nullable_strings],
        manifest_json_nullable_string,
        logical(1)
      )
    )
  ) {
    return(manifest_contract_problem(
      "Manifest slot metadata must use strings or null.",
      field
    ))
  }
  nonblank_nullable <- intersect(
    c("view_column", "enum", "meaning", "external_identifier"),
    names(slot)
  )
  if (
    !all(
      vapply(
        slot[nonblank_nullable],
        manifest_json_nullable_nonblank_string,
        logical(1)
      )
    )
  ) {
    return(manifest_contract_problem(
      "Manifest slot semantic identifiers must be nonblank strings or null.",
      field
    ))
  }
  if (
    "datetime_format" %in%
      names(slot) &&
      (!manifest_json_nullable_string(slot$datetime_format) ||
        (!is.null(slot$datetime_format) &&
          !slot$datetime_format %in% c("offset", "local_utc")))
  ) {
    return(manifest_contract_problem(
      "Manifest slot datetime format is invalid.",
      paste0(field, ".datetime_format")
    ))
  }
  if (
    "search_weight" %in%
      names(slot) &&
      !manifest_json_nullable_number(slot$search_weight)
  ) {
    return(manifest_contract_problem(
      "Manifest slot search weight must be a number or null.",
      paste0(field, ".search_weight")
    ))
  }
  for (bound in intersect(
    c("minimum_value", "maximum_value"),
    names(slot)
  )) {
    if (!manifest_json_nullable_number(slot[[bound]])) {
      return(manifest_contract_problem(
        "Manifest slot bounds must be finite numbers or null.",
        paste(field, bound, sep = ".")
      ))
    }
  }
  if ("pattern" %in% names(slot) && !manifest_regex_is_valid(slot$pattern)) {
    return(manifest_contract_problem(
      "Manifest slot pattern is not a valid R regular expression.",
      paste0(field, ".pattern"),
      "slot_pattern_contract"
    ))
  }
  NULL
}

manifest_class_shape_problem <- function(class, field) {
  required <- c(
    "name",
    "role",
    "view",
    "id_policy",
    "id_format",
    "type_uri",
    "slots",
    "relations"
  )
  allowed <- c(
    required,
    "is_a",
    "ancestors",
    "statement_shape",
    "label_slot",
    "search_slots",
    "origin_key_slots",
    "qualifier_slots",
    "fixed_predicate"
  )
  problem <- manifest_object_fields_problem(class, field, required, allowed)
  if (!is.null(problem)) {
    return(problem)
  }
  string_fields <- c("name", "view")
  if (
    !all(
      vapply(
        class[string_fields],
        manifest_json_nonblank_string,
        logical(1)
      )
    )
  ) {
    return(manifest_contract_problem(
      "Manifest class name and view must be nonblank strings.",
      field
    ))
  }
  if (
    !manifest_json_string(class$role) ||
      !class$role %in%
        c(
          "node",
          "edge",
          "statement",
          "evidence",
          "source",
          "mention",
          "metadata"
        ) ||
      !manifest_json_string(class$id_policy) ||
      !class$id_policy %in%
        c(
          "require",
          "mint",
          "resolve_exact",
          "deterministic"
        ) ||
      !manifest_json_string(class$id_format) ||
      !class$id_format %in% c("graft", "linkml")
  ) {
    return(manifest_contract_problem(
      "Manifest class role or identity policy is invalid.",
      field
    ))
  }
  nullable_strings <- intersect(
    c("is_a", "label_slot", "fixed_predicate"),
    names(class)
  )
  if (
    !all(
      vapply(
        class[nullable_strings],
        manifest_json_nullable_nonblank_string,
        logical(1)
      )
    )
  ) {
    return(manifest_contract_problem(
      "Manifest class metadata must use strings or null.",
      field
    ))
  }
  if (!manifest_json_linkml_reference(class$type_uri, "uri")) {
    return(manifest_contract_problem(
      "Manifest class type URI must be a valid complete URI.",
      paste0(field, ".type_uri"),
      "manifest_reference_contract"
    ))
  }
  if (!manifest_json_nullable_linkml_reference(class$fixed_predicate)) {
    return(manifest_contract_problem(
      "Manifest fixed predicate must be a valid URI or CURIE.",
      paste0(field, ".fixed_predicate"),
      "manifest_reference_contract"
    ))
  }
  if (
    "statement_shape" %in%
      names(class) &&
      (!manifest_json_nullable_string(class$statement_shape) ||
        (!is.null(class$statement_shape) &&
          !class$statement_shape %in% c("narrative", "semantic")))
  ) {
    return(manifest_contract_problem(
      "Manifest class statement shape is invalid.",
      paste0(field, ".statement_shape")
    ))
  }
  array_fields <- intersect(
    c(
      "ancestors",
      "search_slots",
      "origin_key_slots",
      "qualifier_slots",
      "relations"
    ),
    names(class)
  )
  if (
    !all(
      vapply(
        class[array_fields],
        manifest_json_nonblank_string_array,
        logical(1)
      )
    )
  ) {
    return(manifest_contract_problem(
      "Manifest class string collections must be JSON arrays.",
      field
    ))
  }
  if (!manifest_json_object(class$slots)) {
    return(manifest_contract_problem(
      "Manifest class slots must be a JSON object.",
      paste0(field, ".slots")
    ))
  }
  if (
    length(class$slots) > 0L &&
      !all(
        vapply(names(class$slots), manifest_json_nonblank_string, logical(1))
      )
  ) {
    return(manifest_contract_problem(
      "Manifest class slot keys must be nonblank strings.",
      paste0(field, ".slots")
    ))
  }
  for (slot_name in names(class$slots)) {
    problem <- manifest_slot_shape_problem(
      class$slots[[slot_name]],
      paste(field, "slots", slot_name, sep = ".")
    )
    if (!is.null(problem)) {
      return(problem)
    }
  }
  NULL
}

manifest_enum_shape_problem <- function(enum, field) {
  problem <- manifest_object_fields_problem(
    enum,
    field,
    c("name", "permissible_values"),
    c("name", "description", "permissible_values")
  )
  if (!is.null(problem)) {
    return(problem)
  }
  if (
    !manifest_json_nonblank_string(enum$name) ||
      ("description" %in%
        names(enum) &&
        !manifest_json_nullable_string(enum$description)) ||
      !manifest_json_array(enum$permissible_values)
  ) {
    return(manifest_contract_problem(
      "Manifest enum metadata is invalid.",
      field
    ))
  }
  for (index in seq_along(enum$permissible_values)) {
    value <- enum$permissible_values[[index]]
    value_field <- paste0(field, ".permissible_values[", index, "]")
    problem <- manifest_object_fields_problem(
      value,
      value_field,
      "value",
      c("value", "meaning", "description")
    )
    if (!is.null(problem)) {
      return(problem)
    }
    if (
      !manifest_json_nonblank_string(value$value) ||
        ("meaning" %in%
          names(value) &&
          !manifest_json_nullable_linkml_reference(value$meaning)) ||
        ("description" %in%
          names(value) &&
          !manifest_json_nullable_string(value$description))
    ) {
      return(manifest_contract_problem(
        "Manifest permissible-value metadata is invalid.",
        value_field
      ))
    }
  }
  NULL
}

manifest_relation_shape_problem <- function(relation, field) {
  required <- c(
    "name",
    "view",
    "owner_class",
    "owner_view",
    "slot",
    "kind",
    "ordered",
    "predicate"
  )
  problem <- manifest_object_fields_problem(relation, field, required)
  if (!is.null(problem)) {
    return(problem)
  }
  string_fields <- required[!required %in% c("kind", "ordered")]
  if (
    !all(
      vapply(
        relation[string_fields],
        manifest_json_nonblank_string,
        logical(1)
      )
    ) ||
      !manifest_json_string(relation$kind) ||
      !relation$kind %in% c("object", "value") ||
      !manifest_json_boolean(relation$ordered)
  ) {
    return(manifest_contract_problem(
      "Manifest relation metadata is invalid.",
      field
    ))
  }
  if (!manifest_json_linkml_reference(relation$predicate)) {
    return(manifest_contract_problem(
      "Manifest relation predicate must be a valid URI or CURIE.",
      paste0(field, ".predicate"),
      "manifest_reference_contract"
    ))
  }
  NULL
}

manifest_expected_graph_projections <- function(classes, relations) {
  class_names <- names(classes)
  class_roles <- vapply(
    classes,
    \(class) class$role,
    character(1)
  )
  statement_shapes <- vapply(
    classes,
    \(class) {
      if (is.null(class$statement_shape)) "" else class$statement_shape
    },
    character(1)
  )
  object_relations <- vapply(
    Filter(
      \(relation) {
        identical(relation$kind, "object") &&
          !identical(
            classes[[relation$owner_class]]$statement_shape,
            "narrative"
          )
      },
      relations
    ),
    \(relation) relation$name,
    character(1)
  )
  list(
    node_classes = as.list(sort(
      class_names[
        class_roles %in%
          c(
            "node",
            "statement",
            "evidence",
            "source"
          )
      ],
      method = "radix"
    )),
    semantic_edges = list(
      direct_edge_classes = as.list(sort(
        class_names[class_roles == "edge"],
        method = "radix"
      )),
      semantic_statement_classes = as.list(sort(
        class_names[statement_shapes == "semantic"],
        method = "radix"
      )),
      object_relations = as.list(sort(
        object_relations,
        method = "radix"
      )),
      exclude_narrative_statements = TRUE
    ),
    provenance_edges = list(
      narrative_statement_classes = as.list(sort(
        class_names[statement_shapes == "narrative"],
        method = "radix"
      )),
      narrative_slots = as.list(c("about", "primary_subject")),
      statement_to_evidence = TRUE,
      evidence_to_source = TRUE,
      supersession = TRUE,
      mention_resolution = TRUE,
      semantic_derivation = TRUE
    )
  )
}

manifest_expected_normalization_versions <- function(classes) {
  slots <- unlist(
    lapply(classes, \(class) unname(class$slots)),
    recursive = FALSE,
    use.names = FALSE
  )
  namespaces <- vapply(
    slots,
    \(slot) {
      if (is.null(slot$external_identifier)) {
        ""
      } else {
        slot$external_identifier
      }
    },
    character(1)
  )
  namespaces <- sort(unique(namespaces[nzchar(namespaces)]), method = "radix")
  stats::setNames(as.list(rep("1", length(namespaces))), namespaces)
}

manifest_expected_linkml_invariants <- function(classes) {
  invariants <- list(
    list(
      name = "confidence_bounds",
      applies_to_role = "statement",
      fields = as.list("confidence"),
      rule = "null_or_between_inclusive",
      minimum = 0L,
      maximum = 1L
    ),
    list(
      name = "valid_time_order",
      applies_to_role = "statement",
      fields = as.list(c("valid_from", "valid_to")),
      rule = "null_or_less_than_or_equal"
    )
  )
  for (class_name in sort(names(classes), method = "radix")) {
    shape <- classes[[class_name]]$statement_shape
    if (identical(shape, "narrative")) {
      invariants[[length(invariants) + 1L]] <- list(
        name = "narrative_shape",
        class = class_name,
        required_fields = as.list("statement_text"),
        forbidden_fields = as.list(c(
          "predicate",
          "object_entity",
          "object_value",
          "object_datatype"
        )),
        rule = "required_and_forbidden_fields"
      )
    } else if (identical(shape, "semantic")) {
      invariants[[length(invariants) + 1L]] <- list(
        name = "exactly_one_semantic_object",
        class = class_name,
        fields = as.list(c("object_entity", "object_value")),
        cardinality = 1L,
        rule = "exactly_one_present"
      )
      invariants[[length(invariants) + 1L]] <- list(
        name = "semantic_literal_datatype",
        class = class_name,
        fields = as.list(c("object_value", "object_datatype")),
        rule = "datatype_when_not_inferable"
      )
    }
  }
  invariants
}

manifest_slot_semantic_problem <- function(
  slot,
  field,
  known_class_ranges,
  enum_names
) {
  range <- slot$range
  object_reference <- slot$object_reference
  external_identifier <- slot$external_identifier
  primitive_ranges <- names(manifest_primitive_duckdb_types())
  if (!is_nonempty_string(range) || !nzchar(trimws(range))) {
    return(manifest_contract_problem(
      "A slot range must be one non-empty string.",
      paste0(field, ".range"),
      "slot_range_contract"
    ))
  }
  if (
    !is.null(external_identifier) &&
      (!is_nonempty_string(external_identifier) ||
        !nzchar(trimws(external_identifier)) ||
        slot$multivalued ||
        object_reference ||
        !identical(slot$duckdb_type, "VARCHAR") ||
        slot$sensitive)
  ) {
    return(manifest_contract_problem(
      paste(
        "External identifiers must use a public scalar non-object text slot."
      ),
      paste0(field, ".external_identifier"),
      "external_identifier_contract"
    ))
  }
  if (object_reference && !range %in% known_class_ranges) {
    return(manifest_contract_problem(
      "Object-reference slot range does not resolve to a declared class.",
      paste0(field, ".range"),
      "slot_range_contract"
    ))
  }
  if (!object_reference && range %in% known_class_ranges) {
    return(manifest_contract_problem(
      "A class-valued slot must be marked as an object reference.",
      paste0(field, ".object_reference"),
      "slot_range_contract"
    ))
  }
  enum <- slot$enum
  if (
    (!is.null(enum) &&
      (!enum %in% enum_names ||
        !identical(range, enum) ||
        object_reference)) ||
      (is.null(enum) && range %in% enum_names)
  ) {
    return(manifest_contract_problem(
      "Slot enum metadata does not resolve to its declared range.",
      paste0(field, ".enum"),
      "slot_enum_contract"
    ))
  }
  if (
    !object_reference &&
      is.null(enum) &&
      !range %in% primitive_ranges
  ) {
    return(manifest_contract_problem(
      "A scalar slot range must be a supported primitive or declared enum.",
      paste0(field, ".range"),
      "slot_range_contract"
    ))
  }
  minimum <- slot$minimum_value
  maximum <- slot$maximum_value
  if (
    (!is.null(minimum) || !is.null(maximum)) &&
      !slot$duckdb_type %in% c("BIGINT", "DECIMAL", "DOUBLE")
  ) {
    return(manifest_contract_problem(
      "Only numeric slots may declare minimum or maximum values.",
      field,
      "slot_bound_contract"
    ))
  }
  bounds <- Filter(Negate(is.null), list(minimum, maximum))
  if (identical(slot$duckdb_type, "DECIMAL") && length(bounds) > 0L) {
    return(manifest_contract_problem(
      paste(
        "Exact DECIMAL bounds are not supported until the manifest can",
        "represent them without binary floating-point loss."
      ),
      field,
      "slot_bound_contract"
    ))
  }
  if (
    identical(slot$duckdb_type, "BIGINT") &&
      any(vapply(
        bounds,
        \(bound) bound != trunc(bound) || abs(bound) > 9007199254740991,
        logical(1)
      ))
  ) {
    return(manifest_contract_problem(
      "BIGINT bounds must be exact integers within the safe JSON range.",
      field,
      "slot_bound_contract"
    ))
  }
  if (
    !is.null(minimum) &&
      !is.null(maximum) &&
      minimum > maximum
  ) {
    return(manifest_contract_problem(
      "A slot minimum value cannot exceed its maximum value.",
      field,
      "slot_bound_contract"
    ))
  }
  NULL
}

manifest_primitive_duckdb_types <- function() {
  c(
    boolean = "BOOLEAN",
    date = "DATE",
    datetime = "TIMESTAMP",
    decimal = "DECIMAL",
    double = "DOUBLE",
    float = "DOUBLE",
    integer = "BIGINT",
    time = "TIME",
    string = "VARCHAR",
    uriorcurie = "VARCHAR",
    uri = "VARCHAR"
  )
}

manifest_core_class_parents <- function() {
  c(
    GraftRecord = "",
    GraftNode = "GraftRecord",
    GraftEdge = "GraftRecord",
    GraftStatement = "GraftRecord",
    GraftNarrativeStatement = "GraftStatement",
    GraftSemanticStatement = "GraftStatement",
    GraftEvidence = "GraftRecord",
    GraftSource = "GraftRecord",
    GraftMention = "GraftRecord",
    GraftMetadata = "GraftRecord"
  )
}

manifest_core_slot_contracts <- function() {
  contract <- function(
    range,
    duckdb_type = "VARCHAR",
    required = FALSE,
    multivalued = FALSE,
    ordered = FALSE,
    identifier = FALSE,
    object_reference = FALSE,
    enum = NULL,
    minimum_value = NULL,
    maximum_value = NULL
  ) {
    list(
      range = range,
      duckdb_type = duckdb_type,
      required = required,
      multivalued = multivalued,
      ordered = ordered,
      identifier = identifier,
      object_reference = object_reference,
      enum = enum,
      minimum_value = minimum_value,
      maximum_value = maximum_value
    )
  }
  list(
    id = contract("uriorcurie", required = TRUE, identifier = TRUE),
    created_at = contract("datetime", "TIMESTAMP"),
    updated_at = contract("datetime", "TIMESTAMP"),
    label = contract("string"),
    subject = contract(
      "GraftNode",
      required = TRUE,
      object_reference = TRUE
    ),
    object = contract(
      "GraftNode",
      required = TRUE,
      object_reference = TRUE
    ),
    predicate = contract("uriorcurie", required = TRUE),
    polarity = contract("StatementPolarity", enum = "StatementPolarity"),
    confidence = contract(
      "float",
      "DOUBLE",
      minimum_value = 0L,
      maximum_value = 1L
    ),
    status = contract("StatementStatus", enum = "StatementStatus"),
    valid_from = contract("datetime", "TIMESTAMP"),
    valid_to = contract("datetime", "TIMESTAMP"),
    asserted_at = contract("datetime", "TIMESTAMP"),
    superseded_by = contract(
      "GraftStatement",
      object_reference = TRUE
    ),
    statement_text = contract("string", required = TRUE),
    primary_subject = contract("GraftNode", object_reference = TRUE),
    about = contract(
      "GraftNode",
      multivalued = TRUE,
      object_reference = TRUE
    ),
    object_entity = contract("GraftNode", object_reference = TRUE),
    object_value = contract("string"),
    object_datatype = contract("uriorcurie"),
    derived_from_statement = contract(
      "GraftNarrativeStatement",
      object_reference = TRUE
    ),
    statement_id = contract(
      "GraftStatement",
      required = TRUE,
      object_reference = TRUE
    ),
    source_id = contract(
      "GraftSource",
      required = TRUE,
      object_reference = TRUE
    ),
    support_type = contract(
      "EvidenceSupportType",
      required = TRUE,
      enum = "EvidenceSupportType"
    ),
    locator_type = contract("LocatorType", enum = "LocatorType"),
    locator_value = contract("string"),
    page_start = contract("integer", "BIGINT", minimum_value = 1L),
    page_end = contract("integer", "BIGINT", minimum_value = 1L),
    excerpt = contract("string"),
    source_content_hash = contract("string"),
    extraction_method = contract("string"),
    extraction_version = contract("string"),
    surface_form = contract("string", required = TRUE),
    entity_id = contract("GraftNode", object_reference = TRUE)
  )
}

manifest_core_slots_by_class <- function() {
  list(
    GraftRecord = c("id", "created_at", "updated_at"),
    GraftNode = "label",
    GraftEdge = c("subject", "predicate", "object"),
    GraftStatement = c(
      "polarity",
      "confidence",
      "status",
      "valid_from",
      "valid_to",
      "asserted_at",
      "superseded_by"
    ),
    GraftNarrativeStatement = c(
      "statement_text",
      "primary_subject",
      "about"
    ),
    GraftSemanticStatement = c(
      "subject",
      "predicate",
      "object_entity",
      "object_value",
      "object_datatype",
      "derived_from_statement"
    ),
    GraftEvidence = c(
      "statement_id",
      "source_id",
      "support_type",
      "locator_type",
      "locator_value",
      "page_start",
      "page_end",
      "excerpt",
      "source_content_hash",
      "extraction_method",
      "extraction_version"
    ),
    GraftSource = character(),
    GraftMention = c(
      "source_id",
      "surface_form",
      "locator_type",
      "locator_value",
      "entity_id"
    ),
    GraftMetadata = character()
  )
}

manifest_core_class_slot_problem <- function(class, class_name) {
  ancestors <- unlist(class$ancestors, use.names = FALSE)
  core_slots <- manifest_core_slots_by_class()
  inherited <- intersect(ancestors, names(core_slots))
  if (!"GraftRecord" %in% inherited) {
    return(NULL)
  }
  slot_names <- unique(unlist(core_slots[inherited], use.names = FALSE))
  missing <- setdiff(slot_names, names(class$slots))
  if (length(missing) > 0L) {
    return(manifest_contract_problem(
      "A Graft core-derived class is missing inherited core slots.",
      paste0("classes.", class_name, ".slots"),
      "core_slot_contract"
    ))
  }

  contracts <- manifest_core_slot_contracts()
  exact_fields <- c(
    "range",
    "duckdb_type",
    "multivalued",
    "ordered",
    "identifier",
    "object_reference",
    "enum"
  )
  for (slot_name in slot_names) {
    observed <- class$slots[[slot_name]]
    expected <- contracts[[slot_name]]
    exact <- all(vapply(
      exact_fields,
      \(field) identical(observed[[field]], expected[[field]]),
      logical(1)
    ))
    required_is_safe <- !expected$required || observed$required
    minimum_is_safe <- is.null(expected$minimum_value) ||
      (!is.null(observed$minimum_value) &&
        observed$minimum_value >= expected$minimum_value)
    maximum_is_safe <- is.null(expected$maximum_value) ||
      (!is.null(observed$maximum_value) &&
        observed$maximum_value <= expected$maximum_value)
    if (
      !exact ||
        !required_is_safe ||
        !minimum_is_safe ||
        !maximum_is_safe ||
        !is.null(observed$datetime_format) ||
        (identical(slot_name, "id") &&
          (observed$sensitive || !is.null(observed$external_identifier)))
    ) {
      return(manifest_contract_problem(
        "A class-local slot weakens or changes its Graft core contract.",
        paste("classes", class_name, "slots", slot_name, sep = "."),
        "core_slot_contract"
      ))
    }
  }
  NULL
}

manifest_core_global_slot_problem <- function(slots) {
  contracts <- manifest_core_slot_contracts()
  missing <- setdiff(names(contracts), names(slots))
  if (length(missing) > 0L) {
    return(manifest_contract_problem(
      "A LinkML manifest using the Graft core is missing core global slots.",
      "slots",
      "core_slot_contract"
    ))
  }
  fields <- setdiff(names(contracts[[1L]]), "ordered")
  for (slot_name in names(contracts)) {
    observed <- slots[[slot_name]]
    expected <- contracts[[slot_name]]
    matches <- all(vapply(
      fields,
      \(field) identical(observed[[field]], expected[[field]]),
      logical(1)
    ))
    if (!matches || !is.null(observed$datetime_format)) {
      return(manifest_contract_problem(
        "A Graft core global slot differs from the packaged core contract.",
        paste("slots", slot_name, sep = "."),
        "core_slot_contract"
      ))
    }
  }
  NULL
}

manifest_class_hierarchy_problem <- function(classes, data_dict) {
  core_parent <- manifest_core_class_parents()
  observed_parent <- character()
  for (class_name in names(classes)) {
    class <- classes[[class_name]]
    ancestors <- unlist(class$ancestors, use.names = FALSE)
    if (data_dict) {
      if (!is.null(class$is_a) || length(ancestors) > 0L) {
        return(manifest_contract_problem(
          "Data-dict classes cannot declare an inheritance hierarchy.",
          paste0("classes.", class_name, ".ancestors"),
          "class_hierarchy_contract"
        ))
      }
      next
    }
    if (
      length(ancestors) == 0L ||
        !identical(ancestors[[1L]], class_name) ||
        anyDuplicated(ancestors)
    ) {
      return(manifest_contract_problem(
        "A LinkML class must declare a unique self-first ancestor path.",
        paste0("classes.", class_name, ".ancestors"),
        "class_hierarchy_contract"
      ))
    }
    direct_parent <- if (length(ancestors) > 1L) {
      ancestors[[2L]]
    } else {
      NULL
    }
    if (!identical(class$is_a, direct_parent)) {
      return(manifest_contract_problem(
        "A class parent does not match its ancestor path.",
        paste0("classes.", class_name, ".is_a"),
        "class_hierarchy_contract"
      ))
    }
    if (length(ancestors) > 2L) {
      unknown_seen <- FALSE
      for (ancestor in ancestors[-1L]) {
        if (ancestor %in% names(classes) && unknown_seen) {
          return(manifest_contract_problem(
            paste(
              "An undeclared ancestor cannot bridge to a declared class in",
              "an ancestor path."
            ),
            paste0("classes.", class_name, ".ancestors"),
            "class_hierarchy_contract"
          ))
        }
        if (!ancestor %in% c(names(classes), names(core_parent))) {
          unknown_seen <- TRUE
        }
      }
    }
    if (length(ancestors) > 1L) {
      for (index in seq_len(length(ancestors) - 1L)) {
        child <- ancestors[[index]]
        parent <- ancestors[[index + 1L]]
        if (
          child %in% names(classes) && !identical(classes[[child]]$is_a, parent)
        ) {
          return(manifest_contract_problem(
            "A declared class has inconsistent ancestor paths.",
            paste0("classes.", class_name, ".ancestors"),
            "class_hierarchy_contract"
          ))
        }
        if (
          child %in%
            names(core_parent) &&
            !identical(unname(core_parent[[child]]), parent)
        ) {
          return(manifest_contract_problem(
            "A Graft core class has an invalid parent in an ancestor path.",
            paste0("classes.", class_name, ".ancestors"),
            "class_hierarchy_contract"
          ))
        }
        if (
          child %in%
            names(observed_parent) &&
            !identical(unname(observed_parent[[child]]), parent)
        ) {
          return(manifest_contract_problem(
            "Ancestor paths disagree about a class parent.",
            paste0("classes.", class_name, ".ancestors"),
            "class_hierarchy_contract"
          ))
        }
        observed_parent[[child]] <- parent
      }
    }
    terminal <- ancestors[[length(ancestors)]]
    terminal_parent <- if (terminal %in% names(classes)) {
      classes[[terminal]]$is_a
    } else if (terminal %in% names(core_parent)) {
      unname(core_parent[[terminal]])
    } else {
      NULL
    }
    if (!is.null(terminal_parent) && nzchar(terminal_parent)) {
      return(manifest_contract_problem(
        "A class ancestor path ends before its declared root.",
        paste0("classes.", class_name, ".ancestors"),
        "class_hierarchy_contract"
      ))
    }
  }
  NULL
}

manifest_class_role_problem <- function(class, class_name, data_dict) {
  ancestors <- unlist(class$ancestors, use.names = FALSE)
  uses_graft_core <- "GraftRecord" %in% ancestors
  core_roles <- c(
    GraftNarrativeStatement = "statement",
    GraftSemanticStatement = "statement",
    GraftStatement = "statement",
    GraftEdge = "edge",
    GraftEvidence = "evidence",
    GraftSource = "source",
    GraftMention = "mention",
    GraftNode = "node",
    GraftMetadata = "metadata",
    GraftRecord = "metadata"
  )
  role_ancestors <- ancestors[ancestors %in% names(core_roles)]
  expected_role <- if (data_dict) {
    "node"
  } else if (length(role_ancestors) > 0L) {
    unname(core_roles[[role_ancestors[[1L]]]])
  } else {
    class$role
  }
  expected_shape <- if ("GraftNarrativeStatement" %in% ancestors) {
    "narrative"
  } else if ("GraftSemanticStatement" %in% ancestors) {
    "semantic"
  } else {
    NULL
  }
  if (
    !identical(class$role, expected_role) ||
      !identical(class$statement_shape, expected_shape)
  ) {
    return(manifest_contract_problem(
      "A class role or statement shape does not match its inheritance.",
      paste0("classes.", class_name),
      "class_role_contract"
    ))
  }
  if (
    !data_dict &&
      !uses_graft_core &&
      class$role %in% c("edge", "statement", "evidence", "mention")
  ) {
    return(manifest_contract_problem(
      paste(
        "Edge, statement, evidence, and mention roles require Graft core",
        "inheritance."
      ),
      paste0("classes.", class_name, ".role"),
      "class_role_contract"
    ))
  }
  if (!is.null(class$fixed_predicate) && !identical(expected_role, "edge")) {
    return(manifest_contract_problem(
      "Only edge classes may declare a fixed predicate.",
      paste0("classes.", class_name, ".fixed_predicate"),
      "class_role_contract"
    ))
  }
  required_slots <- switch(
    expected_role,
    edge = c("subject", "predicate", "object"),
    statement = c(
      "polarity",
      "confidence",
      "status",
      "valid_from",
      "valid_to",
      "asserted_at",
      "superseded_by"
    ),
    evidence = c(
      "statement_id",
      "source_id",
      "support_type",
      "locator_type",
      "locator_value",
      "page_start",
      "page_end",
      "excerpt",
      "source_content_hash",
      "extraction_method",
      "extraction_version"
    ),
    mention = c(
      "source_id",
      "surface_form",
      "locator_type",
      "locator_value",
      "entity_id"
    ),
    character()
  )
  if (identical(expected_shape, "narrative")) {
    required_slots <- c(
      required_slots,
      "statement_text",
      "primary_subject",
      "about"
    )
  } else if (identical(expected_shape, "semantic")) {
    required_slots <- c(
      required_slots,
      "subject",
      "predicate",
      "object_entity",
      "object_value",
      "object_datatype",
      "derived_from_statement"
    )
  }
  if (length(setdiff(required_slots, names(class$slots))) > 0L) {
    return(manifest_contract_problem(
      "A class is missing slots required by its role or statement shape.",
      paste0("classes.", class_name, ".slots"),
      "class_role_contract"
    ))
  }
  if (!data_dict) {
    core_problem <- manifest_core_class_slot_problem(class, class_name)
    if (!is.null(core_problem)) {
      return(core_problem)
    }
  }
  NULL
}

manifest_class_annotation_problem <- function(class, class_name) {
  slots <- class$slots
  label_slot <- class$label_slot
  if (!is.null(label_slot)) {
    label <- slots[[label_slot]]
    if (
      is.null(label) ||
        label$multivalued ||
        label$object_reference ||
        !identical(label$duckdb_type, "VARCHAR") ||
        label$sensitive
    ) {
      return(manifest_contract_problem(
        "A label slot must resolve to a public scalar text slot.",
        paste0("classes.", class_name, ".label_slot"),
        "class_annotation_contract"
      ))
    }
  }

  annotations <- list(
    search_slots = unlist(class$search_slots, use.names = FALSE),
    origin_key_slots = unlist(class$origin_key_slots, use.names = FALSE),
    qualifier_slots = unlist(class$qualifier_slots, use.names = FALSE)
  )
  for (field in names(annotations)) {
    values <- annotations[[field]]
    if (anyDuplicated(values) || length(setdiff(values, names(slots))) > 0L) {
      return(manifest_contract_problem(
        "Class slot annotations must name unique slots on that class.",
        paste("classes", class_name, field, sep = "."),
        "class_annotation_contract"
      ))
    }
  }
  if (
    identical(class$id_policy, "deterministic") &&
      length(annotations$origin_key_slots) == 0L
  ) {
    return(manifest_contract_problem(
      "A deterministic identity policy requires at least one origin-key slot.",
      paste0("classes.", class_name, ".origin_key_slots"),
      "class_identifier_contract"
    ))
  }
  for (slot_name in annotations$search_slots) {
    slot <- slots[[slot_name]]
    if (
      slot$multivalued ||
        slot$object_reference ||
        !identical(slot$duckdb_type, "VARCHAR") ||
        slot$sensitive
    ) {
      return(manifest_contract_problem(
        "Search slots must be public scalar text slots.",
        paste0("classes.", class_name, ".search_slots"),
        "class_annotation_contract"
      ))
    }
  }
  core_statement_fields <- c(
    "id",
    "created_at",
    "updated_at",
    "polarity",
    "confidence",
    "status",
    "valid_from",
    "valid_to",
    "asserted_at",
    "superseded_by"
  )
  if (
    length(annotations$qualifier_slots) > 0L &&
      (!identical(class$role, "statement") ||
        length(intersect(
          annotations$qualifier_slots,
          core_statement_fields
        )) >
          0L)
  ) {
    return(manifest_contract_problem(
      "Qualifier slots must be non-core fields on a statement class.",
      paste0("classes.", class_name, ".qualifier_slots"),
      "class_annotation_contract"
    ))
  }
  NULL
}

manifest_semantic_contract_problem <- function(manifest, data_dict) {
  hierarchy_problem <- manifest_class_hierarchy_problem(
    manifest$classes,
    data_dict
  )
  if (!is.null(hierarchy_problem)) {
    return(hierarchy_problem)
  }
  class_names <- names(manifest$classes)
  ancestors <- unlist(
    lapply(manifest$classes, \(class) class$ancestors),
    use.names = FALSE
  )
  known_class_ranges <- unique(c(
    class_names,
    ancestors,
    if (data_dict) character() else names(manifest_core_class_parents())
  ))
  enum_names <- names(manifest$enums)
  global_slot_names <- names(manifest$slots)
  uses_graft_core <- !data_dict && "GraftRecord" %in% ancestors
  if (uses_graft_core) {
    core_global_problem <- manifest_core_global_slot_problem(manifest$slots)
    if (!is.null(core_global_problem)) {
      return(core_global_problem)
    }
  }

  for (enum_name in enum_names) {
    enum <- manifest$enums[[enum_name]]
    if (!identical(enum$name, enum_name)) {
      return(manifest_contract_problem(
        "An enum key must match its declared name.",
        paste0("enums.", enum_name, ".name"),
        "enum_identity_contract"
      ))
    }
    values <- vapply(
      enum$permissible_values,
      \(value) value$value,
      character(1)
    )
    if (
      !all(nzchar(trimws(values))) ||
        anyDuplicated(values)
    ) {
      return(manifest_contract_problem(
        "Enum values must be unique strings that are non-empty after trimming.",
        paste0("enums.", enum_name, ".permissible_values"),
        "enum_value_contract"
      ))
    }
  }

  for (class_name in class_names) {
    class <- manifest$classes[[class_name]]
    if (!identical(class$name, class_name)) {
      return(manifest_contract_problem(
        "A class key must match its declared name.",
        paste0("classes.", class_name, ".name"),
        "class_identity_contract"
      ))
    }
    role_problem <- manifest_class_role_problem(
      class,
      class_name,
      data_dict
    )
    if (!is.null(role_problem)) {
      return(role_problem)
    }
    annotation_problem <- manifest_class_annotation_problem(class, class_name)
    if (!is.null(annotation_problem)) {
      return(annotation_problem)
    }
    slots <- class$slots
    identifiers <- names(Filter(\(slot) slot$identifier, slots))
    valid_identifier <- length(identifiers) == 1L &&
      identical(identifiers, "id") &&
      slots$id$required &&
      !slots$id$multivalued &&
      !slots$id$object_reference &&
      identical(slots$id$duckdb_type, "VARCHAR")
    if (!valid_identifier) {
      return(manifest_contract_problem(
        "Each class must have one required scalar string identifier named id.",
        paste0("classes.", class_name, ".slots"),
        "class_identifier_contract"
      ))
    }
    for (slot_name in names(slots)) {
      global_name <- if (data_dict) {
        paste(class_name, slot_name, sep = ".")
      } else {
        slot_name
      }
      has_global_slot <- global_name %in% global_slot_names
      generated_linkml_slot <- !data_dict &&
        slot_name %in% c("id", "created_at", "updated_at")
      if (!has_global_slot && !generated_linkml_slot) {
        return(manifest_contract_problem(
          "A class-local slot has no corresponding global slot contract.",
          paste("classes", class_name, "slots", slot_name, sep = "."),
          "class_global_slot_contract"
        ))
      }
      if (has_global_slot && data_dict) {
        contract_fields <- c(
          "name",
          "range",
          "duckdb_type",
          "required",
          "multivalued",
          "identifier",
          "object_reference",
          "enum",
          "meaning",
          "pattern",
          "datetime_format",
          "minimum_value",
          "maximum_value",
          "external_identifier",
          "search_weight",
          "sensitive"
        )
        local_contract <- lapply(
          contract_fields,
          \(field) slots[[slot_name]][[field]]
        )
        names(local_contract) <- contract_fields
        global_contract <- lapply(
          contract_fields,
          \(field) manifest$slots[[global_name]][[field]]
        )
        names(global_contract) <- contract_fields
        if (
          !identical(
            canonical_schema_value(local_contract),
            canonical_schema_value(global_contract)
          )
        ) {
          return(manifest_contract_problem(
            "A class-local slot differs from its global slot contract.",
            paste("classes", class_name, "slots", slot_name, sep = "."),
            "class_global_slot_contract"
          ))
        }
      } else if (
        has_global_slot &&
          !identical(
            slots[[slot_name]]$name,
            manifest$slots[[global_name]]$name
          )
      ) {
        return(manifest_contract_problem(
          "A class-local slot has a different global slot identity.",
          paste("classes", class_name, "slots", slot_name, sep = "."),
          "class_global_slot_contract"
        ))
      }
      problem <- manifest_slot_semantic_problem(
        slots[[slot_name]],
        paste("classes", class_name, "slots", slot_name, sep = "."),
        known_class_ranges,
        enum_names
      )
      if (!is.null(problem)) {
        return(problem)
      }
    }
  }
  global_class_ranges <- known_class_ranges
  if (!data_dict) {
    global_object_ranges <- vapply(
      Filter(
        \(slot) slot$object_reference,
        manifest$slots
      ),
      \(slot) slot$range,
      character(1)
    )
    global_class_ranges <- unique(c(
      global_class_ranges,
      global_object_ranges
    ))
  }
  for (slot_name in global_slot_names) {
    problem <- manifest_slot_semantic_problem(
      manifest$slots[[slot_name]],
      paste("slots", slot_name, sep = "."),
      global_class_ranges,
      enum_names
    )
    if (!is.null(problem)) {
      return(problem)
    }
  }
  NULL
}

manifest_shape_problem <- function(manifest, integrity = FALSE) {
  problem <- function(message, field, rule = "manifest_shape_contract") {
    list(message = message, field = field, rule = rule)
  }
  if (!manifest_json_object(manifest)) {
    return(problem("The schema manifest must be a JSON object.", "$"))
  }

  object_fields <- c(
    "schema",
    "classes",
    "slots",
    "enums",
    "graph_projections",
    "identifier_normalization_versions",
    "compiler",
    "fingerprints"
  )
  for (field in object_fields) {
    if (!manifest_json_object(manifest[[field]])) {
      rule <- switch(
        field,
        schema = "schema_source_contract",
        compiler = "compiler_contract",
        fingerprints = "manifest_fingerprints",
        "manifest_shape_contract"
      )
      return(problem(
        paste0("Manifest field `", field, "` must be a JSON object."),
        field,
        rule
      ))
    }
  }
  for (field in c("relations", "validation_invariants")) {
    if (!manifest_json_array(manifest[[field]])) {
      return(problem(
        paste0("Manifest field `", field, "` must be a JSON array."),
        field
      ))
    }
  }
  if (
    "dictionary" %in%
      names(manifest) &&
      !manifest_json_object(manifest$dictionary)
  ) {
    return(problem(
      "Manifest field `dictionary` must be a JSON object when present.",
      "dictionary",
      "dictionary_extension_contract"
    ))
  }
  has_dictionary <- "dictionary" %in% names(manifest)
  if (
    !has_dictionary &&
      manifest_json_object(manifest$compiler) &&
      ("provider" %in%
        names(manifest$compiler) ||
        identical(manifest$compiler$name, "graft-data-dict-adapter"))
  ) {
    return(problem(
      "A compiler provider requires a matching dictionary extension.",
      "dictionary",
      "dictionary_provider_contract"
    ))
  }

  for (field in c("classes", "slots", "enums")) {
    values <- manifest[[field]]
    if (
      length(values) > 0L &&
        !all(vapply(names(values), manifest_json_nonblank_string, logical(1)))
    ) {
      return(problem(
        paste0("Every `", field, "` key must be a nonblank string."),
        field
      ))
    }
    invalid <- which(!vapply(values, manifest_json_object, logical(1)))
    if (length(invalid) > 0L) {
      key <- names(values)[[invalid[[1L]]]]
      return(problem(
        paste0("Every `", field, "` value must be a JSON object."),
        paste(field, key, sep = ".")
      ))
    }
  }
  for (class_name in names(manifest$classes)) {
    class_problem <- manifest_class_shape_problem(
      manifest$classes[[class_name]],
      paste("classes", class_name, sep = ".")
    )
    if (!is.null(class_problem)) {
      return(class_problem)
    }
  }
  for (slot_name in names(manifest$slots)) {
    slot_problem <- manifest_slot_shape_problem(
      manifest$slots[[slot_name]],
      paste("slots", slot_name, sep = ".")
    )
    if (!is.null(slot_problem)) {
      return(slot_problem)
    }
  }
  for (enum_name in names(manifest$enums)) {
    enum_problem <- manifest_enum_shape_problem(
      manifest$enums[[enum_name]],
      paste("enums", enum_name, sep = ".")
    )
    if (!is.null(enum_problem)) {
      return(enum_problem)
    }
  }
  invalid_relations <- which(
    !vapply(
      manifest$relations,
      manifest_json_object,
      logical(1)
    )
  )
  if (length(invalid_relations) > 0L) {
    index <- invalid_relations[[1L]]
    return(problem(
      "Every `relations` value must be a JSON object.",
      paste0("relations[", index, "]")
    ))
  }
  for (index in seq_along(manifest$relations)) {
    relation_problem <- manifest_relation_shape_problem(
      manifest$relations[[index]],
      paste0("relations[", index, "]")
    )
    if (!is.null(relation_problem)) {
      return(relation_problem)
    }
  }
  semantic_problem <- manifest_semantic_contract_problem(
    manifest,
    data_dict = has_dictionary
  )
  if (!is.null(semantic_problem)) {
    return(semantic_problem)
  }
  invalid_invariants <- which(
    !vapply(
      manifest$validation_invariants,
      manifest_json_object,
      logical(1)
    )
  )
  if (length(invalid_invariants) > 0L) {
    index <- invalid_invariants[[1L]]
    return(problem(
      "Every `validation_invariants` value must be a JSON object.",
      paste0("validation_invariants[", index, "]")
    ))
  }
  normalization <- manifest$identifier_normalization_versions
  invalid_normalization <- which(
    !vapply(
      normalization,
      manifest_json_string,
      logical(1)
    )
  )
  if (length(invalid_normalization) > 0L) {
    key <- names(normalization)[[invalid_normalization[[1L]]]]
    return(problem(
      "Identifier-normalization versions must be strings.",
      paste("identifier_normalization_versions", key, sep = ".")
    ))
  }
  expected_graph <- manifest_expected_graph_projections(
    manifest$classes,
    manifest$relations
  )
  if (
    !identical(
      canonical_schema_value(manifest$graph_projections),
      canonical_schema_value(expected_graph)
    )
  ) {
    return(problem(
      "Manifest graph projections do not match classes and relations.",
      "graph_projections",
      "graph_projection_contract"
    ))
  }
  expected_normalization <- manifest_expected_normalization_versions(
    manifest$classes
  )
  if (
    !identical(
      canonical_schema_value(normalization),
      canonical_schema_value(expected_normalization)
    )
  ) {
    return(problem(
      "Identifier normalization metadata does not match global slots.",
      "identifier_normalization_versions",
      "identifier_normalization_contract"
    ))
  }
  if (
    !has_dictionary &&
      !identical(
        canonical_schema_value(manifest$validation_invariants),
        canonical_schema_value(
          manifest_expected_linkml_invariants(manifest$classes)
        )
      )
  ) {
    return(problem(
      "Manifest validation invariants do not match class semantics.",
      "validation_invariants",
      "validation_invariant_contract"
    ))
  }

  schema <- manifest$schema
  schema_required <- c("id", "name", "version", "source_files")
  schema_allowed <- schema_required
  if (
    !all(schema_required %in% names(schema)) ||
      length(setdiff(names(schema), schema_allowed)) > 0L ||
      !manifest_json_linkml_reference(schema$id, "uri") ||
      !manifest_json_string(schema$name, nonempty = TRUE) ||
      !manifest_json_nullable_nonblank_string(schema$version) ||
      !manifest_json_array(schema$source_files) ||
      length(schema$source_files) == 0L
  ) {
    return(problem(
      "Manifest source identity metadata is invalid.",
      "schema",
      "schema_source_contract"
    ))
  }
  source_required <- c(
    "schema_id",
    "name",
    "version",
    "content_digest",
    "root"
  )
  source_allowed <- source_required
  for (index in seq_along(schema$source_files)) {
    source_file <- schema$source_files[[index]]
    valid <- manifest_json_object(source_file) &&
      all(source_required %in% names(source_file)) &&
      length(setdiff(names(source_file), source_allowed)) == 0L &&
      manifest_json_nonblank_string(source_file$name) &&
      is_graft_digest(source_file$content_digest) &&
      is.logical(source_file$root) &&
      length(source_file$root) == 1L &&
      !is.na(source_file$root) &&
      manifest_json_nullable_linkml_reference(source_file$schema_id, "uri") &&
      manifest_json_nullable_nonblank_string(source_file$version)
    if (!valid) {
      return(problem(
        "Manifest source-file metadata is invalid.",
        paste0("schema.source_files[", index, "]"),
        "schema_source_contract"
      ))
    }
  }
  source_schema_ids <- vapply(
    schema$source_files,
    \(source_file) {
      if (is.null(source_file$schema_id)) "" else source_file$schema_id
    },
    character(1)
  )
  source_schema_ids <- source_schema_ids[nzchar(source_schema_ids)]
  source_names <- vapply(
    schema$source_files,
    \(source_file) source_file$name,
    character(1)
  )
  if (anyDuplicated(source_schema_ids) || anyDuplicated(source_names)) {
    return(problem(
      "Manifest source-file schema IDs and names must each be unique.",
      "schema.source_files",
      "schema_source_contract"
    ))
  }
  roots <- which(vapply(
    schema$source_files,
    \(source_file) source_file$root,
    logical(1)
  ))
  if (length(roots) != 1L) {
    return(problem(
      "Manifest source files must declare exactly one root.",
      "schema.source_files",
      "schema_source_contract"
    ))
  }
  root <- schema$source_files[[roots[[1L]]]]
  if (
    !identical(root$schema_id, schema$id) ||
      !identical(root$name, schema$name) ||
      !identical(root$version, schema$version)
  ) {
    return(problem(
      "Manifest root source identity does not match the schema identity.",
      paste0("schema.source_files[", roots[[1L]], "]"),
      "schema_source_contract"
    ))
  }

  compiler <- manifest$compiler
  compiler_required <- c("name", "version", "script_digest")
  compiler_allowed <- c(
    compiler_required,
    "python_version",
    "linkml_runtime_version",
    "provider"
  )
  optional_versions <- intersect(
    c("python_version", "linkml_runtime_version"),
    names(compiler)
  )
  valid_optional_versions <- all(vapply(
    compiler[optional_versions],
    manifest_json_string,
    logical(1),
    nonempty = TRUE
  ))
  if (
    !all(compiler_required %in% names(compiler)) ||
      length(setdiff(names(compiler), compiler_allowed)) > 0L ||
      !manifest_json_string(compiler$name, nonempty = TRUE) ||
      !manifest_json_string(compiler$version, nonempty = TRUE) ||
      !is_graft_digest(compiler$script_digest) ||
      !valid_optional_versions ||
      ("provider" %in%
        names(compiler) &&
        !manifest_json_object(compiler$provider))
  ) {
    return(problem(
      "Manifest compiler metadata is invalid.",
      "compiler",
      if (has_dictionary) {
        "dictionary_compiler_contract"
      } else {
        "compiler_contract"
      }
    ))
  }

  if (has_dictionary) {
    if (
      integrity &&
        (!setequal(
          names(compiler),
          c("name", "version", "script_digest", "provider")
        ) ||
          !identical(compiler$name, "graft-data-dict-adapter") ||
          !identical(compiler$version, data_dict_adapter_version) ||
          !identical(
            compiler$script_digest,
            data_dict_adapter_script_digest()
          ))
    ) {
      return(problem(
        "Manifest compiler metadata does not match the data-dict adapter.",
        "compiler",
        "dictionary_compiler_contract"
      ))
    }
  } else if (
    "provider" %in%
      names(compiler) ||
      identical(compiler$name, "graft-data-dict-adapter")
  ) {
    return(problem(
      "A compiler provider requires a matching dictionary extension.",
      "dictionary",
      "dictionary_provider_contract"
    ))
  } else if (
    !identical(compiler$name, graft_linkml_compiler_name) ||
      !identical(compiler$version, graft_linkml_compiler_version) ||
      !identical(compiler$script_digest, graft_linkml_compiler_digest())
  ) {
    return(problem(
      "Manifest compiler metadata does not match the packaged LinkML compiler.",
      "compiler",
      "compiler_contract"
    ))
  }

  fingerprints <- manifest$fingerprints
  fingerprint_fields <- c(
    "structural_digest",
    "source_digest",
    "build_digest"
  )
  if (
    !setequal(names(fingerprints), fingerprint_fields) ||
      !all(
        vapply(
          fingerprints[fingerprint_fields],
          is_graft_digest,
          logical(1)
        )
      )
  ) {
    return(problem(
      "Manifest fingerprints are invalid.",
      "fingerprints",
      "manifest_fingerprints"
    ))
  }
  if (
    !has_dictionary &&
      !identical(
        fingerprints$source_digest,
        graft_linkml_source_digest(schema$source_files)
      )
  ) {
    return(problem(
      "The LinkML source digest does not match the source-file closure.",
      "fingerprints.source_digest",
      "source_digest_content_mismatch"
    ))
  }
  NULL
}

validate_manifest_shape <- function(
  manifest,
  path = NULL,
  integrity = FALSE,
  subclass = NULL
) {
  problem <- manifest_shape_problem(manifest, integrity = integrity)
  if (is.null(problem)) {
    return(invisible(manifest))
  }
  if (integrity) {
    abort_schema_integrity(
      problem$message,
      field = problem$field,
      rule = problem$rule,
      subclass = subclass
    )
  }
  abort_schema_error(
    problem$message,
    manifest_path = path,
    field = problem$field,
    rule = problem$rule
  )
}

validate_manifest_header <- function(manifest, path) {
  duplicate <- duplicate_json_object_key(manifest)
  if (!is.null(duplicate)) {
    abort_schema_error(
      paste0(
        "Schema manifest `",
        path,
        "` contains duplicate JSON object key `",
        duplicate$key,
        "`."
      ),
      manifest_path = path,
      field = duplicate$path,
      rule = "duplicate_json_key"
    )
  }
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
    "identifier_normalization_versions",
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
  unexpected <- setdiff(names(manifest), c(required, "dictionary"))
  if (length(unexpected) > 0L) {
    abort_schema_error(
      paste0(
        "Schema manifest `",
        path,
        "` has unexpected field(s): ",
        paste(unexpected, collapse = ", "),
        "."
      ),
      manifest_path = path,
      unexpected_fields = unexpected,
      rule = "manifest_fields"
    )
  }
  validate_manifest_shape(manifest, path)
  if (!identical(manifest$manifest_version, graft_manifest_version)) {
    abort_schema_error(
      paste0(
        "Schema manifest `",
        path,
        "` uses unsupported manifest version `",
        manifest$manifest_version,
        "`."
      ),
      manifest_path = path,
      field = "manifest_version",
      rule = "supported_manifest_version",
      observed_value = manifest$manifest_version,
      supported_value = graft_manifest_version
    )
  }
  if (
    !identical(
      manifest$projection_mapping_version,
      graft_projection_mapping_version
    )
  ) {
    abort_schema_error(
      paste0(
        "Schema manifest `",
        path,
        "` uses unsupported projection mapping version `",
        manifest$projection_mapping_version,
        "`."
      ),
      manifest_path = path,
      field = "projection_mapping_version",
      rule = "supported_projection_mapping_version",
      observed_value = manifest$projection_mapping_version,
      supported_value = graft_projection_mapping_version
    )
  }
  validate_manifest_dictionary_header(manifest, path)
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
  unexpected_digests <- setdiff(names(digests), required_digests)
  if (length(unexpected_digests) > 0L) {
    abort_schema_error(
      paste0(
        "Schema manifest `",
        path,
        "` has unexpected fingerprint(s): ",
        paste(unexpected_digests, collapse = ", "),
        "."
      ),
      manifest_path = path,
      unexpected_fingerprints = unexpected_digests,
      rule = "manifest_fingerprints"
    )
  }
  invisible(manifest)
}

validate_manifest_dictionary_header <- function(manifest, path) {
  dictionary <- manifest$dictionary
  compiler <- manifest$compiler
  provider <- if (is.list(compiler) && !is.object(compiler)) {
    compiler$provider
  } else {
    NULL
  }
  if (is.null(dictionary)) {
    if (
      !is.null(provider) ||
        (is.list(compiler) &&
          identical(compiler$name, "graft-data-dict-adapter"))
    ) {
      abort_schema_error(
        paste(
          "A data-dict compiler or provider requires a matching dictionary",
          "extension."
        ),
        manifest_path = path,
        field = "dictionary",
        rule = "dictionary_provider_contract"
      )
    }
    return(invisible(manifest))
  }
  required <- c(
    "provider",
    "document",
    "profile",
    "defaults",
    "adapter_version",
    "requirements",
    "mapped",
    "preserved",
    "not_enforced"
  )
  if (!is.list(dictionary) || is.object(dictionary)) {
    abort_schema_error(
      "The dictionary extension must be an object.",
      manifest_path = path,
      field = "dictionary",
      rule = "dictionary_extension_contract"
    )
  }
  missing <- setdiff(required, names(dictionary))
  unexpected <- setdiff(names(dictionary), required)
  if (length(missing) > 0L || length(unexpected) > 0L) {
    abort_schema_error(
      "The dictionary extension has invalid fields.",
      manifest_path = path,
      field = "dictionary",
      rule = "dictionary_extension_contract",
      missing_fields = missing,
      unexpected_fields = unexpected
    )
  }
  if (
    !is.list(compiler) ||
      is.object(compiler) ||
      !setequal(
        names(compiler),
        c("name", "version", "script_digest", "provider")
      ) ||
      !is_graft_digest(compiler$script_digest) ||
      !identical(compiler$script_digest, data_dict_adapter_script_digest())
  ) {
    abort_schema_error(
      "The compiler metadata is invalid for a data-dict manifest.",
      manifest_path = path,
      field = "compiler",
      rule = "dictionary_compiler_contract"
    )
  }
  validate_data_dict_provider_header(provider, path)
  if (!identical(dictionary$provider, provider)) {
    abort_schema_error(
      "Dictionary and compiler provider metadata must be identical.",
      manifest_path = path,
      field = "dictionary.provider",
      rule = "dictionary_provider_contract"
    )
  }
  if (
    !identical(compiler$name, "graft-data-dict-adapter") ||
      !identical(compiler$version, dictionary$adapter_version)
  ) {
    abort_schema_error(
      "The compiler metadata does not match the data-dict adapter.",
      manifest_path = path,
      field = "compiler",
      rule = "dictionary_compiler_contract",
      expected_name = "graft-data-dict-adapter",
      expected_version = dictionary$adapter_version,
      observed_name = compiler$name,
      observed_version = compiler$version
    )
  }
  if (
    !is.list(dictionary$document) ||
      is.object(dictionary$document) ||
      !identical(dictionary$profile, "graft-table-v1") ||
      !is_nonempty_string(dictionary$adapter_version) ||
      !is.list(dictionary$requirements) ||
      length(dictionary$requirements) == 0L ||
      !all(vapply(dictionary$requirements, is_nonempty_string, logical(1))) ||
      !is.list(dictionary$preserved) ||
      !all(vapply(dictionary$preserved, is_nonempty_string, logical(1))) ||
      !data_dict_mapped_contract_is_valid(dictionary$mapped) ||
      !is.list(dictionary$not_enforced) ||
      length(dictionary$not_enforced) == 0L
  ) {
    abort_schema_error(
      "The dictionary extension has invalid contract metadata.",
      manifest_path = path,
      field = "dictionary",
      rule = "dictionary_extension_contract"
    )
  }
  document_version <- dictionary$document[["$version"]]
  if (!identical(document_version, provider$export_format_version)) {
    abort_schema_error(
      paste(
        "The public data-dict document version must match the provider",
        "export-format version."
      ),
      manifest_path = path,
      field = "dictionary.document.$version",
      rule = "dictionary_export_format_version",
      observed_value = document_version,
      expected_value = provider$export_format_version
    )
  }
  tryCatch(
    data_dict_validate_root(dictionary$document),
    graft_schema_error = function(error) {
      abort_schema_error(
        paste0(
          "The public data-dict document is invalid: ",
          conditionMessage(error)
        ),
        manifest_path = path,
        field = "dictionary.document",
        rule = "dictionary_public_document_contract",
        parent = error
      )
    }
  )
  sanitized_document <- tryCatch(
    data_dict_public_document(dictionary$document),
    error = \(error) NULL
  )
  if (
    is.null(sanitized_document) ||
      !identical(sanitized_document, dictionary$document)
  ) {
    abort_schema_error(
      "The public data-dict document contains redacted provider fields.",
      manifest_path = path,
      field = "dictionary.document",
      rule = "dictionary_public_document_contract"
    )
  }
  if (!identical(dictionary$adapter_version, data_dict_adapter_version)) {
    abort_schema_error(
      paste0(
        "The data-dict adapter version `",
        dictionary$adapter_version,
        "` is not supported."
      ),
      manifest_path = path,
      field = "dictionary.adapter_version",
      rule = "supported_data_dict_adapter_version",
      observed_value = dictionary$adapter_version,
      supported_value = data_dict_adapter_version
    )
  }
  validate_data_dict_projection_contract(manifest, path)
  defaults <- dictionary$defaults
  if (
    !is.list(defaults) ||
      !setequal(names(defaults), c("role", "id_policy", "id_format")) ||
      !identical(defaults$role, "node") ||
      !identical(defaults$id_policy, "require") ||
      !identical(defaults$id_format, "linkml") ||
      !all(
        vapply(
          dictionary$not_enforced,
          data_dict_loss_is_valid,
          logical(1)
        )
      )
  ) {
    abort_schema_error(
      "The dictionary extension has invalid defaults or loss metadata.",
      manifest_path = path,
      field = "dictionary",
      rule = "dictionary_extension_contract"
    )
  }
  invisible(manifest)
}

data_dict_mapped_contract_is_valid <- function(mapped) {
  fields <- c(
    "tables_to_classes",
    "columns_to_slots",
    "enums",
    "foreign_keys_to_object_references",
    "list_columns_to_relations",
    "restricted_display_to_sensitive"
  )
  count_fields <- fields[fields != "restricted_display_to_sensitive"]
  valid_count <- function(value, minimum) {
    is.numeric(value) &&
      length(value) == 1L &&
      !is.na(value) &&
      is.finite(value) &&
      value == trunc(value) &&
      value >= minimum
  }
  is.list(mapped) &&
    !is.object(mapped) &&
    setequal(names(mapped), fields) &&
    valid_count(mapped$tables_to_classes, 1L) &&
    valid_count(mapped$columns_to_slots, 1L) &&
    all(vapply(
      mapped[count_fields[-c(1L, 2L)]],
      valid_count,
      logical(1),
      0L
    )) &&
    is.logical(mapped$restricted_display_to_sensitive) &&
    length(mapped$restricted_display_to_sensitive) == 1L &&
    !is.na(mapped$restricted_display_to_sensitive)
}

validate_data_dict_projection_contract <- function(manifest, path) {
  dictionary <- manifest$dictionary
  document <- dictionary$document
  schema <- manifest$schema
  if (!is.list(schema) || is.object(schema)) {
    abort_schema_error(
      "The data-dict source identity must be an object.",
      manifest_path = path,
      field = "schema",
      rule = "dictionary_projection_contract"
    )
  }
  source_files <- schema$source_files
  source_file <- if (
    is.list(source_files) &&
      length(source_files) == 1L &&
      is.list(source_files[[1L]]) &&
      !is.object(source_files[[1L]])
  ) {
    source_files[[1L]]
  } else {
    NULL
  }
  if (is.null(source_file)) {
    abort_schema_error(
      "A data-dict manifest must contain one source-file object.",
      manifest_path = path,
      field = "schema.source_files",
      rule = "dictionary_projection_contract"
    )
  }
  source <- tryCatch(
    data_dict_manifest_source(document, source_file$content_digest),
    graft_schema_error = function(error) {
      abort_schema_error(
        paste0(
          "The data-dict source identity is invalid: ",
          conditionMessage(error)
        ),
        manifest_path = path,
        field = "schema",
        rule = "dictionary_projection_contract",
        parent = error
      )
    }
  )
  expected_schema <- list(
    id = source$id,
    name = source$name,
    version = source$version,
    source_files = list(list(
      schema_id = source$id,
      name = source$name,
      version = source$version,
      content_digest = source$content_digest,
      root = TRUE
    ))
  )
  if (!identical(schema, expected_schema)) {
    abort_schema_error(
      "The data-dict source identity does not match its public document.",
      manifest_path = path,
      field = "schema",
      rule = "dictionary_projection_contract"
    )
  }
  expected_source_digest <- data_dict_manifest_source_digest(
    document,
    source
  )
  if (
    !identical(
      manifest$fingerprints$source_digest,
      expected_source_digest
    )
  ) {
    abort_schema_error(
      "The data-dict source digest does not match its public contract.",
      manifest_path = path,
      field = "fingerprints.source_digest",
      rule = "source_digest_content_mismatch"
    )
  }
  compiled <- tryCatch(
    data_dict_compile_tables(document, source),
    graft_schema_error = function(error) {
      abort_schema_error(
        paste0(
          "The public data-dict document cannot reproduce its contract: ",
          conditionMessage(error)
        ),
        manifest_path = path,
        field = "dictionary.document",
        rule = "dictionary_projection_contract",
        parent = error
      )
    }
  )
  expected_dictionary <- data_dict_dictionary_contract(
    document,
    manifest$compiler$provider,
    compiled
  )
  expected_projection <- list(
    classes = compiled$classes,
    slots = compiled$slots,
    enums = compiled$enums,
    relations = compiled$relations,
    graph_projections = data_dict_graph_projections(
      compiled$classes,
      compiled$relations
    ),
    validation_invariants = list(),
    identifier_normalization_versions = stats::setNames(
      list(),
      character()
    )
  )
  observed_projection <- manifest[names(expected_projection)]
  if (
    !identical(dictionary, expected_dictionary) ||
      !identical(observed_projection, expected_projection)
  ) {
    abort_schema_error(
      paste(
        "The data-dict extension does not reproduce the manifest's compiled",
        "projection."
      ),
      manifest_path = path,
      field = "dictionary",
      rule = "dictionary_projection_contract"
    )
  }
  invisible(manifest)
}

validate_data_dict_provider_header <- function(provider, path) {
  allowed <- c(
    "name",
    "export_format_version",
    "source_spec_version",
    "cli_version",
    "cli_digest",
    "revision",
    "source_format"
  )
  if (
    !is.list(provider) ||
      is.object(provider) ||
      !all(c("name", "export_format_version") %in% names(provider)) ||
      length(setdiff(names(provider), allowed)) > 0L ||
      !identical(provider$name, "data-dict") ||
      !is_nonempty_string(provider$export_format_version) ||
      (!is.null(provider$source_spec_version) &&
        !is_optional_string(provider$source_spec_version)) ||
      (!is.null(provider$cli_version) &&
        !is_optional_string(provider$cli_version)) ||
      (!is.null(provider$revision) &&
        !is_optional_string(provider$revision)) ||
      (!is.null(provider$cli_digest) &&
        !is_graft_digest(provider$cli_digest)) ||
      (!is.null(provider$source_format) &&
        !provider$source_format %in% c("yaml", "resolved_json"))
  ) {
    abort_schema_error(
      "The data-dict provider metadata is invalid.",
      manifest_path = path,
      field = "compiler.provider",
      rule = "dictionary_provider_contract"
    )
  }
  yaml_provider <- identical(provider$source_format, "yaml") &&
    is_nonempty_string(provider$source_spec_version) &&
    is_nonempty_string(provider$cli_version) &&
    is_graft_digest(provider$cli_digest)
  resolved_provider <- identical(provider$source_format, "resolved_json") &&
    is.null(provider$source_spec_version) &&
    is.null(provider$cli_version) &&
    is.null(provider$cli_digest)
  if (!yaml_provider && !resolved_provider) {
    abort_schema_error(
      "The data-dict provider metadata is inconsistent with its source format.",
      manifest_path = path,
      field = "compiler.provider",
      rule = "dictionary_provider_source_format"
    )
  }
  if (
    !identical(
      provider$export_format_version,
      data_dict_export_format_version
    )
  ) {
    abort_schema_error(
      paste0(
        "The data-dict export-format version `",
        provider$export_format_version,
        "` is not supported."
      ),
      manifest_path = path,
      field = "compiler.provider.export_format_version",
      rule = "supported_data_dict_export_format_version",
      observed_value = provider$export_format_version,
      supported_value = data_dict_export_format_version
    )
  }
  invisible(provider)
}

data_dict_loss_is_valid <- function(loss) {
  is.list(loss) &&
    !is.object(loss) &&
    identical(sort(names(loss)), c("handling", "status")) &&
    is_nonempty_string(loss$status) &&
    is_nonempty_string(loss$handling)
}

validate_manifest_integrity <- function(schema, subclass = NULL) {
  if (!is_compiled_schema(schema)) {
    abort_schema_integrity(
      "Schema integrity validation requires a compiled schema.",
      subclass = subclass
    )
  }
  manifest <- schema$manifest
  duplicate <- duplicate_json_object_key(manifest)
  if (!is.null(duplicate)) {
    abort_schema_integrity(
      paste0(
        "The schema manifest contains duplicate JSON object key `",
        duplicate$key,
        "`."
      ),
      field = duplicate$path,
      rule = "duplicate_json_key",
      subclass = subclass
    )
  }
  validate_manifest_shape(
    manifest,
    path = schema$path,
    integrity = TRUE,
    subclass = subclass
  )
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
  declared_build_digest <- scalar_character(fingerprints$build_digest)
  computed_build_digest <- manifest_build_digest(manifest)
  if (!identical(declared_build_digest, computed_build_digest)) {
    abort_schema_integrity(
      "The declared build digest does not match the manifest content.",
      declared_build_digest = declared_build_digest,
      computed_build_digest = computed_build_digest,
      rule = "build_digest_content_mismatch",
      subclass = subclass
    )
  }
  invisible(schema)
}

manifest_build_digest <- function(manifest) {
  content <- unserialize(serialize(manifest, NULL))
  content$fingerprints$build_digest <- NULL
  graft_sha256(canonical_json(content))
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
  range <- scalar_character(slot$range)
  object_reference <- scalar_logical(slot$object_reference)
  datetime_format <- scalar_character(slot$datetime_format)
  valid_datetime_format <- if (identical(range, "datetime")) {
    is.na(datetime_format) ||
      datetime_format %in% c("offset", "local_utc")
  } else {
    is.na(datetime_format)
  }
  if (!valid_datetime_format) {
    abort_schema_integrity(
      "Datetime input metadata does not match the slot range.",
      record_class = record_class,
      slot = slot_name,
      range = range,
      datetime_format = datetime_format,
      rule = "datetime_format_contract",
      subclass = subclass
    )
  }
  primitive_types <- manifest_primitive_duckdb_types()
  enum <- scalar_character(slot$enum)
  expected <- if (
    object_reference || (!is.na(enum) && identical(enum, range))
  ) {
    "VARCHAR"
  } else if (!is.na(range) && range %in% names(primitive_types)) {
    unname(primitive_types[[range]])
  } else {
    abort_schema_integrity(
      "A slot range must resolve to a supported primitive, enum, or class.",
      record_class = record_class,
      slot = slot_name,
      range = range,
      rule = "slot_range_contract",
      subclass = subclass
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
        !nzchar(trimws(view))
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
        !all(nzchar(trimws(view_columns))) ||
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
    !nzchar(trimws(projection_names)) |
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
    nzchar(trimws(predicate))
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
