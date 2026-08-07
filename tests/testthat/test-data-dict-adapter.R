test_that("resolved data-dict exports compile to canonical Graft manifests", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "people",
    description = "A resolved test dictionary.",
    tables = list(
      list(
        name = "Organization",
        columns = list(
          list(
            name = "id",
            type = "string",
            constraints = c("primary_key", "unique", "required"),
            referenced_by = list(
              list(table = "Person", column = "organization_id")
            )
          ),
          list(name = "name", type = "string", constraints = "required"),
          list(
            name = "sector",
            type = "enum",
            values = list("public", "private")
          ),
          list(name = "aliases", type = "list(string)"),
          list(name = "internal_note", type = "string", display = "restricted")
        )
      ),
      list(
        name = "Person",
        columns = list(
          list(
            name = "id",
            type = "string",
            constraints = c("primary_key", "unique", "required")
          ),
          list(name = "name", type = "string", constraints = "required"),
          list(
            name = "organization_id",
            type = "string",
            constraints = "foreign_key",
            references = list(table = "Organization", column = "id")
          ),
          list(
            name = "score",
            type = "number(quantity)",
            range = list(min = 0, max = 1)
          ),
          list(name = "active", type = "boolean")
        )
      )
    ),
    relationships = list(
      list(
        cardinality = "many-to-one",
        pairs = list(
          list(
            left = list(table = "Person", column = "organization_id"),
            right = list(table = "Organization", column = "id")
          )
        )
      )
    )
  )
  source <- data_dict_test_source(dictionary)
  provider <- list(
    name = "data-dict",
    export_format_version = "0.1.0",
    revision = "d794c961",
    source_path = "/private/source/data-dict.yaml"
  )

  schema <- compile_data_dict_manifest(dictionary, source, provider)
  manifest <- schema$manifest

  expect_identical(is_compiled_schema(schema), TRUE)
  expect_null(schema$path)
  expect_invisible(validate_manifest_integrity(schema))
  expect_identical(manifest$manifest_version, "2.0.0")
  expect_identical(manifest$projection_mapping_version, "1")
  expect_null(manifest$dictionary$document$origin)
  expect_null(
    manifest$dictionary$document$tables[[2L]]$columns[[4L]]$range
  )
  expect_identical(manifest$dictionary$profile, "graft-table-v1")
  expect_identical(manifest$dictionary$defaults$role, "node")
  expect_named(
    manifest$dictionary$not_enforced,
    c(
      "class_inheritance",
      "ontology_uris",
      "graft_role",
      "identity_policy",
      "identifier_value_semantics",
      "requiredness_semantics",
      "global_identifier_uniqueness",
      "external_identifier_normalization",
      "search_policy",
      "unique_constraints",
      "representative_ranges",
      "assertions",
      "relationship_cardinality",
      "relationship_joins",
      "graph_relationship_projection",
      "profiles",
      "table_sources",
      "datetime_time_zone",
      "measure_semantics",
      "number_id_semantics",
      "type_validation_semantics",
      "enum_value_semantics",
      "origin_keys",
      "qualifier_slots",
      "polymorphic_references",
      "statement_shape_invariants"
    )
  )
  expect_match(
    manifest$dictionary$not_enforced$datetime_time_zone$handling,
    "Omitted zones require offset-bearing RFC 3339 input",
    fixed = TRUE
  )
  expect_identical(
    manifest$compiler$provider,
    c(
      provider[setdiff(names(provider), "source_path")],
      source_format = "resolved_json"
    )
  )
  expect_identical(
    manifest$compiler$script_digest,
    data_dict_adapter_script_digest()
  )
  expect_identical(
    any(grepl("/private/source", canonical_json(manifest), fixed = TRUE)),
    FALSE
  )
  expect_identical(manifest$classes$Organization$role, "node")
  expect_identical(manifest$classes$Organization$id_policy, "require")
  expect_identical(manifest$classes$Organization$label_slot, "name")
  expect_setequal(
    manifest$classes$Organization$search_slots,
    c("name", "sector")
  )
  expect_identical(
    manifest$classes$Organization$slots$internal_note$sensitive,
    TRUE
  )
  expect_identical(manifest$classes$Person$slots$id$range, "string")
  expect_identical(manifest$classes$Person$slots$id$duckdb_type, "VARCHAR")
  expect_identical(
    manifest$classes$Person$slots$organization_id$object_reference,
    TRUE
  )
  expect_identical(
    manifest$classes$Person$slots$organization_id$range,
    "Organization"
  )
  expect_null(manifest$classes$Person$slots$score$minimum_value)
  expect_null(manifest$classes$Person$slots$score$maximum_value)
  expect_identical(
    manifest$enums$Organization.sector.enum$permissible_values[[1L]]$value,
    "public"
  )
  expect_identical(
    manifest$relations[[1L]]$name,
    "Organization.aliases"
  )
  expect_identical(
    manifest$relations[[1L]]$view,
    "organization__aliases"
  )
  expect_identical(
    unlist(manifest$graph_projections$node_classes, use.names = FALSE),
    c("Organization", "Person")
  )

  repeated <- compile_data_dict_manifest(dictionary, source, provider)
  expect_identical(repeated$manifest, manifest)

  revised <- dictionary
  revised$description <- "Changed dictionary prose."
  revised_schema <- compile_data_dict_manifest(
    revised,
    data_dict_test_source(revised),
    provider
  )
  expect_identical(
    revised_schema$manifest$fingerprints$structural_digest,
    manifest$fingerprints$structural_digest
  )
  expect_identical(
    identical(
      revised_schema$manifest$fingerprints$source_digest,
      manifest$fingerprints$source_digest
    ),
    FALSE
  )
  expect_identical(
    identical(
      revised_schema$manifest$fingerprints$build_digest,
      manifest$fingerprints$build_digest
    ),
    FALSE
  )

  structural <- dictionary
  structural$tables[[2L]]$columns[[2L]]$constraints <- NULL
  structural_schema <- compile_data_dict_manifest(
    structural,
    data_dict_test_source(structural),
    provider
  )
  expect_identical(
    identical(
      structural_schema$manifest$fingerprints$structural_digest,
      manifest$fingerprints$structural_digest
    ),
    FALSE
  )
})

