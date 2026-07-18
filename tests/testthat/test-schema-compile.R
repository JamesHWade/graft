test_that("schema compilation is byte-for-byte deterministic", {
  skip_if_no_linkml_runtime()
  output_one <- withr::local_tempfile(fileext = ".graft.json")
  output_two <- withr::local_tempfile(fileext = ".graft.json")

  first <- kg_compile_schema(tempest_schema_path(), output_one)
  second <- kg_compile_schema(tempest_schema_path(), output_two)

  expect_identical(
    readBin(first$path, what = "raw", n = file.info(first$path)$size),
    readBin(second$path, what = "raw", n = file.info(second$path)$size)
  )
  expect_identical(
    kg_schema_info(first)$structural_digest,
    kg_schema_info(second)$structural_digest
  )
})

test_that("structural digest excludes paths and source-only edits", {
  skip_if_no_linkml_runtime()
  directory_one <- withr::local_tempdir()
  directory_two <- withr::local_tempdir()
  schema_one <- file.path(directory_one, "tempest.linkml.yaml")
  schema_two <- file.path(directory_two, "tempest.linkml.yaml")
  core_import <- sub(
    "\\.yaml$",
    "",
    graft_core_schema_path()
  )
  source <- readLines(tempest_schema_path(), warn = FALSE)
  source <- sub(
    "\\.\\./\\.\\./\\.\\./\\.\\./inst/schema/graft-core\\.linkml",
    core_import,
    source
  )
  writeLines(source, schema_one)
  writeLines(c(source, "# provenance-only comment"), schema_two)

  first <- kg_compile_schema(schema_one, file.path(directory_one, "one.json"))
  second <- kg_compile_schema(schema_two, file.path(directory_two, "two.json"))
  first_info <- kg_schema_info(first)
  second_info <- kg_schema_info(second)

  expect_identical(
    first_info$structural_digest,
    second_info$structural_digest
  )
  expect_false(identical(first_info$source_digest, second_info$source_digest))
  expect_false(identical(first_info$build_digest, second_info$build_digest))
  manifest_text <- readLines(first$path, warn = FALSE)
  expect_false(any(grepl(directory_one, manifest_text, fixed = TRUE)))
})

test_that("structural digest excludes compiler provenance", {
  skip_if_no_linkml_runtime()
  directory <- withr::local_tempdir()
  variant_script <- file.path(directory, "compile_schema_variant.py")
  script <- readLines(graft:::graft_compiler_path(), warn = FALSE)
  script <- sub(
    'COMPILER_VERSION = "0.1.0"',
    'COMPILER_VERSION = "0.1.1"',
    script,
    fixed = TRUE
  )
  writeLines(script, variant_script)
  base_output <- file.path(directory, "base.json")
  variant_output <- file.path(directory, "variant.json")

  base <- kg_compile_schema(tempest_schema_path(), base_output)
  variant <- reticulate::import_from_path(
    "compile_schema_variant",
    path = directory,
    convert = TRUE
  )
  variant$compile_schema(tempest_schema_path(), variant_output)
  variant_schema <- kg_schema(variant_output)

  expect_identical(
    kg_schema_info(base)$structural_digest,
    kg_schema_info(variant_schema)$structural_digest
  )
  expect_identical(
    kg_schema_info(base)$source_digest,
    kg_schema_info(variant_schema)$source_digest
  )
  expect_false(
    identical(
      kg_schema_info(base)$build_digest,
      kg_schema_info(variant_schema)$build_digest
    )
  )
  expect_identical(
    variant_schema$manifest$compiler$version,
    "0.1.1"
  )
})

test_that("invalid statement shapes and qualifiers fail clearly", {
  skip_if_no_linkml_runtime()

  expect_snapshot(
    error = TRUE,
    transform = redact_repo_path,
    kg_compile_schema(
      invalid_schema_path("invalid-mixed-shape.linkml.yaml"),
      withr::local_tempfile(fileext = ".json")
    )
  )
  expect_snapshot(
    error = TRUE,
    transform = redact_repo_path,
    kg_compile_schema(
      invalid_schema_path("invalid-qualifier.linkml.yaml"),
      withr::local_tempfile(fileext = ".json")
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
