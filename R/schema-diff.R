#' Compare two compiled graft schemas
#'
#' Compatibility requires both matching structural content and structural
#' digests that faithfully describe that content. The returned report also
#' identifies class, slot, enum, table, and generated-relation changes so a
#' mismatch is useful to an interactive user or pipeline.
#'
#' @param old_schema A `kg_schema` object or manifest path.
#' @param new_schema A `kg_schema` object or manifest path.
#'
#' @return A `kg_schema_diff` object.
#' @export
kg_schema_diff <- function(old_schema, new_schema) {
  old_schema <- as_kg_schema(old_schema, "old_schema")
  new_schema <- as_kg_schema(new_schema, "new_schema")
  old <- old_schema$manifest
  new <- new_schema$manifest

  old_digest <- scalar_character(old$fingerprints$structural_digest)
  new_digest <- scalar_character(new$fingerprints$structural_digest)
  old_content <- manifest_structural_json(old)
  new_content <- manifest_structural_json(new)
  content_matches <- identical(old_content, new_content)
  integrity <- structural_digest_integrity_details(
    old,
    new,
    old_digest,
    new_digest
  )
  compatible <- content_matches && nrow(integrity) == 0L

  if (compatible) {
    return(new_kg_schema_diff(
      compatible = TRUE,
      old_structural_digest = old_digest,
      new_structural_digest = new_digest,
      classes = empty_named_contract_diff(),
      slots = empty_class_slot_diff(),
      enums = empty_named_contract_diff(),
      tables = empty_named_contract_diff(),
      relations = empty_named_contract_diff(),
      classification = "compatible",
      details = empty_schema_change_details()
    ))
  }

  details <- bind_schema_change_details(
    schema_change_details(old, new),
    integrity
  )
  if (nrow(details) == 0L) {
    details <- new_schema_change_detail(
      path = "/fingerprints/structural_digest",
      object_type = "manifest",
      change = "changed",
      field = "structural_digest",
      old = old_digest,
      new = new_digest,
      classification = "unsupported",
      rule = "unexplained_structural_digest_change"
    )
  }

  new_kg_schema_diff(
    compatible = FALSE,
    old_structural_digest = old_digest,
    new_structural_digest = new_digest,
    classes = diff_named_contract(old$classes, new$classes),
    slots = diff_class_slots(old$classes, new$classes),
    enums = diff_named_contract(old$enums, new$enums),
    tables = diff_named_contract(old$tables, new$tables),
    relations = diff_relations(old$relations, new$relations),
    classification = schema_change_classification(details$classification),
    details = details
  )
}

manifest_structural_contract <- function(manifest) {
  list(
    relational_mapping_version = manifest$relational_mapping_version,
    classes = manifest$classes,
    tables = manifest$tables,
    relations = manifest$relations,
    enums = manifest$enums,
    graph_projections = manifest$graph_projections,
    validation_invariants = manifest$validation_invariants,
    identifier_normalization_versions = manifest$identifier_normalization_versions
  )
}

manifest_structural_json <- function(manifest) {
  canonical_json(canonical_schema_change_value(
    manifest_structural_contract(manifest)
  ))
}

manifest_structural_digest <- function(manifest) {
  paste0(
    "sha256:",
    digest::digest(
      manifest_structural_json(manifest),
      algo = "sha256",
      serialize = FALSE
    )
  )
}

structural_digest_integrity_details <- function(
  old,
  new,
  old_digest,
  new_digest
) {
  old_computed <- manifest_structural_digest(old)
  new_computed <- manifest_structural_digest(new)
  if (
    identical(old_digest, old_computed) &&
      identical(new_digest, new_computed)
  ) {
    return(empty_schema_change_details())
  }
  new_schema_change_detail(
    path = "/fingerprints/structural_digest",
    object_type = "manifest",
    change = "changed",
    field = "structural_digest",
    old = list(declared = old_digest, computed = old_computed),
    new = list(declared = new_digest, computed = new_computed),
    classification = "unsupported",
    rule = "structural_digest_content_mismatch"
  )
}

empty_named_contract_diff <- function() {
  list(added = character(), removed = character(), changed = character())
}