test_that("data-dict source identity is derived from the dictionary", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "source identity/2026",
    version = list(number = "2.4.0"),
    tables = list(list(
      name = "Thing",
      columns = list(list(
        name = "id",
        type = "string",
        constraints = "primary_key"
      ))
    ))
  )
  source <- data_dict_test_source(dictionary)
  provider <- list(
    name = "data-dict",
    export_format_version = "0.1.0"
  )

  expect_identical(
    source,
    list(
      id = "urn:data-dict:source%20identity%2F2026",
      name = "source identity/2026",
      version = "2.4.0",
      content_digest = graft_sha256(canonical_json(dictionary))
    )
  )
  expect_identical(
    is_compiled_schema(
      compile_data_dict_manifest(dictionary, source, provider)
    ),
    TRUE
  )

  mismatched <- source
  mismatched$name <- "another dictionary"
  condition <- rlang::catch_cnd(compile_data_dict_manifest(
    dictionary,
    mismatched,
    provider
  ))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "source_identity")
  expect_identical(condition$field, "source")
  expect_identical(condition$expected_value, source)
  expect_identical(condition$observed_value, mismatched)
})

test_that("data-dict versions retain the upstream lexical contract", {
  expect_identical(data_dict_document_version(list(number = "1.2.3")), "1.2.3")
  expect_identical(
    data_dict_document_version(list(number = "1.2.3-rc.1+build.5")),
    "1.2.3-rc.1+build.5"
  )
  expect_identical(
    data_dict_document_version(list(date = "2024-02-29")),
    "2024-02-29"
  )
  expect_identical(data_dict_document_version(list(hash = "opaque")), "opaque")

  invalid <- list(
    list(number = "2.4"),
    list(number = "release"),
    list(number = "1.2.3-"),
    list(date = "tomorrow"),
    list(date = "2024-02-30"),
    list(date = "2024-2-9")
  )
  for (version in invalid) {
    condition <- rlang::catch_cnd(data_dict_document_version(version))
    expect_s3_class(condition, "graft_schema_error")
    expect_identical(condition$rule, "data_version")
  }
})

test_that("compiled data-dict manifests can be written and loaded", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "thing",
    tables = list(
      list(
        name = "Thing",
        columns = list(
          list(
            name = "id",
            type = "string",
            constraints = "primary_key"
          ),
          list(name = "label", type = "string")
        )
      )
    )
  )
  output <- tempfile(fileext = ".graft.json")
  on.exit(unlink(output), add = TRUE)

  in_memory <- compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  )
  schema <- compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0"),
    output = output
  )

  expect_identical(file.exists(output), TRUE)
  expect_identical(schema$path, normalizePath(output, winslash = "/"))
  expect_invisible(validate_manifest_integrity(schema))
  expect_identical(schema$manifest$dictionary$document, dictionary)
  expect_identical(schema$manifest, in_memory$manifest)

  written <- jsonlite::fromJSON(output, simplifyVector = FALSE)
  expect_type(written$classes$Thing$search_slots, "list")
  expect_type(written$classes$Thing$relations, "list")
  expect_type(written$graph_projections$node_classes, "list")
  expect_identical(names(written$enums), character())
})

test_that("data-dict output path failures retain structured diagnostics", {
  output <- file.path(
    tempfile("missing-data-dict-output-"),
    "schema.graft.json"
  )

  condition <- rlang::catch_cnd(data_dict_output_path(output))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "output_directory")
  expect_identical(condition$field, "output")
  expect_identical(condition$observed_value, output)
})

