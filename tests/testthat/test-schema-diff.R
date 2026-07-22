test_that("schema diff reports compatible manifests", {
  schema <- kg_schema(tempest_manifest_path())

  diff <- kg_schema_diff(schema, schema)

  expect_s3_class(diff, "kg_schema_diff")
  expect_identical(diff$compatible, TRUE)
  expect_identical(diff$classification, "compatible")
  expect_identical(nrow(diff$details), 0L)
  expect_length(diff$classes$added, 0L)
  expect_length(diff$classes$removed, 0L)
  expect_length(diff$classes$changed, 0L)
  expect_identical(nrow(diff$slots), 0L)
})

test_that("schema diff identifies concrete structural changes", {
  old <- kg_schema(tempest_manifest_path())
  new <- unserialize(serialize(old, NULL))
  new$manifest$fingerprints$structural_digest <- paste0(
    "sha256:",
    paste(rep("0", 64L), collapse = "")
  )
  new$manifest$classes$Entity$slots$new_field <- list(
    name = "new_field",
    range = "string",
    relational_type = "VARCHAR",
    required = FALSE,
    multivalued = FALSE,
    identifier = FALSE,
    object_reference = FALSE
  )
  new$manifest$classes$NewClass <- new$manifest$classes$Activity
  new$manifest$classes$NewClass$name <- "NewClass"
  new$manifest$classes$NewClass$table <- "new_class"

  diff <- kg_schema_diff(old, new)

  expect_identical(diff$compatible, FALSE)
  expect_identical(diff$classification, "additive")
  expect_in("NewClass", diff$classes$added)
  expect_in("Entity", diff$classes$changed)
  expect_equal(
    subset(diff$slots, class == "Entity" & slot == "new_field")$change,
    "added"
  )
})

test_that("schema diff ignores source and build changes when structure matches", {
  old <- kg_schema(tempest_manifest_path())
  new <- unserialize(serialize(old, NULL))
  new$manifest$fingerprints$source_digest <- "sha256:new-source"
  new$manifest$fingerprints$build_digest <- "sha256:new-build"
  new$manifest$compiler$version <- "99.0.0"

  diff <- kg_schema_diff(old, new)

  expect_identical(diff$compatible, TRUE)
  expect_identical(diff$classification, "compatible")
  expect_identical(nrow(diff$details), 0L)
  expect_length(diff$classes$changed, 0L)
  expect_identical(nrow(diff$slots), 0L)
})

test_that("schema diff classifies safe additions deterministically", {
  old <- kg_schema(tempest_manifest_path())
  new <- unserialize(serialize(old, NULL))
  new$manifest$fingerprints$structural_digest <- "sha256:additive"
  new$manifest$classes$Entity$slots$new_field <- list(
    name = "new_field",
    column = "new_field",
    range = "string",
    relational_type = "VARCHAR",
    required = FALSE,
    multivalued = FALSE,
    ordered = FALSE,
    identifier = FALSE,
    object_reference = FALSE,
    enum = NULL,
    foreign_key = NULL,
    external_identifier = NULL,
    sensitive = FALSE
  )
  new$manifest$tables$Entity$columns <- c(
    new$manifest$tables$Entity$columns,
    list(list(
      name = "new_field",
      slot = "new_field",
      type = "VARCHAR",
      nullable = TRUE,
      primary_key = FALSE,
      foreign_key = NULL
    ))
  )
  new$manifest$classes$NewClass <- new$manifest$classes$Activity
  new$manifest$classes$NewClass$name <- "NewClass"
  new$manifest$classes$NewClass$table <- "new_class"
  new$manifest$tables$NewClass <- new$manifest$tables$Activity
  new$manifest$tables$NewClass$class <- "NewClass"
  new$manifest$tables$NewClass$name <- "new_class"
  new$manifest$graph_projections$node_classes <- c(
    new$manifest$graph_projections$node_classes,
    "NewClass"
  )
  new$manifest$enums$Importance$permissible_values <- c(
    new$manifest$enums$Importance$permissible_values,
    list(list(value = "urgent", meaning = NULL, description = NULL))
  )

  reordered <- unserialize(serialize(new, NULL))
  reordered$manifest$classes <- reordered$manifest$classes[
    rev(names(reordered$manifest$classes))
  ]
  reordered$manifest$tables <- reordered$manifest$tables[
    rev(names(reordered$manifest$tables))
  ]
  first <- kg_schema_diff(old, new)
  second <- kg_schema_diff(old, reordered)

  expect_identical(first$classification, "additive")
  expect_setequal(unique(first$details$classification), "additive")
  expect_identical(first$details, second$details)
  expect_identical(first$details$path, sort(first$details$path))
  expect_named(
    first$details,
    c(
      "path",
      "object_type",
      "change",
      "field",
      "old_summary",
      "new_summary",
      "classification",
      "rule"
    )
  )
  expect_in("optional_slot_added", first$details$rule)
  expect_in("nullable_column_added", first$details$rule)
  expect_in("enum_value_added", first$details$rule)
})