empty_class_slot_diff <- function() {
  data.frame(
    class = character(),
    slot = character(),
    change = character(),
    stringsAsFactors = FALSE
  )
}

empty_schema_change_details <- function() {
  data.frame(
    path = character(),
    object_type = character(),
    change = character(),
    field = character(),
    old_summary = character(),
    new_summary = character(),
    classification = character(),
    rule = character(),
    stringsAsFactors = FALSE
  )
}

new_schema_change_detail <- function(
  path,
  object_type,
  change,
  field = NA_character_,
  old = NULL,
  new = NULL,
  classification,
  rule
) {
  data.frame(
    path = path,
    object_type = object_type,
    change = change,
    field = field,
    old_summary = if (identical(change, "added")) {
      NA_character_
    } else {
      schema_change_summary(old)
    },
    new_summary = if (identical(change, "removed")) {
      NA_character_
    } else {
      schema_change_summary(new)
    },
    classification = classification,
    rule = rule,
    stringsAsFactors = FALSE
  )
}

schema_change_summary <- function(value) {
  as.character(jsonlite::toJSON(
    canonical_schema_change_value(value),
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    pretty = FALSE
  ))
}

canonical_schema_change_value <- function(value) {
  if (!is.list(value) || is.null(value)) {
    return(value)
  }
  value_names <- names(value)
  if (!is.null(value_names) && all(nzchar(value_names))) {
    value <- value[order(value_names)]
  }
  lapply(value, canonical_schema_change_value)
}

schema_change_path <- function(...) {
  components <- unlist(list(...), use.names = FALSE)
  escaped <- gsub("~", "~0", as.character(components), fixed = TRUE)
  escaped <- gsub("/", "~1", escaped, fixed = TRUE)
  paste0("/", paste(escaped, collapse = "/"))
}

bind_schema_change_details <- function(...) {
  inputs <- list(...)
  rows <- list()
  for (input in inputs) {
    if (is.data.frame(input)) {
      rows[[length(rows) + 1L]] <- input
    } else if (is.list(input)) {
      rows <- c(rows, Filter(is.data.frame, input))
    }
  }
  rows <- Filter(\(.x) nrow(.x) > 0L, rows)
  if (length(rows) == 0L) {
    return(empty_schema_change_details())
  }
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result[
    order(
      result$path,
      result$change,
      result$field,
      result$classification,
      na.last = TRUE
    ),
    ,
    drop = FALSE
  ]
}

schema_change_classification <- function(classifications) {
  severity <- c(
    compatible = 0L,
    additive = 1L,
    review_required = 2L,
    destructive = 3L,
    unsupported = 4L
  )
  classifications <- unique(classifications)
  unknown <- setdiff(classifications, names(severity))
  if (length(unknown) > 0L) {
    return("unsupported")
  }
  classifications[[which.max(unname(severity[classifications]))]]
}

schema_change_details <- function(old, new) {
  added_classes <- setdiff(names(new$classes), names(old$classes))
  bind_schema_change_details(
    diff_class_details(old$classes, new$classes),
    diff_enum_details(old$enums, new$enums),
    diff_table_details(old$tables, new$tables),
    diff_relation_details(old$relations, new$relations),
    diff_graph_projection_details(
      old$graph_projections,
      new$graph_projections
    ),
    diff_validation_details(
      old$validation_invariants,
      new$validation_invariants,
      added_classes
    ),
    diff_normalization_details(
      old$identifier_normalization_versions,
      new$identifier_normalization_versions
    ),
    diff_relational_mapping_version(
      old$relational_mapping_version,
      new$relational_mapping_version
    )
  )
}

diff_class_details <- function(old, new) {
  rows <- diff_named_object_additions(
    old,
    new,
    collection = "classes",
    object_type = "class",
    added_classification = "additive",
    added_rule = "optional_class_added",
    removed_classification = "destructive",
    removed_rule = "class_removed"
  )
  common <- sort(intersect(names(old), names(new)))
  for (class_name in common) {
    path <- schema_change_path("classes", class_name)
    rows[[length(rows) + 1L]] <- diff_object_properties(
      old[[class_name]],
      new[[class_name]],
      path = path,
      object_type = "class",
      exclude = c("slots", "relations"),
      classify = classify_class_property
    )
    rows[[length(rows) + 1L]] <- diff_slot_details(
      old[[class_name]]$slots,
      new[[class_name]]$slots,
      class_name
    )
  }
  bind_schema_change_details(rows)
}