test_that("descriptive data-dict constraints do not become acceptance rules", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "thing",
    tables = list(
      list(
        name = "Thing",
        columns = list(
          list(
            name = "id",
            type = "string",
            constraints = c("primary_key", "unique", "required")
          ),
          list(name = "code", type = "string", constraints = "unique"),
          list(name = "score", type = "number", range = list(min = 0, max = 1)),
          list(name = "valid_from", type = "datetime", time_zone = "UTC"),
          list(name = "valid_to", type = "datetime", time_zone = "UTC"),
          list(name = "superseded_by", type = "string")
        )
      )
    )
  )
  compiled <- compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  )
  schema <- new_graft_schema(compiled)
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))

  plan <- graft_plan(
    store,
    list(
      Thing = data.frame(
        id = c("thing:one", "thing:two"),
        code = c("same", "same"),
        score = c(-10, 10),
        valid_from = c(
          "2026-02-01T00:00:00",
          "2026-02-01T00:00:00"
        ),
        valid_to = c(
          "2026-01-01T00:00:00",
          "2026-01-01T00:00:00"
        ),
        superseded_by = c("thing:one", "thing:two")
      )
    ),
    graft_provenance(
      producer = "data-dict-adapter-test",
      idempotency_key = "descriptive-constraints"
    )
  )

  expect_identical(plan@valid, TRUE)
  expect_equal(nrow(plan@issues), 0L)
})

test_that("Graft ids remain globally unique across data-dict tables", {
  table <- function(name) {
    list(
      name = name,
      columns = list(list(
        name = "id",
        type = "string",
        constraints = "primary_key"
      ))
    )
  }
  dictionary <- list(
    "$version" = "0.1.0",
    name = "global-id",
    tables = list(table("First"), table("Second"))
  )
  schema <- new_graft_schema(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  ))
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))

  plan <- graft_plan(
    store,
    list(
      First = data.frame(id = "shared"),
      Second = data.frame(id = "shared")
    ),
    graft_provenance(
      producer = "data-dict-adapter-test",
      idempotency_key = "global-id"
    )
  )

  expect_identical(plan@valid, FALSE)
  expect_in("unique_batch_id", plan@issues$rule)
})

test_that("required data-dict lists use Graft's stricter missing-value rules", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "required-list",
    tables = list(list(
      name = "Thing",
      columns = list(
        list(name = "id", type = "string", constraints = "primary_key"),
        list(name = "tags", type = "list(string)", constraints = "required")
      )
    ))
  )
  schema <- new_graft_schema(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  ))
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))
  provenance <- graft_provenance(
    producer = "data-dict-adapter-test",
    idempotency_key = "required-list"
  )

  empty <- graft_plan(
    store,
    list(
      Thing = data.frame(
        id = "thing:empty",
        tags = I(list(character()))
      )
    ),
    provenance
  )
  missing_element <- graft_plan(
    store,
    list(
      Thing = data.frame(
        id = "thing:missing-element",
        tags = I(list(c("known", NA_character_)))
      )
    ),
    provenance
  )

  expect_identical(empty@valid, FALSE)
  expect_in("required", empty@issues$rule)
  expect_identical(missing_element@valid, FALSE)
  expect_in("non_missing_collection_values", missing_element@issues$rule)
})

test_that("unsupported data-dict shapes report their exact fields", {
  dictionary_with_type <- function(type) {
    list(
      "$version" = "0.1.0",
      name = "thing",
      tables = list(
        list(
          name = "Thing",
          columns = list(
            list(
              name = "id",
              type = "string",
              constraints = "primary_key"
            ),
            list(name = "payload", type = type)
          )
        )
      )
    )
  }
  compile <- function(dictionary) {
    compile_data_dict_manifest(
      dictionary,
      source = data_dict_test_source(dictionary),
      provider = list(name = "data-dict", export_format_version = "0.1.0")
    )
  }

  struct <- rlang::catch_cnd(compile(dictionary_with_type("struct")))
  expect_s3_class(struct, "graft_schema_error")
  expect_identical(struct$rule, "unsupported_struct")
  expect_identical(struct$field, "tables[1].columns[2].type")

  nested <- rlang::catch_cnd(
    compile(dictionary_with_type("list(list(string))"))
  )
  expect_s3_class(nested, "graft_schema_error")
  expect_identical(nested$rule, "unsupported_nested_list")
  expect_identical(nested$field, "tables[1].columns[2].type")

  for (empty_value in c("", "   ")) {
    empty_enum <- dictionary_with_type("enum")
    empty_enum$tables[[1L]]$columns[[2L]]$values <- c(empty_value, "known")
    condition <- rlang::catch_cnd(compile(empty_enum))
    expect_s3_class(condition, "graft_schema_error")
    expect_identical(condition$rule, "enum_values")
  }
  nested_enum <- dictionary_with_type("enum")
  nested_enum$tables[[1L]]$columns[[2L]]$values <- list(c("a", "b"))
  condition <- rlang::catch_cnd(compile(nested_enum))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "enum_values")

  utc <- dictionary_with_type("datetime")
  utc$tables[[1L]]$columns[[2L]]$time_zone <- "UTC"
  expect_identical(is_compiled_schema(compile(utc)), TRUE)

  named_zone <- dictionary_with_type("datetime")
  named_zone$tables[[1L]]$columns[[2L]]$time_zone <- "America/Detroit"
  condition <- rlang::catch_cnd(compile(named_zone))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "datetime_time_zone")
  expect_identical(condition$observed_value, "America/Detroit")

  naive <- dictionary_with_type("datetime")
  naive$tables[[1L]]$columns[[2L]]$time_zone <- "naive"
  condition <- rlang::catch_cnd(compile(naive))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "datetime_time_zone")
  expect_identical(condition$observed_value, "naive")
})

