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

test_that("the tracked manifest schema follows the live v2 contract", {
  definition <- jsonlite::fromJSON(
    graft_manifest_definition_path(),
    simplifyVector = FALSE
  )
  manifest <- graft_schema(tempest_manifest_path())@manifest

  expect_identical(
    definition[["$id"]],
    "https://w3id.org/graft/manifest/2.0.0"
  )
  expect_identical(definition$properties$manifest_version$const, "2.0.0")
  expect_identical(
    definition$properties$projection_mapping_version$const,
    graft_projection_mapping_version
  )
  expect_identical(
    "version" %in%
      unlist(
        definition$properties$schema$required,
        use.names = FALSE
      ),
    TRUE
  )
  expect_identical(
    definition$properties$schema$properties$source_files$minItems,
    1L
  )
  expect_setequal(
    unlist(definition$required, use.names = FALSE),
    names(manifest)
  )
  expect_identical(
    "relational_mapping_version" %in% names(definition$properties),
    FALSE
  )
  expect_identical(
    "tables" %in% unlist(definition$required, use.names = FALSE),
    FALSE
  )
  expect_identical(definition[["$defs"]]$class$properties$view$type, "string")
  expect_identical(
    definition[["$defs"]]$slot$properties$duckdb_type$type,
    "string"
  )
  expect_identical(
    definition$properties$dictionary[["$ref"]],
    "#/$defs/data_dict_dictionary"
  )
  expect_identical(
    definition$properties$compiler$properties$provider[["$ref"]],
    "#/$defs/data_dict_provider"
  )
  expect_setequal(
    unlist(
      definition[["$defs"]]$data_dict_provider$required,
      use.names = FALSE
    ),
    c("name", "export_format_version", "source_format")
  )
  expect_identical(
    definition[["$defs"]]$data_dict_provider$additionalProperties,
    FALSE
  )
  expect_identical(
    definition[[
      "$defs"
    ]]$data_dict_provider$properties$export_format_version$const,
    data_dict_export_format_version
  )
  expect_identical(
    definition[["$defs"]]$data_dict_dictionary$properties$adapter_version$const,
    data_dict_adapter_version
  )
  expect_identical(
    definition[["$defs"]]$data_dict_dictionary$properties$document$properties[[
      "$version"
    ]]$const,
    data_dict_export_format_version
  )
  expect_identical(
    definition$allOf[[1L]]$then$properties$compiler$properties$name$const,
    "graft-data-dict-adapter"
  )
  expect_identical(
    definition$allOf[[1L]]$then$properties$compiler$properties$version$const,
    data_dict_adapter_version
  )
  expect_identical(
    definition$allOf[[1L]]$then$properties$compiler$properties[[
      "script_digest"
    ]]$const,
    data_dict_adapter_script_digest()
  )
  expect_setequal(
    unlist(
      definition$allOf[[1L]]$then$properties$compiler$propertyNames$enum,
      use.names = FALSE
    ),
    c("name", "version", "script_digest", "provider")
  )
  expect_identical(
    definition$allOf[[
      1L
    ]]$then$properties$schema$properties$source_files$maxItems,
    1L
  )
  expect_identical(
    definition$allOf[[2L]]$then$required,
    list("dictionary")
  )
  expect_identical(
    definition$allOf[[3L]]$then$properties$compiler$properties$name$const,
    graft_linkml_compiler_name
  )
  expect_identical(
    definition$allOf[[3L]]$then$properties$compiler$properties$version$const,
    graft_linkml_compiler_version
  )
  expect_identical(
    definition$allOf[[3L]]$then$properties$compiler$properties[[
      "script_digest"
    ]]$const,
    graft_linkml_compiler_digest()
  )
  expect_identical(
    definition[["$defs"]]$data_dict_public_column$properties$examples,
    FALSE
  )
  expect_identical(
    definition[["$defs"]]$data_dict_public_column$properties$fields,
    FALSE
  )
})

test_that("manifest validation rejects duplicate JSON object keys", {
  manifest <- graft_schema(data_dict_personinfo_export_path())@manifest

  duplicated_root <- c(
    manifest,
    list(manifest_version = manifest$manifest_version)
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(duplicated_root, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "duplicate_json_key")
  expect_identical(condition$field, "$.manifest_version")

  condition <- rlang::catch_cnd(validate_manifest_integrity(
    new_compiled_schema(duplicated_root)
  ))
  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "duplicate_json_key")

  duplicated_nested <- manifest
  column <- duplicated_nested$dictionary$document$tables[[1L]]$columns[[1L]]
  duplicated_nested$dictionary$document$tables[[1L]]$columns[[1L]] <- c(
    column,
    list(type = column$type)
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(duplicated_nested, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "duplicate_json_key")
  expect_match(condition$field, "columns\\[1\\].type$")

  canonical <- canonical_manifest_json(manifest)
  duplicated_text <- sub(
    '"manifest_version":"2.0.0"',
    paste0(
      '"manifest_version":"2.0.0",',
      '"manifest_version":"2.0.0"'
    ),
    canonical,
    fixed = TRUE
  )
  path <- withr::local_tempfile(fileext = ".graft.json")
  writeLines(duplicated_text, path, useBytes = TRUE)
  condition <- rlang::catch_cnd(load_schema_manifest(path))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "duplicate_json_key")
})