classify_class_property <- function(field, change, old, new) {
  if (
    field %in%
      c(
        "name",
        "table",
        "id_policy",
        "id_format",
        "origin_key_slots",
        "role",
        "statement_shape",
        "relations"
      )
  ) {
    return(c("unsupported", paste0("class_", field, "_change")))
  }
  c("review_required", paste0("class_", field, "_change"))
}

diff_slot_details <- function(old, new, class_name) {
  old <- if (is.null(old)) list() else old
  new <- if (is.null(new)) list() else new
  rows <- list()
  added <- sort(setdiff(names(new), names(old)))
  removed <- sort(setdiff(names(old), names(new)))
  for (slot_name in added) {
    slot <- new[[slot_name]]
    optional <- !isTRUE(slot$required)
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = schema_change_path("classes", class_name, "slots", slot_name),
      object_type = "slot",
      change = "added",
      new = slot,
      classification = if (optional) "additive" else "unsupported",
      rule = if (optional) "optional_slot_added" else "required_slot_added"
    )
  }
  for (slot_name in removed) {
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = schema_change_path("classes", class_name, "slots", slot_name),
      object_type = "slot",
      change = "removed",
      old = old[[slot_name]],
      classification = "destructive",
      rule = "slot_removed"
    )
  }
  common <- sort(intersect(names(old), names(new)))
  for (slot_name in common) {
    rows[[length(rows) + 1L]] <- diff_object_properties(
      old[[slot_name]],
      new[[slot_name]],
      path = schema_change_path(
        "classes",
        class_name,
        "slots",
        slot_name
      ),
      object_type = "slot",
      classify = classify_slot_property
    )
  }
  bind_schema_change_details(rows)
}

classify_slot_property <- function(field, change, old, new) {
  unsupported <- c(
    "name",
    "column",
    "range",
    "relational_type",
    "required",
    "multivalued",
    "ordered",
    "identifier",
    "object_reference",
    "enum",
    "foreign_key",
    "external_identifier"
  )
  if (field %in% unsupported) {
    return(c("unsupported", paste0("slot_", field, "_change")))
  }
  c("review_required", paste0("slot_", field, "_change"))
}

diff_enum_details <- function(old, new) {
  rows <- diff_named_object_additions(
    old,
    new,
    collection = "enums",
    object_type = "enum",
    added_classification = "additive",
    added_rule = "enum_added",
    removed_classification = "destructive",
    removed_rule = "enum_removed"
  )
  common <- sort(intersect(names(old), names(new)))
  for (enum_name in common) {
    path <- schema_change_path("enums", enum_name)
    rows[[length(rows) + 1L]] <- diff_object_properties(
      old[[enum_name]],
      new[[enum_name]],
      path = path,
      object_type = "enum",
      exclude = "permissible_values",
      classify = function(field, change, old, new) {
        if (identical(field, "name")) {
          c("unsupported", "enum_name_change")
        } else {
          c("review_required", paste0("enum_", field, "_change"))
        }
      }
    )
    rows[[length(rows) + 1L]] <- diff_enum_value_details(
      old[[enum_name]]$permissible_values,
      new[[enum_name]]$permissible_values,
      enum_name
    )
  }
  bind_schema_change_details(rows)
}

