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
  source <- readLines(tempest_schema_path(), warn = FALSE)
  source_one <- stage_test_schema_core(source, directory_one)
  source_two <- stage_test_schema_core(source, directory_two)
  writeLines(source_one, schema_one)
  writeLines(c(source_two, "# provenance-only comment"), schema_two)

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
    'COMPILER_VERSION = "0.2.0"',
    'COMPILER_VERSION = "0.2.1"',
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
    "0.2.1"
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

test_that("installed core imports are staged beside test schemas", {
  directory <- withr::local_tempdir()
  source <- stage_test_schema_core(
    c("imports:", "  - /installed/graft-core.linkml"),
    directory
  )

  expect_identical(source, c("imports:", "  - graft-core.linkml"))
  expect_true(file.exists(
    file.path(directory, "graft-core.linkml.yaml")
  ))
})

test_that("plain LinkML schemas compile without graft annotations", {
  skip_if_no_linkml_runtime()
  manifest_path <- withr::local_tempfile(fileext = ".graft.json")

  schema <- kg_compile_schema(
    plain_linkml_schema_path(),
    manifest_path
  )
  classes <- kg_classes(schema)
  person <- schema$manifest$classes$Person

  expect_setequal(classes$class, c("Organization", "Person"))
  expect_identical(person$role, "node")
  expect_identical(person$id_policy, "require")
  expect_identical(person$id_format, "linkml")
  expect_identical(person$label_slot, "full_name")
  expect_setequal(person$search_slots, c("full_name"))
  expect_in("created_at", names(person$slots))
  expect_in("updated_at", names(person$slots))
})

test_that("plain LinkML identifiers work throughout the store", {
  skip_if_no_linkml_runtime()
  manifest_path <- withr::local_tempfile(fileext = ".graft.json")
  schema <- kg_compile_schema(
    plain_linkml_schema_path(),
    manifest_path
  )
  store <- kg_connect_duckdb(schema, ":memory:")
  withr::defer(kg_disconnect(store))
  kg_init(store)

  kg_ingest(
    store,
    kg_batch("plain-linkml", idempotency_key = "personinfo-v1"),
    list(
      Organization = data.frame(
        id = "org:daily-planet",
        name = "Daily Planet"
      ),
      Person = data.frame(
        id = "person:clark-kent",
        full_name = "Clark Kent",
        aliases = I(list(c("Superman", "Kal-El"))),
        age = 35L,
        employed_by = I(list("org:daily-planet"))
      )
    )
  )

  person <- kg_get(store, "person:clark-kent")

  expect_identical(person$class, "Person")
  expect_identical(person$record$full_name[[1]], "Clark Kent")
  expect_setequal(person$record$aliases, c("Superman", "Kal-El"))
  expect_identical(
    kg_find(store, "Clark", class = "Person", limit = 5)$id,
    "person:clark-kent"
  )
})