test_that("export-data profiles are rejected before contract compilation", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "thing",
    tables = list(list(
      name = "Thing",
      columns = list(
        list(name = "id", type = "string", constraints = "primary_key"),
        list(
          name = "secret",
          type = "string",
          display = "restricted",
          profile = list(sample_values = "SENSITIVE_CANARY")
        )
      )
    ))
  )
  compile <- function(document) {
    compile_data_dict_manifest(
      document,
      source = data_dict_test_source(document),
      provider = list(name = "data-dict", export_format_version = "0.1.0")
    )
  }

  condition <- rlang::catch_cnd(compile(dictionary))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "export_spec_only")
  expect_identical(condition$field, "tables[1].columns[2].profile")
  expect_identical(
    grepl("SENSITIVE_CANARY", conditionMessage(condition), fixed = TRUE),
    FALSE
  )

  rows <- dictionary
  rows$tables[[1L]]$columns[[2L]]$profile <- NULL
  rows$tables[[1L]]$rows <- 10L
  condition <- rlang::catch_cnd(compile(rows))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$field, "tables[1].rows")

  nested <- dictionary
  nested$tables[[1L]]$columns[[2L]] <- list(
    name = "payload",
    type = "struct",
    fields = list(list(
      name = "secret",
      type = "string",
      profile = list(sample_values = "SENSITIVE_CANARY")
    ))
  )
  condition <- rlang::catch_cnd(compile(nested))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(
    condition$field,
    "tables[1].columns[2].fields[1].profile"
  )
})

test_that("data-dict export and provider versions are pinned", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "thing",
    tables = list(list(
      name = "Thing",
      columns = list(list(
        name = "id",
        type = "string",
        constraints = "primary_key"
      ))
    ))
  )
  compile <- function(document, export_format_version = "0.1.0") {
    compile_data_dict_manifest(
      document,
      source = data_dict_test_source(document),
      provider = list(
        name = "data-dict",
        export_format_version = export_format_version
      )
    )
  }

  unsupported <- dictionary
  unsupported[["$version"]] <- "0.2.0"
  condition <- rlang::catch_cnd(compile(unsupported, "0.2.0"))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "export_format_version")
  expect_identical(condition$observed_value, "0.2.0")
  expect_identical(condition$supported_value, "0.1.0")

  condition <- rlang::catch_cnd(compile(dictionary, "0.0.9"))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "provider_export_format_version")
  expect_identical(condition$observed_value, "0.0.9")
  expect_identical(condition$expected_value, "0.1.0")
})

test_that("data-dict provider metadata is explicit and sanitized", {
  dictionary <- list("$version" = "0.1.0")
  provider <- list(
    name = "data-dict",
    export_format_version = "0.1.0",
    source_path = "/private/data-dict.yaml",
    source_format = "resolved_json"
  )

  sanitized <- data_dict_provider_metadata(provider, dictionary)

  expect_identical("source_path" %in% names(sanitized), FALSE)
  expect_identical(sanitized$source_format, "resolved_json")

  typo <- provider
  typo$revizion <- "intended-revision"
  condition <- rlang::catch_cnd(
    data_dict_provider_metadata(typo, dictionary)
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "provider_metadata")
  expect_identical(condition$unexpected_fields, "revizion")

  inconsistent <- provider
  inconsistent$cli_version <- "0.0.1"
  condition <- rlang::catch_cnd(
    data_dict_provider_metadata(inconsistent, dictionary)
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "provider_source_format")
})

test_that("ambiguous contract keys are rejected before serialization", {
  table <- function(name, column) {
    list(
      name = name,
      columns = list(
        list(name = "id", type = "string", constraints = "primary_key"),
        list(name = column, type = "string")
      )
    )
  }
  dictionary <- list(
    "$version" = "0.1.0",
    name = "keys",
    tables = list(table("a.b", "c"), table("a", "b.c"))
  )

  condition <- rlang::catch_cnd(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  ))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "ambiguous_contract_keys")
  expect_identical(condition$observed_value, "a.b.c")
})

test_that("foreign keys must match the profile's string identity type", {
  id <- list(name = "id", type = "string", constraints = "primary_key")
  dictionary <- list(
    "$version" = "0.1.0",
    name = "foreign-key",
    tables = list(
      list(name = "Target", columns = list(id)),
      list(
        name = "Source",
        columns = list(
          id,
          list(
            name = "target_id",
            type = "number(id)",
            constraints = "foreign_key",
            references = list(table = "Target", column = "id")
          )
        )
      )
    )
  )

  condition <- rlang::catch_cnd(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  ))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "foreign_key_type")
  expect_identical(condition$field, "tables[2].columns[2].type")
})

test_that("resolved references require the foreign-key constraint", {
  id <- list(name = "id", type = "string", constraints = "primary_key")
  dictionary <- list(
    "$version" = "0.1.0",
    name = "foreign-key",
    tables = list(
      list(name = "Target", columns = list(id)),
      list(
        name = "Source",
        columns = list(
          id,
          list(
            name = "target_id",
            type = "string",
            references = list(table = "Target", column = "id")
          )
        )
      )
    )
  )

  condition <- rlang::catch_cnd(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  ))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "resolved_foreign_key")
  expect_identical(condition$field, "tables[2].columns[2].references")
})