diff_enum_value_details <- function(old, new, enum_name) {
  old <- schema_named_list(old, "value")
  new <- schema_named_list(new, "value")
  rows <- list()
  added <- sort(setdiff(names(new), names(old)))
  removed <- sort(setdiff(names(old), names(new)))
  for (value_name in added) {
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = schema_change_path(
        "enums",
        enum_name,
        "permissible_values",
        value_name
      ),
      object_type = "enum_value",
      change = "added",
      new = new[[value_name]],
      classification = "additive",
      rule = "enum_value_added"
    )
  }
  for (value_name in removed) {
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = schema_change_path(
        "enums",
        enum_name,
        "permissible_values",
        value_name
      ),
      object_type = "enum_value",
      change = "removed",
      old = old[[value_name]],
      classification = "destructive",
      rule = "enum_value_removed"
    )
  }
  common <- sort(intersect(names(old), names(new)))
  for (value_name in common) {
    rows[[length(rows) + 1L]] <- diff_object_properties(
      old[[value_name]],
      new[[value_name]],
      path = schema_change_path(
        "enums",
        enum_name,
        "permissible_values",
        value_name
      ),
      object_type = "enum_value",
      classify = function(field, change, old, new) {
        if (identical(field, "value")) {
          c("unsupported", "enum_value_name_change")
        } else {
          c("review_required", paste0("enum_value_", field, "_change"))
        }
      }
    )
  }
  bind_schema_change_details(rows)
}

diff_table_details <- function(old, new) {
  rows <- diff_named_object_additions(
    old,
    new,
    collection = "tables",
    object_type = "table",
    added_classification = "additive",
    added_rule = "table_added",
    removed_classification = "destructive",
    removed_rule = "table_removed"
  )
  common <- sort(intersect(names(old), names(new)))
  for (table_name in common) {
    path <- schema_change_path("tables", table_name)
    rows[[length(rows) + 1L]] <- diff_object_properties(
      old[[table_name]],
      new[[table_name]],
      path = path,
      object_type = "table",
      exclude = "columns",
      classify = function(field, change, old, new) {
        if (field %in% c("name", "class")) {
          c("unsupported", paste0("table_", field, "_change"))
        } else {
          c("review_required", paste0("table_", field, "_change"))
        }
      }
    )
    rows[[length(rows) + 1L]] <- diff_column_details(
      old[[table_name]]$columns,
      new[[table_name]]$columns,
      path,
      "table_column",
      allow_nullable_addition = TRUE
    )
  }
  bind_schema_change_details(rows)
}

diff_relation_details <- function(old, new) {
  old <- relation_map(old)
  new <- relation_map(new)
  rows <- diff_named_object_additions(
    old,
    new,
    collection = "relations",
    object_type = "relation",
    added_classification = "additive",
    added_rule = "relation_added",
    removed_classification = "destructive",
    removed_rule = "relation_removed"
  )
  common <- sort(intersect(names(old), names(new)))
  for (relation_name in common) {
    path <- schema_change_path("relations", relation_name)
    rows[[length(rows) + 1L]] <- diff_object_properties(
      old[[relation_name]],
      new[[relation_name]],
      path = path,
      object_type = "relation",
      exclude = "columns",
      classify = function(field, change, old, new) {
        if (identical(field, "predicate")) {
          c("review_required", "relation_predicate_change")
        } else {
          c("unsupported", paste0("relation_", field, "_change"))
        }
      }
    )
    rows[[length(rows) + 1L]] <- diff_column_details(
      old[[relation_name]]$columns,
      new[[relation_name]]$columns,
      path,
      "relation_column",
      allow_nullable_addition = FALSE
    )
  }
  bind_schema_change_details(rows)
}

diff_column_details <- function(
  old,
  new,
  parent_path,
  object_type,
  allow_nullable_addition
) {
  old <- schema_column_map(old)
  new <- schema_column_map(new)
  rows <- list()
  added <- sort(setdiff(names(new), names(old)))
  removed <- sort(setdiff(names(old), names(new)))
  for (column_name in added) {
    column <- new[[column_name]]
    safe <- isTRUE(allow_nullable_addition) && isTRUE(column$nullable)
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = paste0(parent_path, "/columns/", json_pointer_escape(column_name)),
      object_type = object_type,
      change = "added",
      new = column,
      classification = if (safe) "additive" else "unsupported",
      rule = if (safe) "nullable_column_added" else "column_added"
    )
  }
  for (column_name in removed) {
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = paste0(parent_path, "/columns/", json_pointer_escape(column_name)),
      object_type = object_type,
      change = "removed",
      old = old[[column_name]],
      classification = "destructive",
      rule = "column_removed"
    )
  }
  common <- sort(intersect(names(old), names(new)))
  for (column_name in common) {
    rows[[length(rows) + 1L]] <- diff_object_properties(
      old[[column_name]],
      new[[column_name]],
      path = paste0(
        parent_path,
        "/columns/",
        json_pointer_escape(column_name)
      ),
      object_type = object_type,
      classify = function(field, change, old, new) {
        c("unsupported", paste0("column_", field, "_change"))
      }
    )
  }
  bind_schema_change_details(rows)
}

