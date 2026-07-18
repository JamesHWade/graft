test_that("schema diff reports compatible manifests", {
  schema <- kg_schema(tempest_manifest_path())

  diff <- kg_schema_diff(schema, schema)

  expect_s3_class(diff, "kg_schema_diff")
  expect_identical(diff$compatible, TRUE)
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
  expect_in("NewClass", diff$classes$added)
  expect_in("Entity", diff$classes$changed)
  expect_equal(
    subset(diff$slots, class == "Entity" & slot == "new_field")$change,
    "added"
  )
})
