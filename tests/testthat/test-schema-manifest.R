test_that("compiled manifests load without Python", {
  withr::local_envvar(
    RETICULATE_PYTHON = "/path/that/does/not/exist/python"
  )

  schema <- graft_schema(tempest_manifest_path())

  expect_identical(S7::S7_inherits(schema, GraftSchema), TRUE)
  expect_identical(schema@name, "tempest-artifacts")
  expect_length(schema@classes, 10L)
  expect_identical(schema@manifest$manifest_version, "2.0.0")
  expect_identical(schema@manifest$projection_mapping_version, "1")
  expect_null(schema@manifest$tables)
})

test_that("schema properties expose semantic contracts", {
  schema <- graft_schema(tempest_manifest_path())
  claim <- schema@classes$Claim
  semantic_claim <- schema@classes$SemanticClaim
  about <- claim@slots$about
  manifest <- schema@manifest
  support_values <- manifest$enums$EvidenceSupportType$permissible_values
  support_names <- vapply(
    support_values,
    \(value) scalar_character(value$value),
    character(1)
  )

  expect_identical(claim@statement_shape, "narrative")
  expect_identical(semantic_claim@statement_shape, "semantic")
  expect_identical(about@required, TRUE)
  expect_identical(about@duckdb_type, "VARCHAR")
  expect_in("supports", support_names)
  expect_identical(
    schema@classes$Source@slots$uri@external_identifier,
    "canonical_url"
  )
  expect_identical(
    manifest$identifier_normalization_versions$canonical_url,
    "1"
  )
  expect_identical(
    manifest$relations[[1L]],
    list(
      kind = "object",
      name = "Claim.about",
      ordered = FALSE,
      owner_class = "Claim",
      owner_view = "claim",
      predicate = "https://w3id.org/graft/about",
      slot = "about",
      view = "claim__about"
    )
  )
})

test_that("manifest integrity validates projection contracts", {
  schema <- as_graft_schema_internal(graft_schema(tempest_manifest_path()))

  expect_invisible(validate_manifest_integrity(schema))

  tampered <- unserialize(serialize(schema, NULL))
  tampered$manifest$relations[[1L]]$view <- "wrong_projection"
  tampered <- refresh_schema_structural_digest(tampered)
  condition <- rlang::catch_cnd(validate_manifest_integrity(tampered))

  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "generated_relation_contract")
})

test_that("manifest integrity rejects scalar slot name mismatches", {
  schema <- as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  tampered <- unserialize(serialize(schema, NULL))
  tampered$manifest$classes$Entity$slots$description$name <- "renamed"
  tampered <- refresh_schema_structural_digest(tampered)

  condition <- rlang::catch_cnd(validate_manifest_integrity(tampered))

  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "slot_name_contract")
  expect_identical(condition$record_class, "Entity")
  expect_identical(condition$slot, "description")
})

test_that("narrative claims do not require artificial predicates", {
  schema <- graft_schema(tempest_manifest_path())
  claim_slots <- names(schema@classes$Claim@slots)
  claim <- yaml::read_yaml(
    test_path("fixtures", "tempest-schema", "valid-narrative.yaml")
  )

  semantic_fields <- c(
    "predicate",
    "object_entity",
    "object_value",
    "object_datatype"
  )
  expect_disjoint(claim_slots, semantic_fields)
  expect_disjoint(names(claim), semantic_fields)
  expect_identical(
    schema@manifest$graph_projections$semantic_edges$exclude_narrative_statements,
    TRUE
  )
  expect_length(
    schema@manifest$graph_projections$semantic_edges$object_relations,
    0L
  )
})

test_that("semantic statements retain their exactly-one invariant", {
  schema <- graft_schema(tempest_manifest_path())
  invariants <- schema@manifest$validation_invariants
  invariant_names <- vapply(invariants, \(.x) .x$name, character(1))
  invariant <- invariants[[which(
    invariant_names == "exactly_one_semantic_object"
  )]]

  expect_identical(invariant$class, "SemanticClaim")
  expect_setequal(
    unlist(invariant$fields, use.names = FALSE),
    c("object_entity", "object_value")
  )
  expect_identical(invariant$cardinality, 1L)
  expect_identical(invariant$rule, "exactly_one_present")
})