diff_graph_projection_details <- function(old, new) {
  diff_schema_tree(
    old,
    new,
    path = "/graph_projections",
    object_type = "graph_projection",
    added_classification = "additive",
    removed_classification = "destructive",
    changed_classification = "review_required",
    rule_prefix = "graph_projection"
  )
}

diff_validation_details <- function(old, new, added_classes) {
  old <- validation_map(old)
  new <- validation_map(new)
  rows <- list()
  added <- sort(setdiff(names(new), names(old)))
  removed <- sort(setdiff(names(old), names(new)))
  for (key in added) {
    invariant <- new[[key]]
    class_name <- scalar_character(invariant$class, "")
    safe <- nzchar(class_name) && class_name %in% added_classes
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = schema_change_path("validation_invariants", key),
      object_type = "validation_invariant",
      change = "added",
      new = invariant,
      classification = if (safe) "additive" else "review_required",
      rule = if (safe) {
        "new_class_validation_added"
      } else {
        "validation_added"
      }
    )
  }
  for (key in removed) {
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = schema_change_path("validation_invariants", key),
      object_type = "validation_invariant",
      change = "removed",
      old = old[[key]],
      classification = "review_required",
      rule = "validation_removed"
    )
  }
  common <- sort(intersect(names(old), names(new)))
  for (key in common) {
    rows[[length(rows) + 1L]] <- diff_object_properties(
      old[[key]],
      new[[key]],
      path = schema_change_path("validation_invariants", key),
      object_type = "validation_invariant",
      classify = function(field, change, old, new) {
        c("review_required", paste0("validation_", field, "_change"))
      }
    )
  }
  bind_schema_change_details(rows)
}

diff_normalization_details <- function(old, new) {
  old <- if (is.null(old)) list() else old
  new <- if (is.null(new)) list() else new
  rows <- list()
  added <- sort(setdiff(names(new), names(old)))
  removed <- sort(setdiff(names(old), names(new)))
  for (namespace in added) {
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = schema_change_path(
        "identifier_normalization_versions",
        namespace
      ),
      object_type = "identifier_normalization",
      change = "added",
      new = new[[namespace]],
      classification = "additive",
      rule = "identifier_normalization_added"
    )
  }
  for (namespace in removed) {
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = schema_change_path(
        "identifier_normalization_versions",
        namespace
      ),
      object_type = "identifier_normalization",
      change = "removed",
      old = old[[namespace]],
      classification = "destructive",
      rule = "identifier_normalization_removed"
    )
  }
  common <- sort(intersect(names(old), names(new)))
  for (namespace in common) {
    if (!identical(old[[namespace]], new[[namespace]])) {
      rows[[length(rows) + 1L]] <- new_schema_change_detail(
        path = schema_change_path(
          "identifier_normalization_versions",
          namespace
        ),
        object_type = "identifier_normalization",
        change = "changed",
        field = namespace,
        old = old[[namespace]],
        new = new[[namespace]],
        classification = "unsupported",
        rule = "identifier_normalization_version_change"
      )
    }
  }
  bind_schema_change_details(rows)
}

diff_relational_mapping_version <- function(old, new) {
  if (identical(old, new)) {
    return(empty_schema_change_details())
  }
  new_schema_change_detail(
    path = "/relational_mapping_version",
    object_type = "manifest",
    change = "changed",
    field = "relational_mapping_version",
    old = old,
    new = new,
    classification = "unsupported",
    rule = "relational_mapping_version_change"
  )
}

