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
  variant_schema <- graft_schema(variant_output)

  expect_identical(
    base@structural_digest,
    variant_schema@structural_digest
  )
  expect_identical(
    base@source_digest,
    variant_schema@source_digest
  )
  expect_identical(
    identical(base@build_digest, variant_schema@build_digest),
    FALSE
  )
  expect_identical(
    variant_schema@manifest$compiler$version,
    "0.3.1"
  )
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

  expect_setequal(names(schema@classes), c("Organization", "Person"))
  expect_identical(person$role, "node")
  expect_identical(person$id_policy, "require")
  expect_identical(person$id_format, "linkml")
  expect_identical(person$label_slot, "full_name")
  expect_setequal(person$search_slots, c("full_name"))
  expect_in("created_at", names(person$slots))
  expect_in("updated_at", names(person$slots))
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
