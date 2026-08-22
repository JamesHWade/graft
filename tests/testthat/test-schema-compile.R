test_that("schema compilation is byte-for-byte deterministic", {
  skip_if_no_linkml_runtime()
  output_one <- withr::local_tempfile(fileext = ".graft.json")
  output_two <- withr::local_tempfile(fileext = ".graft.json")

  first <- graft_schema(tempest_schema_path(), output_one)
  second <- graft_schema(tempest_schema_path(), output_two)

  expect_identical(
    readBin(first@path, what = "raw", n = file.info(first@path)$size),
    readBin(second@path, what = "raw", n = file.info(second@path)$size)
  )
  expect_identical(
    first@structural_digest,
    second@structural_digest
  )
})

test_that("structural digest excludes paths and source-only edits", {
  skip_if_no_linkml_runtime()
  directory_one <- withr::local_tempdir()
  directory_two <- withr::local_tempdir()
  schema_one <- file.path(directory_one, "tempest.linkml.yaml")
  schema_two <- file.path(directory_two, "tempest.linkml.yaml")
  source <- readLines(tempest_schema_path(), warn = FALSE)
  source_one <- stage_test_schema_core(source, directory_one)
  source_two <- stage_test_schema_core(source, directory_two)
  writeLines(source_one, schema_one)
  writeLines(c(source_two, "# provenance-only comment"), schema_two)

  first <- graft_schema(
    schema_one,
    file.path(directory_one, "one.graft.json")
  )
  second <- graft_schema(
    schema_two,
    file.path(directory_two, "two.graft.json")
  )

  expect_identical(
    first@structural_digest,
    second@structural_digest
  )
  expect_identical(identical(first@source_digest, second@source_digest), FALSE)
  expect_identical(identical(first@build_digest, second@build_digest), FALSE)
  manifest_text <- readLines(first@path, warn = FALSE)
  expect_identical(
    any(grepl(directory_one, manifest_text, fixed = TRUE)),
    FALSE
  )
})

test_that("structural digest excludes compiler provenance", {
  skip_if_no_linkml_runtime()
  directory <- withr::local_tempdir()
  variant_script <- file.path(directory, "compile_schema_variant.py")
  script <- readLines(graft:::graft_compiler_path(), warn = FALSE)
  script <- sub(
    'COMPILER_VERSION = "0.3.0"',
    'COMPILER_VERSION = "0.3.1"',
    script,
    fixed = TRUE
  )
  writeLines(script, variant_script)
  base_output <- file.path(directory, "base.graft.json")
  variant_output <- file.path(directory, "variant.graft.json")

  base <- graft_schema(tempest_schema_path(), base_output)
  variant <- reticulate::import_from_path(
    "compile_schema_variant",
    path = directory,
    convert = TRUE
  )
  variant$compile_schema(tempest_schema_path(), variant_output)
  variant_manifest <- jsonlite::fromJSON(
    variant_output,
    simplifyVector = FALSE
  )

  variant_augmented <- augment_manifest_with_measures(
    new_compiled_schema(variant_manifest)
  )$manifest
  expect_identical(
    base@structural_digest,
    variant_augmented$fingerprints$structural_digest
  )
  expect_identical(
    base@source_digest,
    variant_manifest$fingerprints$source_digest
  )
  expect_identical(
    identical(
      base@build_digest,
      variant_manifest$fingerprints$build_digest
    ),
    FALSE
  )
  expect_identical(
    variant_manifest$compiler$version,
    "0.3.1"
  )
  condition <- rlang::catch_cnd(graft_schema(variant_output))
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "compiler_contract")
})

test_that("invalid statement shapes and qualifiers fail clearly", {
  skip_if_no_linkml_runtime()

  expect_snapshot(
    error = TRUE,
    transform = redact_repo_path,
    graft_schema(
      invalid_schema_path("invalid-mixed-shape.linkml.yaml"),
      withr::local_tempfile(fileext = ".graft.json")
    )
  )
  expect_snapshot(
    error = TRUE,
    transform = redact_repo_path,
    graft_schema(
      invalid_schema_path("invalid-qualifier.linkml.yaml"),
      withr::local_tempfile(fileext = ".graft.json")
    )
  )
})

test_that("snapshot paths are stable in covr's installed test layout", {
  installed_path <- file.path(
    normalizePath(test_path("..", ".."), winslash = "/"),
    "graft-tests",
    "testthat",
    "fixtures",
    "invalid-records",
    "invalid-qualifier.linkml.yaml"
  )

  expect_identical(
    redact_repo_path(installed_path),
    paste0(
      "<repo>/tests/testthat/fixtures/invalid-records/",
      "invalid-qualifier.linkml.yaml"
    )
  )
})