test_that("ambiguous data-dict identities are rejected", {
  dictionary_with_columns <- function(columns) {
    list(
      "$version" = "0.1.0",
      name = "thing",
      tables = list(list(name = "Thing", columns = columns))
    )
  }
  compile <- function(dictionary) {
    compile_data_dict_manifest(
      dictionary,
      source = data_dict_test_source(dictionary),
      provider = list(name = "data-dict", export_format_version = "0.1.0")
    )
  }

  missing <- rlang::catch_cnd(compile(dictionary_with_columns(list(
    list(name = "id", type = "string")
  ))))
  expect_s3_class(missing, "graft_schema_error")
  expect_identical(missing$rule, "unambiguous_identity")
  expect_identical(missing$field, "tables[1].columns")

  multiple <- rlang::catch_cnd(compile(dictionary_with_columns(list(
    list(name = "id", type = "string", constraints = "primary_key"),
    list(name = "other", type = "string", constraints = "primary_key")
  ))))
  expect_s3_class(multiple, "graft_schema_error")
  expect_identical(multiple$rule, "unambiguous_identity")

  renamed <- rlang::catch_cnd(compile(dictionary_with_columns(list(
    list(name = "thing_id", type = "string", constraints = "primary_key")
  ))))
  expect_s3_class(renamed, "graft_schema_error")
  expect_identical(renamed$rule, "primary_id")
  expect_identical(renamed$field, "tables[1].columns[1].name")

  numeric <- rlang::catch_cnd(compile(dictionary_with_columns(list(
    list(name = "id", type = "number(id)", constraints = "primary_key")
  ))))
  expect_s3_class(numeric, "graft_schema_error")
  expect_identical(numeric$rule, "primary_id_type")
  expect_identical(numeric$field, "tables[1].columns[1].type")

  restricted <- rlang::catch_cnd(compile(dictionary_with_columns(list(
    list(
      name = "id",
      type = "string",
      constraints = "primary_key",
      display = "restricted"
    )
  ))))
  expect_s3_class(restricted, "graft_schema_error")
  expect_identical(restricted$rule, "public_identifier")
  expect_identical(restricted$field, "tables[1].columns[1].display")
})

test_that("a data-dict primary id cannot also be a foreign key", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "primary-foreign",
    tables = list(
      list(
        name = "Parent",
        columns = list(list(
          name = "id",
          type = "string",
          constraints = "primary_key"
        ))
      ),
      list(
        name = "Child",
        columns = list(list(
          name = "id",
          type = "string",
          constraints = c("primary_key", "foreign_key"),
          references = list(table = "Parent", column = "id")
        ))
      )
    )
  )

  condition <- rlang::catch_cnd(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  ))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "primary_foreign_key")
  expect_identical(condition$field, "tables[2].columns[1].constraints")
})

test_that("nested data-dict column fields are rejected", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "nested-fields",
    tables = list(list(
      name = "Thing",
      columns = list(
        list(name = "id", type = "string", constraints = "primary_key"),
        list(
          name = "payload",
          type = "string",
          fields = list(list(
            name = "nested",
            type = "string",
            examples = "PRIVATE_NESTED_EXAMPLE",
            range = list(min = 1)
          ))
        )
      )
    ))
  )

  condition <- rlang::catch_cnd(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  ))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "unsupported_nested_fields")
  expect_identical(condition$field, "tables[1].columns[2].fields")
  sanitized <- data_dict_public_document(dictionary)
  expect_null(sanitized$tables[[1L]]$columns[[2L]]$fields[[1L]]$examples)
  expect_null(sanitized$tables[[1L]]$columns[[2L]]$fields[[1L]]$range)

  explicit_null <- dictionary
  explicit_null$tables[[1L]]$columns[[2L]]["fields"] <- list(NULL)
  condition <- rlang::catch_cnd(compile_data_dict_manifest(
    explicit_null,
    source = data_dict_test_source(explicit_null),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  ))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "unsupported_nested_fields")
})

test_that("data-dict structural collections must be arrays", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "array-shape",
    tables = list(list(
      name = "Thing",
      columns = list(list(
        name = "id",
        type = "string",
        constraints = "primary_key"
      ))
    ))
  )
  compile <- function(value) {
    compile_data_dict_manifest(
      value,
      source = data_dict_test_source(value),
      provider = list(name = "data-dict", export_format_version = "0.1.0")
    )
  }

  named_tables <- dictionary
  names(named_tables$tables) <- "Thing"
  condition <- rlang::catch_cnd(compile(named_tables))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "nonempty_tables")

  named_columns <- dictionary
  names(named_columns$tables[[1L]]$columns) <- "id"
  condition <- rlang::catch_cnd(compile(named_columns))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "nonempty_columns")
})