diff_named_object_additions <- function(
  old,
  new,
  collection,
  object_type,
  added_classification,
  added_rule,
  removed_classification,
  removed_rule
) {
  old <- if (is.null(old)) list() else old
  new <- if (is.null(new)) list() else new
  rows <- list()
  for (name in sort(setdiff(names(new), names(old)))) {
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = schema_change_path(collection, name),
      object_type = object_type,
      change = "added",
      new = new[[name]],
      classification = added_classification,
      rule = added_rule
    )
  }
  for (name in sort(setdiff(names(old), names(new)))) {
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = schema_change_path(collection, name),
      object_type = object_type,
      change = "removed",
      old = old[[name]],
      classification = removed_classification,
      rule = removed_rule
    )
  }
  rows
}

diff_object_properties <- function(
  old,
  new,
  path,
  object_type,
  classify,
  exclude = character()
) {
  old <- if (is.null(old)) list() else old
  new <- if (is.null(new)) list() else new
  fields <- sort(setdiff(union(names(old), names(new)), exclude))
  rows <- list()
  for (field in fields) {
    old_present <- field %in% names(old)
    new_present <- field %in% names(new)
    old_value <- if (old_present) old[[field]] else NULL
    new_value <- if (new_present) new[[field]] else NULL
    if (old_present && new_present && identical(old_value, new_value)) {
      next
    }
    change <- if (!old_present) {
      "added"
    } else if (!new_present) {
      "removed"
    } else {
      "changed"
    }
    decision <- classify(field, change, old_value, new_value)
    rows[[length(rows) + 1L]] <- new_schema_change_detail(
      path = paste0(path, "/", json_pointer_escape(field)),
      object_type = object_type,
      change = change,
      field = field,
      old = old_value,
      new = new_value,
      classification = decision[[1L]],
      rule = decision[[2L]]
    )
  }
  bind_schema_change_details(rows)
}

diff_schema_tree <- function(
  old,
  new,
  path,
  object_type,
  added_classification,
  removed_classification,
  changed_classification,
  rule_prefix
) {
  if (identical(old, new)) {
    return(empty_schema_change_details())
  }
  if (is_named_schema_list(old) && is_named_schema_list(new)) {
    rows <- list()
    keys <- sort(union(names(old), names(new)))
    for (key in keys) {
      child_path <- paste0(path, "/", json_pointer_escape(key))
      old_present <- key %in% names(old)
      new_present <- key %in% names(new)
      if (!old_present) {
        rows[[length(rows) + 1L]] <- new_schema_change_detail(
          path = child_path,
          object_type = object_type,
          change = "added",
          new = new[[key]],
          classification = added_classification,
          rule = paste0(rule_prefix, "_added")
        )
      } else if (!new_present) {
        rows[[length(rows) + 1L]] <- new_schema_change_detail(
          path = child_path,
          object_type = object_type,
          change = "removed",
          old = old[[key]],
          classification = removed_classification,
          rule = paste0(rule_prefix, "_removed")
        )
      } else {
        rows[[length(rows) + 1L]] <- diff_schema_tree(
          old[[key]],
          new[[key]],
          path = child_path,
          object_type = object_type,
          added_classification = added_classification,
          removed_classification = removed_classification,
          changed_classification = changed_classification,
          rule_prefix = rule_prefix
        )
      }
    }
    return(bind_schema_change_details(rows))
  }
  if (is_scalar_schema_list(old) && is_scalar_schema_list(new)) {
    old_values <- vapply(old, schema_change_summary, character(1))
    new_values <- vapply(new, schema_change_summary, character(1))
    rows <- list()
    for (value in sort(setdiff(new_values, old_values))) {
      rows[[length(rows) + 1L]] <- new_schema_change_detail(
        path = paste0(path, "/", json_pointer_escape(value)),
        object_type = object_type,
        change = "added",
        new = jsonlite::fromJSON(value, simplifyVector = FALSE),
        classification = added_classification,
        rule = paste0(rule_prefix, "_value_added")
      )
    }
    for (value in sort(setdiff(old_values, new_values))) {
      rows[[length(rows) + 1L]] <- new_schema_change_detail(
        path = paste0(path, "/", json_pointer_escape(value)),
        object_type = object_type,
        change = "removed",
        old = jsonlite::fromJSON(value, simplifyVector = FALSE),
        classification = removed_classification,
        rule = paste0(rule_prefix, "_value_removed")
      )
    }
    return(bind_schema_change_details(rows))
  }
  new_schema_change_detail(
    path = path,
    object_type = object_type,
    change = "changed",
    field = basename(path),
    old = old,
    new = new,
    classification = changed_classification,
    rule = paste0(rule_prefix, "_change")
  )
}

