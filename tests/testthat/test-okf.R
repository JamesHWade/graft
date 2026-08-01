test_that("OKF absolute paths include Windows network shares", {
  expect_identical(graft:::okf_is_absolute_path("/tmp/bundle.okf"), TRUE)
  expect_identical(
    graft:::okf_is_absolute_path("C:\\exports\\bundle.okf"),
    TRUE
  )
  expect_identical(
    graft:::okf_is_absolute_path("\\\\server\\share\\bundle.okf"),
    TRUE
  )
  expect_identical(graft:::okf_is_absolute_path("exports/bundle.okf"), FALSE)

  parent <- withr::local_tempdir()
  expected <- file.path(
    normalizePath(parent, winslash = "/", mustWork = TRUE),
    "bundle.okf"
  )
  trailing <- paste0(expected, .Platform$file.sep)
  expect_identical(graft:::okf_normalize_path(trailing), expected)
  expect_identical(graft:::okf_output_path(trailing), expected)
})

test_that("kg_export_okf writes a deterministic source-linked bundle", {
  fixture <- local_vertical_slice_store()
  first_path <- tempfile("graft-okf-first-")
  second_path <- tempfile("graft-okf-second-")

  first <- kg_export_okf(fixture$store, first_path, limit = 100)
  second <- kg_export_okf(fixture$store, second_path, limit = 100)

  expect_s3_class(first, "kg_okf_bundle")
  expect_identical(first$okf_version, "0.2")
  expect_identical(first$concept_count, 29L)
  expect_identical(first$classes, second$classes)

  first_files <- list.files(first_path, recursive = TRUE)
  second_files <- list.files(second_path, recursive = TRUE)
  expect_identical(first_files, second_files)
  expect_identical(
    unname(vapply(
      file.path(first_path, first_files),
      \(path) paste(readLines(path, warn = FALSE), collapse = "\n"),
      character(1)
    )),
    unname(vapply(
      file.path(second_path, second_files),
      \(path) paste(readLines(path, warn = FALSE), collapse = "\n"),
      character(1)
    ))
  )

  claim_path <- file.path(
    first_path,
    "concepts",
    "Claim",
    paste0(
      utils::URLencode(fixture$ids$claim_branching, reserved = TRUE),
      ".md"
    )
  )
  frontmatter <- graft:::okf_parse_frontmatter(claim_path)
  body <- paste(readLines(claim_path, warn = FALSE), collapse = "\n")

  expect_identical(frontmatter$type, "Claim")
  expect_identical(frontmatter$status, "stable")
  expect_identical(frontmatter$generated$by, "tempest/0.9.0")
  expect_identical(frontmatter$graft$record_id, fixture$ids$claim_branching)
  expect_identical(
    frontmatter$graft$record$statement_text,
    "Increasing short-chain branching generally lowers LLDPE crystallinity."
  )
  expect_match(
    frontmatter$graft$public_content_digest,
    "^sha256:"
  )
  expect_length(frontmatter$sources, 2L)
  expect_in(
    "https://example.org/lldpe/review",
    vapply(frontmatter$sources, \(.x) .x$resource, character(1))
  )
  expect_match(body, "## Relationships", fixed = TRUE)
  expect_match(body, "/concepts/Entity/", fixed = TRUE)
  expect_match(body, "[^source-", fixed = TRUE)
})

test_that("kg_export_okf recovers a historical accepted boundary", {
  fixture <- local_vertical_slice_store()
  current_path <- tempfile("graft-okf-current-")
  historical_path <- tempfile("graft-okf-historical-")

  kg_export_okf(fixture$store, current_path, limit = 100)
  historical <- kg_export_okf(
    fixture$store,
    historical_path,
    as_of = fixture$result_one$batch_id,
    limit = 100
  )

  current_claim <- graft:::okf_parse_frontmatter(file.path(
    current_path,
    "concepts",
    "Claim",
    paste0(
      utils::URLencode(fixture$ids$claim_range_old, reserved = TRUE),
      ".md"
    )
  ))
  historical_claim <- graft:::okf_parse_frontmatter(file.path(
    historical_path,
    "concepts",
    "Claim",
    paste0(
      utils::URLencode(fixture$ids$claim_range_old, reserved = TRUE),
      ".md"
    )
  ))

  expect_identical(historical$concept_count, 15L)
  expect_identical(historical$as_of_batch_id, fixture$result_one$batch_id)
  expect_identical(
    historical$schema_build_digest,
    historical_claim$graft$schema_build_digest
  )
  expect_identical(current_claim$status, "deprecated")
  expect_identical(historical_claim$status, "stable")
  expect_identical(
    historical_claim$graft$batch_id,
    fixture$result_one$batch_id
  )
})

test_that("kg_export_okf only overwrites its own complete bundles", {
  fixture <- local_vertical_slice_store()
  path <- tempfile("graft-okf-overwrite-")
  dir.create(path)
  writeLines("keep", file.path(path, "important.txt"))

  expect_error(
    kg_export_okf(fixture$store, path, limit = 100, overwrite = TRUE),
    class = "graft_backend_error"
  )
  expect_identical(readLines(file.path(path, "important.txt")), "keep")

  owned <- tempfile("graft-okf-owned-")
  kg_export_okf(fixture$store, owned, limit = 100)
  writeLines("obsolete", file.path(owned, "obsolete.txt"))
  replacement <- kg_export_okf(
    fixture$store,
    owned,
    limit = 100,
    overwrite = TRUE
  )

  expect_identical(replacement$concept_count, 29L)
  expect_identical(file.exists(file.path(owned, "obsolete.txt")), FALSE)
})

test_that("kg_export_okf refuses partial or unknown-class exports", {
  fixture <- local_vertical_slice_store()
  limited <- tempfile("graft-okf-limited-")

  expect_error(
    kg_export_okf(fixture$store, limited, limit = 1),
    class = "graft_limit_error"
  )
  expect_identical(dir.exists(limited), FALSE)

  expect_error(
    kg_export_okf(
      fixture$store,
      tempfile("graft-okf-unknown-"),
      classes = "Unknown"
    ),
    class = "graft_validation_error"
  )
})

test_that("kg_okf_bundle prints its portable boundary", {
  fixture <- local_vertical_slice_store()
  bundle <- kg_export_okf(
    fixture$store,
    tempfile("graft-okf-print-"),
    classes = "Entity",
    limit = 10
  )

  output <- capture.output(print(bundle))
  expect_match(output[[1]], "<kg_okf_bundle> OKF 0.2", fixed = TRUE)
  expect_match(output[[2]], "path:", fixed = TRUE)
  expect_match(output[[3]], "concepts:   4", fixed = TRUE)
  expect_match(output[[4]], "structural: sha256:", fixed = TRUE)
})