test_that("optional scalar data-dict foreign keys normalize blank values", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "blank-reference",
    tables = list(
      list(
        name = "Parent",
        columns = list(list(
          name = "id",
          type = "string",
          constraints = "primary_key"
        ))
      ),
      list(
        name = "Child",
        columns = list(
          list(name = "id", type = "string", constraints = "primary_key"),
          list(
            name = "parent_id",
            type = "string",
            constraints = "foreign_key",
            references = list(table = "Parent", column = "id")
          )
        )
      )
    )
  )
  schema <- new_graft_schema(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  ))
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))
  child_ids <- c("child:empty", "child:whitespace")

  plan <- graft_plan(
    store,
    list(
      Child = data.frame(
        id = child_ids,
        parent_id = c("", "   ")
      )
    ),
    graft_provenance("blank-reference", idempotency_key = "blank-reference")
  )

  expect_identical(plan@valid, TRUE)
  expect_identical(
    plan@records$Child$parent_id,
    c(NA_character_, NA_character_)
  )
  graft_commit(store, plan)
  retrieved <- lapply(
    child_ids,
    \(record_id) graft_get(store, record_id, include = character())
  )
  expect_identical(
    lapply(retrieved, \(record) record$record$parent_id),
    list(NULL, NULL)
  )
})

test_that("public manifests redact representative values and source locators", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "private-metadata",
    origin = "PRIVATE_ORIGIN_CANARY",
    tables = list(list(
      name = "Thing",
      origin = "PRIVATE_TABLE_ORIGIN_CANARY",
      source = list(parquet = "PRIVATE_SOURCE_CANARY"),
      columns = list(
        list(
          name = "id",
          type = "string",
          constraints = "primary_key",
          examples = "PRIVATE_ID_EXAMPLE"
        ),
        list(
          name = "secret",
          type = "string",
          display = "restricted",
          examples = "PRIVATE_RESTRICTED_EXAMPLE"
        ),
        list(
          name = "score",
          type = "number(quantity)",
          range = list(min = 1, max = 2)
        )
      )
    ))
  )
  compile <- function(document) {
    compile_data_dict_manifest(
      document,
      source = data_dict_test_source(document),
      provider = list(
        name = "data-dict",
        export_format_version = "0.1.0"
      )
    )
  }

  schema <- compile(dictionary)
  manifest_text <- canonical_json(schema$manifest)
  public <- schema$manifest$dictionary$document

  expect_identical(
    any(grepl("PRIVATE_", manifest_text, fixed = TRUE)),
    FALSE
  )
  expect_null(public$origin)
  expect_null(public$tables[[1L]]$origin)
  expect_null(public$tables[[1L]]$source)
  expect_null(public$tables[[1L]]$columns[[1L]]$examples)
  expect_null(public$tables[[1L]]$columns[[2L]]$examples)
  expect_null(public$tables[[1L]]$columns[[3L]]$range)
  expect_identical(
    public$tables[[1L]]$columns[[2L]]$display,
    "restricted"
  )
  expect_identical(
    schema$manifest$dictionary$not_enforced$representative_ranges$status,
    "redacted"
  )
  expect_identical(
    schema$manifest$dictionary$not_enforced$table_sources$status,
    "redacted"
  )

  changed <- dictionary
  changed$tables[[1L]]$columns[[2L]]$examples <- "DIFFERENT_PRIVATE_VALUE"
  changed_schema <- compile(changed)
  expect_identical(
    changed_schema$manifest$fingerprints$structural_digest,
    schema$manifest$fingerprints$structural_digest
  )
  expect_identical(
    identical(
      changed_schema$manifest$fingerprints$source_digest,
      schema$manifest$fingerprints$source_digest
    ),
    FALSE
  )
  expect_identical(
    identical(
      changed_schema$manifest$fingerprints$build_digest,
      schema$manifest$fingerprints$build_digest
    ),
    FALSE
  )
})

test_that("number id columns are rejected instead of rounded or retyped", {
  dictionary_with_type <- function(type) {
    list(
      "$version" = "0.1.0",
      name = "number-id",
      tables = list(list(
        name = "Thing",
        columns = list(
          list(name = "id", type = "string", constraints = "primary_key"),
          list(name = "code", type = type)
        )
      ))
    )
  }
  compile <- function(type) {
    dictionary <- dictionary_with_type(type)
    compile_data_dict_manifest(
      dictionary,
      source = data_dict_test_source(dictionary),
      provider = list(
        name = "data-dict",
        export_format_version = "0.1.0"
      )
    )
  }

  scalar <- rlang::catch_cnd(compile("number(id)"))
  expect_s3_class(scalar, "graft_schema_error")
  expect_identical(scalar$rule, "unsupported_number_id")
  expect_identical(scalar$field, "tables[1].columns[2].type")

  collection <- rlang::catch_cnd(compile("list(number(id))"))
  expect_s3_class(collection, "graft_schema_error")
  expect_identical(collection$rule, "unsupported_number_id")
  expect_identical(collection$field, "tables[1].columns[2].type")
})