test_that("installed core imports are staged beside test schemas", {
  directory <- withr::local_tempdir()
  source <- stage_test_schema_core(
    c("imports:", "  - /installed/graft-core.linkml"),
    directory
  )

  expect_identical(source, c("imports:", "  - graft-core.linkml"))
  expect_identical(
    file.exists(file.path(directory, "graft-core.linkml.yaml")),
    TRUE
  )
})

test_that("plain LinkML schemas compile without graft annotations", {
  skip_if_no_linkml_runtime()
  manifest_path <- withr::local_tempfile(fileext = ".graft.json")

  schema <- graft_schema(
    plain_linkml_schema_path(),
    manifest_path
  )
  person <- schema@manifest$classes$Person

  expect_setequal(
    names(schema@classes),
    c("Organization", "Person", "GraftMeasure")
  )
  expect_identical(person$role, "node")
  expect_identical(person$id_policy, "require")
  expect_identical(person$id_format, "linkml")
  expect_identical(person$label_slot, "full_name")
  expect_setequal(person$search_slots, c("full_name"))
  expect_in("created_at", names(person$slots))
  expect_in("updated_at", names(person$slots))
})

test_that("plain LinkML class roles remain explicit compiler contracts", {
  skip_if_no_linkml_runtime()
  directory <- withr::local_tempdir()
  schema_path <- file.path(directory, "explicit-role.linkml.yaml")
  source <- readLines(plain_linkml_schema_path(), warn = FALSE)
  person <- match("  Person:", source)
  source <- append(
    source,
    c(
      "    annotations:",
      "      graft.role:",
      "        tag: graft.role",
      "        value: metadata"
    ),
    after = person
  )
  writeLines(source, schema_path)

  schema <- graft_schema(
    schema_path,
    file.path(directory, "explicit-role.graft.json")
  )

  expect_identical(schema@manifest$classes$Person$role, "metadata")
  expect_null(schema@manifest$classes$Person$statement_shape)
})

test_that("LinkML slot usage overrides are class-local", {
  skip_if_no_linkml_runtime()
  directory <- withr::local_tempdir()
  schema_path <- file.path(directory, "slot-usage.linkml.yaml")
  source <- readLines(plain_linkml_schema_path(), warn = FALSE)
  person <- match("  Person:", source)
  source <- append(
    source,
    c(
      "    slot_usage:",
      "      full_name:",
      "        pattern: '^[A-Z]'",
      "        annotations:",
      "          graft.external_identifier:",
      "            tag: graft.external_identifier",
      "            value: custom"
    ),
    after = person
  )
  writeLines(source, schema_path)

  schema <- graft_schema(
    schema_path,
    file.path(directory, "slot-usage.graft.json")
  )
  local <- schema@manifest$classes$Person$slots$full_name
  global <- schema@manifest$slots$full_name

  expect_identical(local$pattern, "^[A-Z]")
  expect_identical(local$external_identifier, "custom")
  expect_null(global$pattern)
  expect_null(global$external_identifier)
  expect_identical(
    schema@manifest$identifier_normalization_versions$custom,
    "1"
  )
})

test_that("LinkML class mixins fail at the compiler boundary", {
  skip_if_no_linkml_runtime()
  directory <- withr::local_tempdir()
  schema_path <- file.path(directory, "mixin.linkml.yaml")
  source <- readLines(plain_linkml_schema_path(), warn = FALSE)
  person <- match("  Person:", source)
  source <- append(
    source,
    c(
      "    mixins:",
      "      - HasTag"
    ),
    after = person
  )
  source <- c(
    source,
    "",
    "  HasTag:",
    "    mixin: true",
    "    attributes:",
    "      tag:"
  )
  writeLines(source, schema_path)

  condition <- rlang::catch_cnd(graft_schema(
    schema_path,
    file.path(directory, "mixin.graft.json")
  ))

  expect_s3_class(condition, "graft_schema_error")
  expect_match(
    conditionMessage(condition),
    "LinkML class mixins are not supported by graft-table-v1",
    fixed = TRUE
  )
})

