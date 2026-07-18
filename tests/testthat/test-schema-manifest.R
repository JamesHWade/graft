test_that("committed manifest loads without a usable Python path", {
  withr::local_envvar(
    RETICULATE_PYTHON = "/path/that/does/not/exist/python"
  )

  schema <- kg_schema(tempest_manifest_path())

  expect_s3_class(schema, "kg_schema")
  expect_identical(kg_schema_info(schema)$schema_name, "tempest-artifacts")
  expect_identical(kg_schema_info(schema)$class_count, 10L)
})

test_that("schema inspection exposes roles, slots, and enums", {
  schema <- kg_schema(tempest_manifest_path())

  classes <- kg_classes(schema)
  slots <- kg_slots(schema, "Claim")
  enums <- kg_enums(schema)

  expect_identical(
    classes$statement_shape[classes$class == "Claim"],
    "narrative"
  )
  expect_identical(
    classes$statement_shape[classes$class == "SemanticClaim"],
    "semantic"
  )
  expect_in("about", slots$slot)
  expect_identical(slots$required[slots$slot == "about"], TRUE)
  expect_in("supports", enums$value[enums$enum == "EvidenceSupportType"])
  expect_identical(
    schema$manifest$classes$Source$slots$uri$external_identifier,
    "canonical_url"
  )
  expect_identical(
    schema$manifest$identifier_normalization_versions$canonical_url,
    "1"
  )
})

test_that("narrative claims do not require artificial predicates", {
  schema <- kg_schema(tempest_manifest_path())
  claim_slots <- kg_slots(schema, "Claim")$slot
  claim <- yaml::read_yaml(
    test_path("fixtures", "tempest-schema", "valid-narrative.yaml")
  )

  expect_disjoint(
    claim_slots,
    c("predicate", "object_entity", "object_value", "object_datatype")
  )
  expect_disjoint(
    names(claim),
    c("predicate", "object_entity", "object_value", "object_datatype")
  )
  expect_identical(
    schema$manifest$graph_projections$semantic_edges$exclude_narrative_statements,
    TRUE
  )
  expect_length(
    schema$manifest$graph_projections$semantic_edges$object_relations,
    0L
  )
})

test_that("semantic statements represent an exactly-one object invariant", {
  schema <- kg_schema(tempest_manifest_path())
  invariants <- schema$manifest$validation_invariants
  names <- vapply(invariants, \(.x) .x$name, character(1))
  invariant <- invariants[[which(names == "exactly_one_semantic_object")]]

  expect_identical(invariant$class, "SemanticClaim")
  expect_setequal(
    unlist(invariant$fields, use.names = FALSE),
    c("object_entity", "object_value")
  )
  expect_identical(invariant$cardinality, 1L)
  expect_identical(invariant$rule, "exactly_one_present")
})

test_that("mixed narrative and invalid semantic fixtures violate invariants", {
  schema <- kg_schema(tempest_manifest_path())
  invariants <- schema$manifest$validation_invariants
  names <- vapply(invariants, \(.x) .x$name, character(1))
  narrative <- invariants[[which(names == "narrative_shape")]]
  semantic <- invariants[[which(names == "exactly_one_semantic_object")]]

  mixed <- yaml::read_yaml(
    invalid_schema_path("narrative-with-semantic-fields.yaml")
  )
  both <- yaml::read_yaml(
    invalid_schema_path("semantic-with-both-objects.yaml")
  )
  neither <- yaml::read_yaml(
    invalid_schema_path("semantic-without-object.yaml")
  )
  present <- function(record, fields) {
    sum(vapply(fields, \(.x) !is.null(record[[.x]]), logical(1)))
  }

  expect_gt(
    length(intersect(names(mixed), unlist(narrative$forbidden_fields))),
    0L
  )
  expect_identical(present(both, semantic$fields), 2L)
  expect_identical(present(neither, semantic$fields), 0L)
})

test_that("manifest failures use structured schema conditions", {
  expect_snapshot(
    error = TRUE,
    kg_slots(kg_schema(tempest_manifest_path()), "MissingClass")
  )
})