test_that("data-dict datetime formats survive compilation and coercion", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "datetime",
    tables = list(list(
      name = "Event",
      columns = list(
        list(name = "id", type = "string", constraints = "primary_key"),
        list(name = "occurred_at", type = "datetime"),
        list(name = "reported_at", type = "datetime", time_zone = "UTC"),
        list(name = "checkpoints", type = "list(datetime)")
      )
    ))
  )
  schema <- new_graft_schema(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(
      name = "data-dict",
      export_format_version = "0.1.0"
    )
  ))
  expect_identical(
    schema@classes$Event@slots$occurred_at@datetime_format,
    "offset"
  )
  expect_identical(
    schema@classes$Event@slots$reported_at@datetime_format,
    "local_utc"
  )
  expect_identical(
    schema@manifest$slots[["Event.occurred_at"]]$datetime_format,
    "offset"
  )
  tampered <- as_graft_schema_internal(schema)
  tampered$manifest$classes$Event$slots$id$datetime_format <- "offset"
  tampered$manifest$slots[["Event.id"]]$datetime_format <- "offset"
  tampered <- refresh_schema_structural_digest(tampered)
  condition <- rlang::catch_cnd(validate_manifest_integrity(tampered))
  expect_s3_class(condition, "graft_schema_integrity_error")
  expect_identical(condition$rule, "datetime_format_contract")
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))
  provenance <- graft_provenance(
    "datetime-test",
    idempotency_key = "datetime-test"
  )

  valid <- graft_plan(
    store,
    list(
      Event = data.frame(
        id = "event:valid",
        occurred_at = "2024-01-01T00:00:00-05:00",
        reported_at = "2024-01-01T00:00:00",
        checkpoints = I(list(c(
          "2024-01-01T00:00:00Z",
          "2024-01-01T00:00:00-05:00"
        )))
      )
    ),
    provenance
  )
  expect_identical(valid@valid, TRUE)
  graft_commit(store, valid)
  record <- graft_get(store, "event:valid", include = character())$record
  expect_equal(as.numeric(record$occurred_at), 1704085200)
  expect_equal(as.numeric(record$reported_at), 1704067200)
  expect_equal(
    as.numeric(unlist(record$checkpoints, use.names = FALSE)),
    c(1704067200, 1704085200)
  )

  invalid <- graft_plan(
    store,
    list(
      Event = data.frame(
        id = "event:invalid",
        occurred_at = "2024-01-01T00:00:00",
        reported_at = "2024-01-01T00:00:00Z",
        checkpoints = I(list("2024-01-01T00:00:00.1234567Z"))
      )
    ),
    provenance
  )
  expect_identical(invalid@valid, FALSE)
  expect_equal(sum(invalid@issues$rule == "type_timestamp"), 3L)

  infinite <- graft_plan(
    store,
    list(
      Event = data.frame(
        id = c("event:infinite", "event:unformattable"),
        occurred_at = as.POSIXct(
          c(Inf, 1e20),
          origin = "1970-01-01",
          tz = "UTC"
        ),
        reported_at = as.POSIXct(
          c(Inf, 1e20),
          origin = "1970-01-01",
          tz = "UTC"
        )
      )
    ),
    provenance
  )
  expect_identical(infinite@valid, FALSE)
  expect_equal(sum(infinite@issues$rule == "type_timestamp"), 4L)

  microsecond <- as.POSIXct(0.123456, origin = "1970-01-01", tz = "UTC")
  expect_identical(coerce_timestamp(microsecond), microsecond)
  submicrosecond <- as.POSIXct(
    c(0.1234567, 0.1234564),
    origin = "1970-01-01",
    tz = "UTC"
  )
  expect_null(coerce_timestamp(submicrosecond))

  submicrosecond_plan <- graft_plan(
    store,
    list(
      Event = data.frame(
        id = paste0("event:submicrosecond-", 1:2),
        occurred_at = submicrosecond,
        reported_at = submicrosecond
      )
    ),
    graft_provenance(
      "datetime-test",
      idempotency_key = "datetime-submicrosecond"
    )
  )
  expect_identical(submicrosecond_plan@valid, FALSE)
  expect_equal(
    sum(submicrosecond_plan@issues$rule == "type_timestamp"),
    4L
  )
})

test_that("malformed data-dict dates produce an invalid plan", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "date",
    tables = list(list(
      name = "Event",
      columns = list(
        list(name = "id", type = "string", constraints = "primary_key"),
        list(name = "day", type = "date")
      )
    ))
  )
  schema <- new_graft_schema(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(name = "data-dict", export_format_version = "0.1.0")
  ))
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))

  plan <- graft_plan(
    store,
    list(
      Event = data.frame(
        id = paste0("event:invalid-", 1:4),
        day = c(
          "not-a-date",
          "2024-01-01junk",
          "2024-01-01 12:00",
          "2024/01/01"
        )
      )
    ),
    graft_provenance("date-test", idempotency_key = "date-test")
  )

  expect_identical(plan@valid, FALSE)
  expect_equal(sum(plan@issues$rule == "type_date"), 4L)

  infinite <- graft_plan(
    store,
    list(
      Event = data.frame(
        id = c("event:infinite", "event:unformattable"),
        day = structure(c(Inf, 1e20), class = "Date")
      )
    ),
    graft_provenance("date-test", idempotency_key = "date-infinite")
  )
  expect_identical(infinite@valid, FALSE)
  expect_equal(sum(infinite@issues$rule == "type_date"), 2L)

  fractional <- structure(0.5, class = "Date")
  expect_null(coerce_date(fractional))

  fractional_plan <- graft_plan(
    store,
    list(
      Event = data.frame(
        id = "event:fractional-date",
        day = fractional
      )
    ),
    graft_provenance("date-test", idempotency_key = "date-fractional")
  )
  expect_identical(fractional_plan@valid, FALSE)
  expect_identical(fractional_plan@issues$rule, "type_date")
})