test_that("unsupported LinkML semantics fail closed", {
  skip_if_no_linkml_runtime()
  cases <- list(
    slot_constraint = function(source) {
      field <- match("      full_name:", source)
      append(source, "        equals_string: Clark Kent", after = field)
    },
    slot_identity_prefix = function(source) {
      field <- match("      full_name:", source)
      append(
        source,
        c(
          "        id_prefixes:",
          "          - personinfo",
          "        id_prefixes_are_closed: true"
        ),
        after = field
      )
    },
    slot_type_mapping = function(source) {
      field <- match("      full_name:", source)
      append(
        source,
        c(
          "        type_mappings:",
          "          - framework: python",
          "            type: integer"
        ),
        after = field
      )
    },
    class_unique_key = function(source) {
      person <- match("  Person:", source)
      append(
        source,
        c(
          "    unique_keys:",
          "      full_name_key:",
          "        unique_key_slots:",
          "          - full_name"
        ),
        after = person
      )
    },
    class_identity_prefix = function(source) {
      person <- match("  Person:", source)
      append(
        source,
        c(
          "    id_prefixes:",
          "      - personinfo",
          "    id_prefixes_are_closed: true"
        ),
        after = person
      )
    },
    schema_slot_names_unique = function(source) {
      name <- match("name: personinfo", source)
      append(source, "slot_names_unique: true", after = name)
    },
    schema_identifier_prefix = function(source) {
      c(source, "id_prefixes:", "  - personinfo")
    },
    schema_closed_identifier_prefixes = function(source) {
      c(source, "id_prefixes_are_closed: true")
    },
    schema_graft_annotation = function(source) {
      c(
        source,
        "annotations:",
        "  graft.role:",
        "    tag: graft.role",
        "    value: node"
      )
    },
    custom_type = function(source) {
      c(
        source,
        "",
        "types:",
        "  PositiveCode:",
        "    typeof: string",
        "    pattern: '^X'"
      )
    },
    custom_type_id_spoof = function(source) {
      source[[grep("^id:", source)[[1L]]]] <-
        "id: https://w3id.org/linkml/types"
      c(
        source,
        "",
        "types:",
        "  PositiveCode:",
        "    typeof: string",
        "    pattern: '^X'"
      )
    },
    unsupported_builtin_range = function(source) {
      person <- match("  Person:", source)
      append(
        source,
        c(
          "    slot_usage:",
          "      age:",
          "        range: ncname"
        ),
        after = person
      )
    },
    enum_inheritance = function(source) {
      c(
        source,
        "",
        "enums:",
        "  BaseStatus:",
        "    permissible_values:",
        "      active:",
        "  Status:",
        "    inherits: BaseStatus",
        "    permissible_values:",
        "      pending:"
      )
    },
    enum_uri = function(source) {
      c(
        source,
        "",
        "enums:",
        "  Status:",
        "    enum_uri: sdo:status",
        "    permissible_values:",
        "      active:"
      )
    },
    enum_identifier_prefix = function(source) {
      c(
        source,
        "",
        "enums:",
        "  Status:",
        "    id_prefixes:",
        "      - personinfo",
        "    permissible_values:",
        "      active:"
      )
    },
    enum_closed_identifier_prefixes = function(source) {
      c(
        source,
        "",
        "enums:",
        "  Status:",
        "    id_prefixes_are_closed: true",
        "    permissible_values:",
        "      active:"
      )
    },
    enum_graft_annotation = function(source) {
      c(
        source,
        "",
        "enums:",
        "  Status:",
        "    annotations:",
        "      graft.role:",
        "        tag: graft.role",
        "        value: node",
        "    permissible_values:",
        "      active:"
      )
    },
    permissible_value_graft_annotation = function(source) {
      c(
        source,
        "",
        "enums:",
        "  Status:",
        "    permissible_values:",
        "      active:",
        "        annotations:",
        "          graft.sensitive:",
        "            tag: graft.sensitive",
        "            value: true"
      )
    },
    permissible_value_hierarchy = function(source) {
      c(
        source,
        "",
        "enums:",
        "  Status:",
        "    permissible_values:",
        "      base:",
        "      child:",
        "        is_a: base"
      )
    }
  )

  for (name in names(cases)) {
    directory <- withr::local_tempdir()
    schema_path <- file.path(directory, paste0(name, ".linkml.yaml"))
    output <- file.path(directory, paste0(name, ".graft.json"))
    source <- readLines(plain_linkml_schema_path(), warn = FALSE)
    writeLines(cases[[name]](source), schema_path)

    condition <- rlang::catch_cnd(graft_schema(schema_path, output))

    expect_s3_class(condition, "graft_schema_error")
    expect_match(conditionMessage(condition), "unsupported", ignore.case = TRUE)
    expect_identical(file.exists(output), FALSE)
  }
})