test_that("manifest headers enforce required fields and supported versions", {
  manifest <- graft_schema(tempest_manifest_path())@manifest

  missing <- manifest
  missing$identifier_normalization_versions <- NULL
  condition <- rlang::catch_cnd(validate_manifest_header(missing, "fixture"))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(
    condition$missing_fields,
    "identifier_normalization_versions"
  )

  unsupported_manifest <- manifest
  unsupported_manifest$manifest_version <- "3.0.0"
  condition <- rlang::catch_cnd(
    validate_manifest_header(unsupported_manifest, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "supported_manifest_version")
  expect_identical(condition$observed_value, "3.0.0")
  expect_identical(condition$supported_value, graft_manifest_version)

  unsupported_projection <- manifest
  unsupported_projection$projection_mapping_version <- "2"
  condition <- rlang::catch_cnd(
    validate_manifest_header(unsupported_projection, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "supported_projection_mapping_version")
  expect_identical(condition$observed_value, "2")
  expect_identical(
    condition$supported_value,
    graft_projection_mapping_version
  )
})

test_that("manifest headers enforce generic container and provenance shapes", {
  manifest <- graft_schema(tempest_manifest_path())@manifest
  scalar_fields <- c(
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

  for (field in scalar_fields) {
    malformed <- manifest
    malformed[[field]] <- "not-a-container"
    condition <- rlang::catch_cnd(
      validate_manifest_header(malformed, "fixture")
    )
    expect_s3_class(condition, "graft_schema_error")
    expect_identical(condition$field, field)
  }

  malformed_value <- manifest
  malformed_value$classes[[1L]] <- "not-an-object"
  condition <- rlang::catch_cnd(
    validate_manifest_header(malformed_value, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_match(condition$field, "^classes[.]")

  named_sources <- manifest
  names(named_sources$schema$source_files) <- paste0(
    "source-",
    seq_along(named_sources$schema$source_files)
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(named_sources, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "schema_source_contract")

  compiler_variants <- list(
    list(),
    list(
      name = 1,
      version = "0.3.0",
      script_digest = manifest$compiler$script_digest
    ),
    c(manifest$compiler, private = "value"),
    within(manifest$compiler, script_digest <- "not-a-digest")
  )
  for (compiler in compiler_variants) {
    malformed <- manifest
    malformed$compiler <- compiler
    condition <- rlang::catch_cnd(
      validate_manifest_header(malformed, "fixture")
    )
    expect_s3_class(condition, "graft_schema_error")
    expect_identical(condition$rule, "compiler_contract")
  }

  null_dictionary <- manifest
  null_dictionary["dictionary"] <- list(NULL)
  condition <- rlang::catch_cnd(
    validate_manifest_header(null_dictionary, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_extension_contract")
})

test_that("generic manifest shapes cannot bypass in-memory integrity", {
  schema <- as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  schema$manifest$compiler <- list()
  schema$manifest$fingerprints$build_digest <- manifest_build_digest(
    schema$manifest
  )

  condition <- rlang::catch_cnd(new_graft_schema(schema))

  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "compiler_contract")
})

test_that("recursive manifest objects retain their exact contract", {
  manifest <- graft_schema(tempest_manifest_path())@manifest

  missing_class_field <- manifest
  missing_class_field$classes$Entity$role <- NULL
  condition <- rlang::catch_cnd(
    validate_manifest_header(missing_class_field, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_match(condition$field, "^classes[.]Entity")

  extra_class_field <- manifest
  extra_class_field$classes$Entity$private <- "value"
  condition <- rlang::catch_cnd(
    validate_manifest_header(extra_class_field, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_match(condition$field, "^classes[.]Entity")

  missing_slot_field <- manifest
  missing_slot_field$classes$Entity$slots$description$required <- NULL
  missing_slot_field$slots$description$required <- NULL
  condition <- rlang::catch_cnd(
    validate_manifest_header(missing_slot_field, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_match(condition$field, "slots[.]description$")

  extra_slot_field <- manifest
  extra_slot_field$classes$Entity$slots$description$private <- "value"
  extra_slot_field$slots$description$private <- "value"
  condition <- rlang::catch_cnd(
    validate_manifest_header(extra_slot_field, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_match(condition$field, "slots[.]description$")

  for (bound in list(list(secret = "abc"), as.list(c(1, 2)), "abc")) {
    malformed_bound <- manifest
    malformed_bound$classes$Entity$slots$description$minimum_value <- bound
    malformed_bound$slots$description$minimum_value <- bound
    condition <- rlang::catch_cnd(
      validate_manifest_header(malformed_bound, "fixture")
    )
    expect_s3_class(condition, "graft_schema_error")
    expect_match(condition$field, "[.]minimum_value$")
  }

  malformed_pattern <- manifest
  malformed_pattern$classes$Entity$slots$description$pattern <- "["
  malformed_pattern$slots$description$pattern <- "["
  condition <- rlang::catch_cnd(
    validate_manifest_header(malformed_pattern, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "slot_pattern_contract")

  malformed_datetime <- manifest
  malformed_datetime$classes$Entity$slots$created_at$datetime_format <-
    as.list(c("offset", "secret"))
  malformed_datetime$slots$created_at$datetime_format <-
    as.list(c("offset", "secret"))
  condition <- rlang::catch_cnd(
    validate_manifest_header(malformed_datetime, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_match(condition$field, "[.]datetime_format$")

  malformed_statement <- manifest
  malformed_statement$classes$Claim$statement_shape <- as.list(c(
    "narrative",
    "secret"
  ))
  condition <- rlang::catch_cnd(
    validate_manifest_header(malformed_statement, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_match(condition$field, "[.]statement_shape$")

  malformed_graph <- manifest
  malformed_graph$graph_projections$semantic_edges <- 1L
  condition <- rlang::catch_cnd(
    validate_manifest_header(malformed_graph, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "graph_projection_contract")

  malformed_invariants <- manifest
  malformed_invariants$validation_invariants <- list()
  condition <- rlang::catch_cnd(
    validate_manifest_header(malformed_invariants, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "validation_invariant_contract")

  malformed_normalization <- manifest
  malformed_normalization$identifier_normalization_versions <- list(
    secret = "1"
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(malformed_normalization, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "identifier_normalization_contract")
})

test_that("manifest identities and executable policies are valid and unique", {
  manifest <- graft_schema(tempest_manifest_path())@manifest
  cases <- list(
    blank_fixed_predicate = list(
      rule = "manifest_shape_contract",
      mutate = function(value) {
        value$classes$Entity$fixed_predicate <- " "
        value
      }
    ),
    deterministic_without_origin = list(
      rule = "class_identifier_contract",
      mutate = function(value) {
        value$classes$Run$origin_key_slots <- list()
        value
      }
    ),
    blank_type_uri = list(
      rule = "manifest_reference_contract",
      mutate = function(value) {
        value$classes$Entity$type_uri <- " "
        value
      }
    ),
    missing_type_uri = list(
      rule = "manifest_shape_contract",
      mutate = function(value) {
        value$classes$Entity$type_uri <- NULL
        value
      }
    ),
    malformed_type_uri = list(
      rule = "manifest_reference_contract",
      mutate = function(value) {
        value$classes$Entity$type_uri <- "not a uri"
        value
      }
    ),
    relative_type_uri = list(
      rule = "manifest_reference_contract",
      mutate = function(value) {
        value$classes$Entity$type_uri <- "relative/path"
        value
      }
    ),
    blank_slot_meaning = list(
      rule = "manifest_reference_contract",
      mutate = function(value) {
        value$classes$Entity$slots$description$meaning <- " "
        value
      }
    ),
    malformed_slot_meaning = list(
      rule = "manifest_reference_contract",
      mutate = function(value) {
        value$classes$Entity$slots$description$meaning <- "not a uri"
        value
      }
    ),
    relative_slot_meaning = list(
      rule = "manifest_reference_contract",
      mutate = function(value) {
        value$classes$Entity$slots$description$meaning <- "relative"
        value
      }
    ),
    malformed_fixed_predicate = list(
      rule = "manifest_reference_contract",
      mutate = function(value) {
        value$classes$Entity$fixed_predicate <- "not a uri"
        value
      }
    ),
    relative_fixed_predicate = list(
      rule = "manifest_reference_contract",
      mutate = function(value) {
        value$classes$Entity$fixed_predicate <- "relative"
        value
      }
    ),
    blank_class_view = list(
      rule = "manifest_shape_contract",
      mutate = function(value) {
        value$classes$Entity$view <- " "
        value
      }
    ),
    blank_view_column = list(
      rule = "manifest_shape_contract",
      mutate = function(value) {
        value$classes$Entity$slots$description$view_column <- " "
        value
      }
    ),
    blank_relation_predicate = list(
      rule = "manifest_shape_contract",
      mutate = function(value) {
        value$relations[[1L]]$predicate <- " "
        value
      }
    ),
    malformed_relation_predicate = list(
      rule = "manifest_reference_contract",
      mutate = function(value) {
        value$relations[[1L]]$predicate <- "not a uri"
        value
      }
    ),
    relative_relation_predicate = list(
      rule = "manifest_reference_contract",
      mutate = function(value) {
        value$relations[[1L]]$predicate <- "relative"
        value
      }
    ),
    blank_schema_name = list(
      rule = "schema_source_contract",
      mutate = function(value) {
        value$schema$name <- " "
        value
      }
    ),
    relative_schema_id = list(
      rule = "schema_source_contract",
      mutate = function(value) {
        value$schema$id <- "relative/path"
        value$schema$source_files[[1L]]$schema_id <- "relative/path"
        value
      }
    ),
    relative_source_schema_id = list(
      rule = "schema_source_contract",
      mutate = function(value) {
        value$schema$source_files[[2L]]$schema_id <- "relative/path"
        value
      }
    ),
    duplicate_source_identity = list(
      rule = "schema_source_contract",
      mutate = function(value) {
        duplicate <- value$schema$source_files[[1L]]
        duplicate$root <- FALSE
        duplicate$content_digest <- paste0("sha256:", strrep("0", 64L))
        value$schema$source_files[[length(value$schema$source_files) + 1L]] <-
          duplicate
        value
      }
    ),
    duplicate_source_schema_id = list(
      rule = "schema_source_contract",
      mutate = function(value) {
        duplicate <- value$schema$source_files[[2L]]
        duplicate$schema_id <- value$schema$source_files[[1L]]$schema_id
        duplicate$name <- paste0(duplicate$name, "-alias")
        duplicate$content_digest <- paste0("sha256:", strrep("1", 64L))
        value$schema$source_files[[length(value$schema$source_files) + 1L]] <-
          duplicate
        value
      }
    ),
    duplicate_source_name = list(
      rule = "schema_source_contract",
      mutate = function(value) {
        duplicate <- value$schema$source_files[[2L]]
        duplicate$schema_id <- "urn:graft:test:duplicate-source"
        duplicate$name <- value$schema$source_files[[1L]]$name
        duplicate$content_digest <- paste0("sha256:", strrep("2", 64L))
        value$schema$source_files[[length(value$schema$source_files) + 1L]] <-
          duplicate
        value
      }
    )
  )

  for (case_name in names(cases)) {
    case <- cases[[case_name]]
    condition <- rlang::catch_cnd(
      validate_manifest_header(case$mutate(manifest), "fixture")
    )
    expect_s3_class(condition, "graft_schema_error")
    expect_identical(condition$rule, case$rule, info = case_name)
  }
})

test_that("manifest slots retain coherent semantic contracts", {
  manifest <- graft_schema(tempest_manifest_path())@manifest
  cases <- list(
    empty_range = list(
      rule = "manifest_shape_contract",
      mutate = function(value) {
        value$classes$Entity$slots$description$range <- ""
        value$slots$description$range <- ""
        value
      }
    ),
    unknown_scalar_range = list(
      rule = "slot_range_contract",
      mutate = function(value) {
        value$classes$Entity$slots$description$range <- "strnig"
        value$slots$description$range <- "strnig"
        value
      }
    ),
    character_bound = list(
      rule = "slot_bound_contract",
      mutate = function(value) {
        value$classes$Entity$slots$description$minimum_value <- 1
        value$slots$description$minimum_value <- 1
        value
      }
    ),
    reversed_bound = list(
      rule = "core_slot_contract",
      mutate = function(value) {
        value$classes$Claim$slots$confidence$minimum_value <- 2
        value$classes$Claim$slots$confidence$maximum_value <- 1
        value$slots$confidence$minimum_value <- 2
        value$slots$confidence$maximum_value <- 1
        value
      }
    ),
    missing_identifier = list(
      rule = "core_slot_contract",
      mutate = function(value) {
        value$classes$Entity$slots$id$identifier <- FALSE
        value
      }
    ),
    multiple_identifiers = list(
      rule = "class_identifier_contract",
      mutate = function(value) {
        value$classes$Entity$slots$description$identifier <- TRUE
        value
      }
    ),
    optional_identifier = list(
      rule = "core_slot_contract",
      mutate = function(value) {
        value$classes$Entity$slots$id$required <- FALSE
        value
      }
    ),
    weakened_core_reference = list(
      rule = "core_slot_contract",
      mutate = function(value) {
        value$classes$SemanticClaim$slots$subject$range <- "string"
        value$classes$SemanticClaim$slots$subject$required <- FALSE
        value$classes$SemanticClaim$slots$subject$object_reference <- FALSE
        value
      }
    ),
    weakened_core_enum = list(
      rule = "core_slot_contract",
      mutate = function(value) {
        value$classes$Claim$slots$status$range <- "string"
        value$classes$Claim$slots$status$enum <- NULL
        value
      }
    ),
    widened_core_bound = list(
      rule = "core_slot_contract",
      mutate = function(value) {
        value$classes$Claim$slots$confidence$minimum_value <- -1
        value
      }
    ),
    ordered_core_relation = list(
      rule = "core_slot_contract",
      mutate = function(value) {
        value$classes$Claim$slots$about$ordered <- TRUE
        value
      }
    ),
    sensitive_core_identifier = list(
      rule = "core_slot_contract",
      mutate = function(value) {
        value$classes$Entity$slots$id$sensitive <- TRUE
        value
      }
    ),
    multivalued_external_identifier = list(
      rule = "external_identifier_contract",
      mutate = function(value) {
        value$classes$Claim$slots$about$external_identifier <- "custom"
        value
      }
    ),
    unknown_object_range = list(
      rule = "core_slot_contract",
      mutate = function(value) {
        value$classes$Claim$slots$about$range <- "UnknownClass"
        value$slots$about$range <- "UnknownClass"
        value
      }
    ),
    unknown_enum = list(
      rule = "slot_enum_contract",
      mutate = function(value) {
        value$classes$Claim$slots$claim_type$range <- "UnknownEnum"
        value$classes$Claim$slots$claim_type$enum <- "UnknownEnum"
        value$slots$claim_type$range <- "UnknownEnum"
        value$slots$claim_type$enum <- "UnknownEnum"
        value
      }
    ),
    missing_global_slot = list(
      rule = "class_global_slot_contract",
      mutate = function(value) {
        value$slots$description <- NULL
        value
      }
    ),
    mismatched_global_identity = list(
      rule = "class_global_slot_contract",
      mutate = function(value) {
        value$classes$Entity$slots$description$name <- "renamed"
        value
      }
    ),
    missing_label_slot = list(
      rule = "class_annotation_contract",
      mutate = function(value) {
        value$classes$Entity$label_slot <- "missing"
        value
      }
    ),
    sensitive_search_slot = list(
      rule = "class_annotation_contract",
      mutate = function(value) {
        value$classes$Entity$slots$description$sensitive <- TRUE
        value
      }
    ),
    missing_origin_slot = list(
      rule = "manifest_shape_contract",
      mutate = function(value) {
        value$classes$Claim$origin_key_slots <- c("missing")
        value
      }
    ),
    unrelated_ancestor = list(
      rule = "class_hierarchy_contract",
      mutate = function(value) {
        value$classes$Entity$ancestors <- c(
          value$classes$Entity$ancestors,
          "Source"
        )
        value
      }
    ),
    forged_role = list(
      rule = "class_role_contract",
      mutate = function(value) {
        value$classes$Entity$role <- "statement"
        value$classes$Entity$statement_shape <- "narrative"
        value
      }
    ),
    undeclared_ancestor_bridge = list(
      rule = "class_hierarchy_contract",
      mutate = function(value) {
        value$classes$Entity$is_a <- "UndeclaredAbstract"
        value$classes$Entity$ancestors <- as.list(c(
          "Entity",
          "UndeclaredAbstract",
          "Source"
        ))
        value
      }
    ),
    decimal_bound = list(
      rule = "slot_bound_contract",
      mutate = function(value) {
        value$classes$SemanticClaim$slots$temperature$range <- "decimal"
        value$classes$SemanticClaim$slots$temperature$duckdb_type <- "DECIMAL"
        value$classes$SemanticClaim$slots$temperature$minimum_value <- 0.1
        value$slots$temperature$range <- "decimal"
        value$slots$temperature$duckdb_type <- "DECIMAL"
        value$slots$temperature$minimum_value <- 0.1
        value
      }
    ),
    unsafe_bigint_bound = list(
      rule = "slot_bound_contract",
      mutate = function(value) {
        value$classes$SemanticClaim$slots$temperature$range <- "integer"
        value$classes$SemanticClaim$slots$temperature$duckdb_type <- "BIGINT"
        value$classes$SemanticClaim$slots$temperature$maximum_value <-
          9007199254740992
        value$slots$temperature$range <- "integer"
        value$slots$temperature$duckdb_type <- "BIGINT"
        value$slots$temperature$maximum_value <- 9007199254740992
        value
      }
    ),
    renamed_enum = list(
      rule = "enum_identity_contract",
      mutate = function(value) {
        value$enums$ClaimType$name <- "Impostor"
        value
      }
    ),
    duplicate_enum_value = list(
      rule = "enum_value_contract",
      mutate = function(value) {
        value$enums$ClaimType$permissible_values[[2L]]$value <-
          value$enums$ClaimType$permissible_values[[1L]]$value
        value
      }
    )
  )

  for (case_name in names(cases)) {
    case <- cases[[case_name]]
    condition <- rlang::catch_cnd(
      validate_manifest_header(case$mutate(manifest), "fixture")
    )

    expect_s3_class(condition, "graft_schema_error")
    expect_identical(condition$rule, case$rule, info = case_name)
  }

  dictionary_manifest <- graft_schema(
    data_dict_personinfo_export_path()
  )@manifest
  dictionary_manifest$classes$person$slots$full_name$required <- FALSE
  condition <- rlang::catch_cnd(
    validate_manifest_header(dictionary_manifest, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "class_global_slot_contract")
})

test_that("public manifest loading classifies invalid scalar ranges", {
  manifest <- graft_schema(tempest_manifest_path())@manifest
  manifest$classes$Entity$slots$description$range <- "strnig"
  manifest$slots$description$range <- "strnig"
  manifest$fingerprints$structural_digest <- manifest_structural_digest(
    manifest
  )
  manifest$fingerprints$build_digest <- manifest_build_digest(manifest)
  path <- withr::local_tempfile(fileext = ".graft.json")
  writeLines(canonical_json(manifest), path, useBytes = TRUE)

  condition <- rlang::catch_cnd(graft_schema(path))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "slot_range_contract")
  expect_identical(condition$field, "classes.Entity.slots.description.range")
})

test_that("LinkML provenance is pinned and internally reproducible", {
  manifest <- graft_schema(tempest_manifest_path())@manifest
  expect_identical(
    graft_linkml_source_digest(manifest$schema$source_files),
    manifest$fingerprints$source_digest
  )

  bogus_compiler <- manifest
  bogus_compiler$compiler$name <- "bogus-compiler"
  condition <- rlang::catch_cnd(
    validate_manifest_header(bogus_compiler, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "compiler_contract")

  false_compiler_digest <- manifest
  false_compiler_digest$compiler$script_digest <- paste0(
    "sha256:",
    strrep("0", 64L)
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(false_compiler_digest, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "compiler_contract")

  no_sources <- manifest
  no_sources$schema$source_files <- list()
  condition <- rlang::catch_cnd(
    validate_manifest_header(no_sources, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "schema_source_contract")

  no_root <- manifest
  no_root$schema$source_files <- lapply(
    no_root$schema$source_files,
    \(source_file) within(source_file, root <- FALSE)
  )
  condition <- rlang::catch_cnd(validate_manifest_header(no_root, "fixture"))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "schema_source_contract")

  mismatched_root <- manifest
  root <- which(vapply(
    mismatched_root$schema$source_files,
    \(source_file) source_file$root,
    logical(1)
  ))[[1L]]
  mismatched_root$schema$source_files[[root]]$name <- "impostor"
  condition <- rlang::catch_cnd(
    validate_manifest_header(mismatched_root, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "schema_source_contract")

  false_source_digest <- manifest
  false_source_digest$fingerprints$source_digest <- paste0(
    "sha256:",
    strrep("0", 64L)
  )
  false_source_digest$fingerprints$build_digest <- manifest_build_digest(
    false_source_digest
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(false_source_digest, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "source_digest_content_mismatch")
})

test_that("build digests cover provider and dictionary metadata", {
  schema <- as_graft_schema_internal(
    graft_schema(data_dict_personinfo_export_path())
  )
  schema$manifest$compiler$provider$revision <- "tampered-revision"

  condition <- rlang::catch_cnd(validate_manifest_integrity(schema))

  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "build_digest_content_mismatch")
})

test_that("data-dict source digests are reproducible from public contracts", {
  manifest <- graft_schema(data_dict_personinfo_export_path())@manifest
  manifest$fingerprints$source_digest <- paste0(
    "sha256:",
    strrep("0", 64L)
  )
  manifest$fingerprints$build_digest <- manifest_build_digest(manifest)

  condition <- rlang::catch_cnd(
    validate_manifest_header(manifest, "fixture")
  )

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "source_digest_content_mismatch")
})

test_that("data-dict manifest extensions enforce their nested contract", {
  manifest <- graft_schema(data_dict_personinfo_export_path())@manifest
  expect_invisible(validate_manifest_header(manifest, "fixture"))

  missing <- manifest
  missing$dictionary$profile <- NULL
  condition <- rlang::catch_cnd(validate_manifest_header(missing, "fixture"))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_extension_contract")
  expect_identical(condition$missing_fields, "profile")

  leaked <- manifest
  leaked$compiler$provider$source_path <- "/private/source"
  leaked$dictionary$provider <- leaked$compiler$provider
  condition <- rlang::catch_cnd(validate_manifest_header(leaked, "fixture"))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_provider_contract")

  leaked_compiler <- manifest
  leaked_compiler$compiler$source_path <- "/private/compiler"
  leaked_compiler$fingerprints$build_digest <- manifest_build_digest(
    leaked_compiler
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(leaked_compiler, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_compiler_contract")

  false_compiler_digest <- manifest
  false_compiler_digest$compiler$script_digest <- paste0(
    "sha256:",
    strrep("0", 64L)
  )
  false_compiler_digest$fingerprints$build_digest <- manifest_build_digest(
    false_compiler_digest
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(false_compiler_digest, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_compiler_contract")

  extra_mapping <- manifest
  extra_mapping$dictionary$mapped$private_count <- 1L
  extra_mapping$fingerprints$build_digest <- manifest_build_digest(
    extra_mapping
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(extra_mapping, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_extension_contract")

  wrong_mapping <- manifest
  wrong_mapping$dictionary$mapped$columns_to_slots <- 999L
  wrong_mapping$fingerprints$build_digest <- manifest_build_digest(
    wrong_mapping
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(wrong_mapping, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_projection_contract")

  atomic_schema <- manifest
  atomic_schema$schema <- 1
  atomic_schema$fingerprints$build_digest <- manifest_build_digest(
    atomic_schema
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(atomic_schema, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "schema_source_contract")

  atomic_source_file <- manifest
  atomic_source_file$schema$source_files <- list(1)
  atomic_source_file$fingerprints$build_digest <- manifest_build_digest(
    atomic_source_file
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(atomic_source_file, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "schema_source_contract")

  false_invariants <- manifest
  false_invariants$validation_invariants <- list(list(secret = "observed"))
  false_invariants$fingerprints$structural_digest <-
    manifest_structural_digest(false_invariants)
  false_invariants$fingerprints$build_digest <- manifest_build_digest(
    false_invariants
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(false_invariants, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_projection_contract")

  false_normalization <- manifest
  false_normalization$identifier_normalization_versions <- list(
    secret = "observed"
  )
  false_normalization$fingerprints$structural_digest <-
    manifest_structural_digest(false_normalization)
  false_normalization$fingerprints$build_digest <- manifest_build_digest(
    false_normalization
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(false_normalization, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "identifier_normalization_contract")

  extra_root <- manifest
  extra_root$private_origin <- "/private/source"
  extra_root$fingerprints$build_digest <- manifest_build_digest(extra_root)
  condition <- rlang::catch_cnd(
    validate_manifest_header(extra_root, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "manifest_fields")

  extra_fingerprint <- manifest
  extra_fingerprint$fingerprints$private <- "observed"
  extra_fingerprint$fingerprints$build_digest <- manifest_build_digest(
    extra_fingerprint
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(extra_fingerprint, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "manifest_fingerprints")

  mismatched_source <- manifest
  mismatched_source$schema$id <- "urn:data-dict:impostor"
  mismatched_source$schema$name <- "impostor"
  mismatched_source$schema$version <- "999"
  mismatched_source$schema$source_files[[1L]]$schema_id <-
    "urn:data-dict:impostor"
  mismatched_source$schema$source_files[[1L]]$name <- "impostor"
  mismatched_source$schema$source_files[[1L]]$version <- "999"
  for (class_name in names(mismatched_source$classes)) {
    mismatched_source$classes[[class_name]]$type_uri <- paste0(
      "urn:data-dict:impostor#",
      utils::URLencode(class_name, reserved = TRUE)
    )
  }
  mismatched_source$fingerprints$structural_digest <-
    manifest_structural_digest(mismatched_source)
  mismatched_source$fingerprints$build_digest <- manifest_build_digest(
    mismatched_source
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(mismatched_source, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_projection_contract")

  leaked_source_file <- manifest
  leaked_source_file$schema$source_files[[1L]]$path <- "/private/source"
  leaked_source_file$fingerprints$build_digest <- manifest_build_digest(
    leaked_source_file
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(leaked_source_file, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "schema_source_contract")

  malformed_document <- manifest
  malformed_document$dictionary$document$tables[[1L]]$columns <- list()
  malformed_source <- data_dict_manifest_source(
    malformed_document$dictionary$document,
    malformed_document$schema$source_files[[1L]]$content_digest
  )
  malformed_document$fingerprints$source_digest <-
    data_dict_manifest_source_digest(
      malformed_document$dictionary$document,
      malformed_source
    )
  malformed_document$fingerprints$build_digest <- manifest_build_digest(
    malformed_document
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(malformed_document, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_projection_contract")

  null_fields <- manifest
  null_fields$dictionary$document$tables[[1L]]$columns[[1L]]["fields"] <-
    list(NULL)
  null_source <- data_dict_manifest_source(
    null_fields$dictionary$document,
    null_fields$schema$source_files[[1L]]$content_digest
  )
  null_fields$fingerprints$source_digest <- data_dict_manifest_source_digest(
    null_fields$dictionary$document,
    null_source
  )
  null_fields$fingerprints$build_digest <- manifest_build_digest(null_fields)
  path <- withr::local_tempfile(fileext = ".graft.json")
  writeLines(canonical_json(null_fields), path, useBytes = TRUE)
  condition <- rlang::catch_cnd(graft_schema(path))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_projection_contract")

  mismatched <- manifest
  mismatched$dictionary$provider$revision <- "different"
  condition <- rlang::catch_cnd(
    validate_manifest_header(mismatched, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_provider_contract")

  stripped <- manifest
  stripped$dictionary <- NULL
  stripped$compiler$provider <- NULL
  stripped$fingerprints$build_digest <- manifest_build_digest(stripped)
  condition <- rlang::catch_cnd(
    validate_manifest_header(stripped, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_provider_contract")

  unsupported_export <- manifest
  unsupported_export$compiler$provider$export_format_version <- "99.0.0"
  unsupported_export$dictionary$provider <- unsupported_export$compiler$provider
  unsupported_export$fingerprints$build_digest <- manifest_build_digest(
    unsupported_export
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(unsupported_export, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(
    condition$rule,
    "supported_data_dict_export_format_version"
  )
  expect_identical(condition$observed_value, "99.0.0")
  expect_identical(
    condition$supported_value,
    data_dict_export_format_version
  )

  mismatched_document <- manifest
  mismatched_document$dictionary$document[["$version"]] <- "99.0.0"
  mismatched_document$fingerprints$build_digest <- manifest_build_digest(
    mismatched_document
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(mismatched_document, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_export_format_version")
  expect_identical(condition$observed_value, "99.0.0")
  expect_identical(
    condition$expected_value,
    data_dict_export_format_version
  )

  mismatched_compiler <- manifest
  mismatched_compiler$compiler$name <- "bogus-adapter"
  mismatched_compiler$fingerprints$build_digest <- manifest_build_digest(
    mismatched_compiler
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(mismatched_compiler, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_compiler_contract")
  expect_identical(condition$observed_name, "bogus-adapter")

  mismatched_compiler <- manifest
  mismatched_compiler$compiler$version <- "99.0.0"
  mismatched_compiler$fingerprints$build_digest <- manifest_build_digest(
    mismatched_compiler
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(mismatched_compiler, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "dictionary_compiler_contract")
  expect_identical(condition$observed_version, "99.0.0")

  unsupported_adapter <- manifest
  unsupported_adapter$dictionary$adapter_version <- "99.0.0"
  unsupported_adapter$compiler$version <- "99.0.0"
  unsupported_adapter$fingerprints$build_digest <- manifest_build_digest(
    unsupported_adapter
  )
  condition <- rlang::catch_cnd(
    validate_manifest_header(unsupported_adapter, "fixture")
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "supported_data_dict_adapter_version")
  expect_identical(condition$observed_value, "99.0.0")
  expect_identical(condition$supported_value, data_dict_adapter_version)
})

test_that("loaded data-dict manifests enforce their public redaction boundary", {
  manifest <- graft_schema(data_dict_personinfo_export_path())@manifest
  mutations <- list(
    dataset_origin = function(document) {
      document$origin <- "/private/dataset"
      document
    },
    table_origin = function(document) {
      document$tables[[1L]]$origin <- "/private/table"
      document
    },
    table_source = function(document) {
      document$tables[[1L]]$source <- list(parquet = "/private/data.parquet")
      document
    },
    rows = function(document) {
      document$tables[[1L]]$rows <- list(list(secret = "observed"))
      document
    },
    examples = function(document) {
      document$tables[[1L]]$columns[[1L]]$examples <- "observed"
      document
    },
    range = function(document) {
      document$tables[[1L]]$columns[[1L]]$range <- list(min = 1, max = 2)
      document
    },
    profile = function(document) {
      document$tables[[1L]]$columns[[1L]]$profile <- list(count = 1)
      document
    },
    nested_profile = function(document) {
      document$tables[[1L]]$columns[[1L]]$fields <- list(list(
        name = "nested",
        profile = list(count = 1)
      ))
      document
    },
    nested_examples = function(document) {
      document$tables[[1L]]$columns[[1L]]$fields <- list(list(
        name = "nested",
        type = "string",
        examples = "observed",
        range = list(min = 1)
      ))
      document
    }
  )

  for (mutation in mutations) {
    tampered <- manifest
    tampered$dictionary$document <- mutation(
      tampered$dictionary$document
    )
    tampered$fingerprints$build_digest <- manifest_build_digest(tampered)

    condition <- rlang::catch_cnd(
      validate_manifest_header(tampered, "fixture")
    )

    expect_s3_class(condition, "graft_schema_error")
    expect_identical(condition$rule, "dictionary_public_document_contract")
  }
})

test_that("loaded data-dict manifests reject unsafe numeric lexemes", {
  manifest <- graft_schema(data_dict_personinfo_export_path())@manifest
  manifest$dictionary$document$custom_numeric <- 9007199254740991
  manifest$fingerprints$build_digest <- manifest_build_digest(manifest)
  canonical <- canonical_manifest_json(manifest)
  tampered <- sub(
    '"custom_numeric":9007199254740991',
    '"custom_numeric":9007199254740991.1',
    canonical,
    fixed = TRUE
  )
  expect_identical(tampered == canonical, FALSE)
  path <- tempfile(fileext = ".graft.json")
  withr::defer(unlink(path))
  writeLines(tampered, path, useBytes = TRUE)

  condition <- rlang::catch_cnd(load_schema_manifest(path))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "unsafe_json_number")
})

test_that("loaded LinkML manifests reject unsafe numeric lexemes", {
  manifest <- graft_schema(tempest_manifest_path())@manifest
  manifest$classes$Entity$slots$description$minimum_value <-
    9007199254740991
  manifest$slots$description$minimum_value <- 9007199254740991
  manifest$fingerprints$structural_digest <-
    manifest_structural_digest(manifest)
  manifest$fingerprints$build_digest <- manifest_build_digest(manifest)
  canonical <- canonical_manifest_json(manifest)
  tampered <- sub(
    "9007199254740991",
    "9223372036854775807",
    canonical,
    fixed = TRUE
  )
  expect_identical(tampered == canonical, FALSE)
  path <- tempfile(fileext = ".graft.json")
  withr::defer(unlink(path))
  writeLines(tampered, path, useBytes = TRUE)

  condition <- rlang::catch_cnd(load_schema_manifest(path))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "unsafe_json_number")
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

test_that("manifest integrity rejects local and global slot mismatches", {
  schema <- as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  tampered <- unserialize(serialize(schema, NULL))
  tampered$manifest$classes$Entity$slots$description$name <- "renamed"
  tampered <- refresh_schema_structural_digest(tampered)

  condition <- rlang::catch_cnd(validate_manifest_integrity(tampered))

  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "class_global_slot_contract")
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