test_that("schema diff classifies removals as destructive", {
  old <- kg_schema(tempest_manifest_path())
  new <- unserialize(serialize(old, NULL))
  new$manifest$fingerprints$structural_digest <- "sha256:destructive"
  new$manifest$classes$Entity$slots$description <- NULL
  keep <- vapply(
    new$manifest$tables$Entity$columns,
    \(.x) !identical(.x$slot, "description"),
    logical(1)
  )
  new$manifest$tables$Entity$columns <-
    new$manifest$tables$Entity$columns[keep]

  diff <- kg_schema_diff(old, new)

  expect_identical(diff$classification, "destructive")
  expect_equal(
    subset(diff$details, rule == "slot_removed")$classification,
    "destructive"
  )
  expect_equal(
    subset(diff$details, rule == "column_removed")$classification,
    "destructive"
  )
})

test_that("schema diff distinguishes review from unsupported changes", {
  old <- kg_schema(tempest_manifest_path())
  reviewed <- unserialize(serialize(old, NULL))
  reviewed$manifest$fingerprints$structural_digest <- "sha256:reviewed"
  reviewed$manifest$classes$Entity$slots$description$sensitive <- TRUE
  reviewed$manifest$relations[[1L]]$predicate <- "https://example.org/changed"

  review_diff <- kg_schema_diff(old, reviewed)

  expect_identical(review_diff$classification, "review_required")
  expect_equal(
    subset(review_diff$details, rule == "slot_sensitive_change")$classification,
    "review_required"
  )
  expect_equal(
    subset(
      review_diff$details,
      rule == "relation_predicate_change"
    )$classification,
    "review_required"
  )

  unsupported <- unserialize(serialize(old, NULL))
  unsupported$manifest$fingerprints$structural_digest <- "sha256:unsupported"
  unsupported$manifest$classes$Entity$id_policy <- "require"
  unsupported$manifest$classes$Entity$table <- "renamed_entity"
  unsupported$manifest$classes$Entity$slots$description$relational_type <-
    "DOUBLE"
  unsupported$manifest$classes$Entity$slots$description$required <- TRUE
  unsupported$manifest$classes$Entity$slots$description$multivalued <- TRUE
  unsupported$manifest$classes$Claim$slots$about$ordered <- TRUE
  unsupported$manifest$tables$Entity$name <- "renamed_entity"
  unsupported$manifest$relations[[1L]]$ordered <- TRUE
  namespace <- names(
    unsupported$manifest$identifier_normalization_versions
  )[[1L]]
  unsupported$manifest$identifier_normalization_versions[[namespace]] <- "2"

  unsupported_diff <- kg_schema_diff(old, unsupported)

  expect_identical(unsupported_diff$classification, "unsupported")
  expected_rules <- c(
    "class_id_policy_change",
    "class_table_change",
    "slot_relational_type_change",
    "slot_required_change",
    "slot_multivalued_change",
    "slot_ordered_change",
    "table_name_change",
    "relation_ordered_change",
    "identifier_normalization_version_change"
  )
  expect_setequal(
    intersect(unsupported_diff$details$rule, expected_rules),
    expected_rules
  )
  expect_setequal(
    unique(
      subset(
        unsupported_diff$details,
        rule %in% expected_rules
      )$classification
    ),
    "unsupported"
  )
})