test_that("manifest validation precedes LinkML artifact publication", {
  skip_if_no_linkml_runtime()
  directory <- withr::local_tempdir()
  schema_path <- file.path(directory, "empty-identifier.linkml.yaml")
  output <- file.path(directory, "empty-identifier.graft.json")
  source <- readLines(plain_linkml_schema_path(), warn = FALSE)
  field <- match("      full_name:", source)
  source <- append(
    source,
    c(
      "        annotations:",
      "          graft.external_identifier:",
      "            tag: graft.external_identifier",
      "            value: ''"
    ),
    after = field
  )
  writeLines(source, schema_path)
  writeLines("previous validated artifact", output)

  condition <- rlang::catch_cnd(graft_schema(schema_path, output))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "manifest_shape_contract")
  expect_identical(
    readLines(output, warn = FALSE),
    "previous validated artifact"
  )
})

test_that("fixed predicates remain one truth from plan to projection", {
  skip_if_no_linkml_runtime()
  directory <- withr::local_tempdir()
  schema_path <- file.path(directory, "fixed-edge.linkml.yaml")
  writeLines(
    c(
      "id: https://example.org/fixed-edge",
      "name: fixed-edge",
      "prefixes:",
      "  ex: https://example.org/",
      "  linkml: https://w3id.org/linkml/",
      "imports:",
      "  - graft-core.linkml",
      "default_prefix: ex",
      "classes:",
      "  FixedEdge:",
      "    is_a: GraftEdge",
      "    annotations:",
      "      graft.fixed_predicate:",
      "        tag: graft.fixed_predicate",
      "        value: ex:fixed"
    ),
    schema_path
  )
  expect_identical(
    file.copy(
      graft_core_schema_path(),
      file.path(directory, "graft-core.linkml.yaml")
    ),
    TRUE
  )
  schema <- graft_schema(
    schema_path,
    file.path(directory, "fixed-edge.graft.json")
  )
  store <- graft_open(schema, okf = "disabled")
  withr::defer(graft_close(store))

  plan <- graft_plan(
    store,
    list(
      FixedEdge = data.frame(
        id = test_graft_id("fixed-edge"),
        subject = test_graft_id("fixed-subject"),
        predicate = "ex:conflict",
        object = test_graft_id("fixed-object")
      )
    ),
    graft_provenance(
      "fixed-predicate-test",
      idempotency_key = "fixed-predicate-conflict"
    )
  )

  expect_identical(plan@valid, FALSE)
  expect_in("fixed_predicate", plan@issues$rule)
})

test_that("LinkML compilation publishes only validated manifests", {
  skip_if_no_linkml_runtime()
  directory <- withr::local_tempdir()
  schema_path <- file.path(directory, "invalid-role.linkml.yaml")
  output <- file.path(directory, "invalid-role.graft.json")
  source <- readLines(plain_linkml_schema_path(), warn = FALSE)
  person <- match("  Person:", source)
  source <- append(
    source,
    c(
      "    annotations:",
      "      graft.role:",
      "        tag: graft.role",
      "        value: statement"
    ),
    after = person
  )
  writeLines(source, schema_path)
  writeLines("previous validated artifact", output)

  condition <- rlang::catch_cnd(graft_schema(schema_path, output))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "class_role_contract")
  expect_identical(
    readLines(output, warn = FALSE),
    "previous validated artifact"
  )
  expect_length(
    list.files(directory, pattern = "[.]graft[.]json-stage-"),
    0L
  )
})

test_that("LinkML output validation protects the source", {
  skip_if_no_linkml_runtime()
  source <- plain_linkml_schema_path()
  before <- readBin(source, what = "raw", n = file.info(source)$size)

  condition <- rlang::catch_cnd(graft_schema(source, source))

  expect_s3_class(condition, "graft_schema_error")
  expect_match(
    conditionMessage(condition),
    "`output` must use the `.graft.json` extension",
    fixed = TRUE
  )
  expect_identical(
    readBin(source, what = "raw", n = file.info(source)$size),
    before
  )
})

test_that("plain LinkML identifiers compile to projection contracts", {
  skip_if_no_linkml_runtime()
  manifest_path <- withr::local_tempfile(fileext = ".graft.json")
  schema <- graft_schema(
    plain_linkml_schema_path(),
    manifest_path
  )
  person <- schema@manifest$classes$Person
  relation_names <- vapply(
    schema@manifest$relations,
    \(.x) .x$name,
    character(1)
  )

  expect_identical(person$view, "person")
  expect_identical(person$slots$full_name$view_column, "full_name")
  expect_identical(person$slots$age$duckdb_type, "BIGINT")
  expect_null(person$slots$aliases$view_column)
  expect_setequal(
    relation_names,
    c("Person.aliases", "Person.employed_by")
  )
  expect_identical(
    schema@manifest$relations[[match("Person.aliases", relation_names)]]$view,
    "person__aliases"
  )
})