is_named_schema_list <- function(value) {
  is.list(value) && !is.null(names(value)) && all(nzchar(names(value)))
}

is_scalar_schema_list <- function(value) {
  is.list(value) &&
    is.null(names(value)) &&
    all(vapply(
      value,
      \(.x) is.null(.x) || (!is.list(.x) && length(.x) <= 1L),
      logical(1)
    ))
}

schema_named_list <- function(values, field) {
  if (length(values) == 0L) {
    return(list())
  }
  keys <- vapply(
    values,
    \(.x) scalar_character(.x[[field]]),
    character(1)
  )
  names(values) <- keys
  values[order(keys)]
}

schema_column_map <- function(columns) {
  if (length(columns) == 0L) {
    return(list())
  }
  keys <- vapply(
    columns,
    function(column) {
      slot <- scalar_character(column$slot, "")
      if (nzchar(slot)) slot else scalar_character(column$name)
    },
    character(1)
  )
  names(columns) <- keys
  columns[order(keys)]
}

validation_map <- function(invariants) {
  if (length(invariants) == 0L) {
    return(list())
  }
  keys <- vapply(
    invariants,
    function(invariant) {
      paste(
        scalar_character(invariant$name),
        scalar_character(invariant$class, ""),
        scalar_character(invariant$applies_to_role, ""),
        sep = "|"
      )
    },
    character(1)
  )
  names(invariants) <- keys
  invariants[order(keys)]
}

json_pointer_escape <- function(value) {
  value <- gsub("~", "~0", as.character(value), fixed = TRUE)
  gsub("/", "~1", value, fixed = TRUE)
}

diff_named_contract <- function(old, new) {
  old_names <- names(old)
  new_names <- names(new)
  common <- intersect(old_names, new_names)
  changed <- common[
    !vapply(
      common,
      \(.x) identical(old[[.x]], new[[.x]]),
      logical(1)
    )
  ]
  list(
    added = sort(setdiff(new_names, old_names)),
    removed = sort(setdiff(old_names, new_names)),
    changed = sort(changed)
  )
}

diff_class_slots <- function(old_classes, new_classes) {
  common_classes <- intersect(names(old_classes), names(new_classes))
  rows <- lapply(common_classes, function(class) {
    old_slots <- old_classes[[class]]$slots
    new_slots <- new_classes[[class]]$slots
    old_names <- names(old_slots)
    new_names <- names(new_slots)
    common_slots <- intersect(old_names, new_names)
    changed <- common_slots[
      !vapply(
        common_slots,
        \(.x) identical(old_slots[[.x]], new_slots[[.x]]),
        logical(1)
      )
    ]
    data.frame(
      class = rep(
        class,
        length(setdiff(new_names, old_names)) +
          length(setdiff(old_names, new_names)) +
          length(changed)
      ),
      slot = c(
        sort(setdiff(new_names, old_names)),
        sort(setdiff(old_names, new_names)),
        sort(changed)
      ),
      change = c(
        rep("added", length(setdiff(new_names, old_names))),
        rep("removed", length(setdiff(old_names, new_names))),
        rep("changed", length(changed))
      ),
      row.names = NULL
    )
  })
  rows <- Filter(\(.x) nrow(.x) > 0L, rows)
  if (length(rows) == 0L) {
    return(empty_class_slot_diff())
  }
  result <- do.call(rbind, rows)
  result[order(result$class, result$slot, result$change), , drop = FALSE]
}

relation_map <- function(relations) {
  if (length(relations) == 0L) {
    return(list())
  }
  names(relations) <- vapply(
    relations,
    \(.x) scalar_character(.x$name),
    character(1)
  )
  relations
}

diff_relations <- function(old, new) {
  diff_named_contract(relation_map(old), relation_map(new))
}