test_that("data-dict doubles retain distinct exact values through the ledger", {
  dictionary <- list(
    "$version" = "0.1.0",
    name = "double",
    tables = list(list(
      name = "Measurement",
      columns = list(
        list(name = "id", type = "string", constraints = "primary_key"),
        list(name = "value", type = "number")
      )
    ))
  )
  schema <- new_graft_schema(compile_data_dict_manifest(
    dictionary,
    source = data_dict_test_source(dictionary),
    provider = list(
      name = "data-dict",
      export_format_version = "0.1.0"
    )
  ))
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))
  first <- 9007199254740990
  second <- 9007199254740991
  exact_values <- c(pi, sqrt(2), .Machine$double.xmax)
  exact_ids <- paste0("measurement:exact-", seq_along(exact_values))

  exact <- graft_plan(
    store,
    list(Measurement = data.frame(id = exact_ids, value = exact_values)),
    graft_provenance("double-test", idempotency_key = "double-exact")
  )
  expect_identical(exact@valid, TRUE)
  graft_commit(store, exact)
  observed <- vapply(
    exact_ids,
    \(record_id) {
      graft_get(store, record_id, include = character())$record$value
    },
    numeric(1)
  )
  expect_identical(unname(observed), exact_values)

  insert <- graft_plan(
    store,
    list(Measurement = data.frame(id = "measurement:one", value = first)),
    graft_provenance("double-test", idempotency_key = "double-first")
  )
  expect_identical(insert@valid, TRUE)
  expect_identical(insert@changes$action, "insert")
  graft_commit(store, insert)
  expect_identical(
    graft_get(store, "measurement:one", include = character())$record$value,
    first
  )

  update <- graft_plan(
    store,
    list(Measurement = data.frame(id = "measurement:one", value = second)),
    graft_provenance("double-test", idempotency_key = "double-second")
  )
  expect_identical(update@valid, TRUE)
  expect_identical(update@changes$action, "update")
  expect_identical(
    update@changes$expected_content_digest ==
      update@changes$proposed_content_digest,
    FALSE
  )
  graft_commit(store, update)
  expect_identical(
    graft_get(store, "measurement:one", include = character())$record$value,
    second
  )

  negative_zero <- graft_plan(
    store,
    list(Measurement = data.frame(id = "measurement:zero", value = -0)),
    graft_provenance("double-test", idempotency_key = "double-zero-negative")
  )
  expect_identical(negative_zero@valid, TRUE)
  graft_commit(store, negative_zero)
  retrieved_zero <- graft_get(
    store,
    "measurement:zero",
    include = character()
  )$record$value
  expect_identical(1 / retrieved_zero, Inf)

  positive_zero <- graft_plan(
    store,
    list(Measurement = data.frame(id = "measurement:zero", value = 0)),
    graft_provenance("double-test", idempotency_key = "double-zero-positive")
  )
  expect_identical(positive_zero@valid, TRUE)
  expect_identical(positive_zero@changes$action, "match")

  underflow <- graft_plan(
    store,
    list(
      Measurement = data.frame(
        id = c("measurement:underflow-1", "measurement:underflow-2"),
        value = c("1e-9999", "-1e-9999")
      )
    ),
    graft_provenance("double-test", idempotency_key = "double-underflow")
  )
  expect_identical(underflow@valid, FALSE)
  expect_equal(sum(underflow@issues$rule == "type_double"), 2L)
  expect_identical(coerce_numeric(c("0e9999", "-0e9999")), c(0, 0))
})

test_that("data-dict compilation is independent of collation locale", {
  original <- Sys.getlocale("LC_COLLATE")
  withr::defer(Sys.setlocale("LC_COLLATE", original))
  dictionary <- list(
    "$version" = "0.1.0",
    name = "locale",
    tables = list(
      list(
        name = "zebra",
        columns = list(list(
          name = "id",
          type = "string",
          constraints = "primary_key"
        ))
      ),
      list(
        name = "Aardvark",
        columns = list(list(
          name = "id",
          type = "string",
          constraints = "primary_key"
        ))
      )
    )
  )
  compile <- function() {
    compile_data_dict_manifest(
      dictionary,
      source = data_dict_test_source(dictionary),
      provider = list(
        name = "data-dict",
        export_format_version = "0.1.0"
      )
    )
  }

  c_result <- Sys.setlocale("LC_COLLATE", "C")
  expect_identical(nzchar(c_result), TRUE)
  c_locale <- compile()
  alternative <- Sys.setlocale("LC_COLLATE", "en_US.UTF-8")
  skip_if(!nzchar(alternative), "An alternate collation locale is unavailable")
  alternative_locale <- compile()

  expect_identical(alternative_locale$manifest, c_locale$manifest)
})

test_that("the adapter digest covers transitive implementation helpers", {
  observed <- data_dict_adapter_script_digest()
  local_mocked_bindings(
    duplicate_json_object_key = \(value, path = "$") {
      list(key = "changed", path = path)
    }
  )

  expect_identical(
    identical(data_dict_adapter_script_digest(), observed),
    FALSE
  )
})
