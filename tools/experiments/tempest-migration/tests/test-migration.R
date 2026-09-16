test_that("the target retains native identities, history, schema and exact evidence", {
  target <- local_migration()
  restored <- migration_open(target$target, target$handle)
  expect_identical(restored$checkpoints, migration_fixture$checkpoints)
  expect_identical(restored$receipts, migration_fixture$receipts)
  expect_identical(
    restored$promotion_bundles,
    migration_fixture$promotion_bundles
  )
  expect_identical(unname(restored$history), migration_fixture$history)
  expect_identical(restored$schema, migration_fixture$schema)
  expect_identical(
    restored$schema_file_text,
    migration_fixture$schema_file_text
  )
  expect_identical(restored$final_snapshot, migration_fixture$final_snapshot)
  expect_identical(
    names(restored$identity_map),
    vapply(migration_fixture$history, \(row) row$revision_id, character(1))
  )
  expect_length(restored$history, 11L)
  expect_length(restored$checkpoints$initial$resources, 4L)
  expect_length(restored$checkpoints$correction$resources, 4L)
  revised <- Filter(\(row) row$revision_number > 1L, restored$history)
  expect_length(revised, 1L)
  expect_identical(revised[[1]]$record$status, "superseded")
  expect_identical(
    migration_revision(restored, revised[[1]]$prior_revision_id)$record$status,
    "active"
  )
  expect_match(restored$checkpoints$initial$report_md, "82%", fixed = TRUE)
  expect_match(restored$checkpoints$correction$report_md, "62%", fixed = TRUE)
})

test_that("native timestamps survive JSON without losing fractional seconds", {
  timestamp <- as.POSIXct("2026-01-01", tz = "UTC") + 0.123456
  encoded <- migration_plain(list(recorded_at = timestamp))$recorded_at
  expect_identical(as.numeric(encoded$epoch_hex), as.numeric(timestamp))
  expect_identical(encoded$type, "POSIXct")
  expect_identical(
    migration_plain(as.Date("2026-01-01")),
    list(type = "Date", days = 20454L)
  )
})

test_that("portable reads run in a fresh process without Graft or Tempest", {
  target <- local_migration()
  library <- withr::local_tempdir()
  for (package in c("jsonlite", "digest", "rlang")) {
    expect_equal(
      file.copy(find.package(package), library, recursive = TRUE),
      TRUE
    )
  }
  restored <- callr::r(
    function(checkout, target, handle) {
      if (
        requireNamespace("graft", quietly = TRUE) ||
          requireNamespace("tempest", quietly = TRUE)
      ) {
        stop(
          "The portable-reader library unexpectedly contains Graft or Tempest."
        )
      }
      for (file in c(
        "artifacts/content.R",
        "artifacts/backends.R",
        "tempest-migration/migration.R"
      )) {
        source(file.path(checkout, "tools/experiments", file))
      }
      list(
        pid = Sys.getpid(),
        value = migration_read(target, handle, "initial")
      )
    },
    args = list(migration_checkout, target$target, target$handle),
    libpath = c(library, .Library)
  )
  expect_length(unique(c(Sys.getpid(), restored$pid)), 2L)
  expect_identical(restored$value, migration_fixture$checkpoints$initial)
})

test_that("native Tempest admission explicitly rejects the portable view", {
  target <- local_migration()
  portable <- migration_read(target$target, target$handle, "initial")
  expect_error(
    tempest::tempest_knowledge(
      portable,
      record_ids = unlist(portable$record_ids)
    ),
    "valid pinned Graft view",
    class = "tempest_knowledge_error"
  )
})

test_that("incomplete or inconsistent histories fail before import", {
  altered <- migration_fixture
  altered$final_snapshot$schema_build_digest <- "another-schema"
  expect_error(
    migration_validate(altered),
    "only the pinned Tempest schema",
    class = "artifact_experiment_error"
  )
  altered <- migration_fixture
  altered$promotion_bundles$initial$bundle_json <- sub(
    "82%",
    "83%",
    altered$promotion_bundles$initial$bundle_json,
    fixed = TRUE
  )
  expect_error(
    migration_validate(altered),
    "bundle bytes do not match",
    class = "artifact_experiment_error"
  )
  altered <- migration_fixture
  altered$history <- altered$history[-length(altered$history)]
  expect_error(
    migration_validate(altered),
    "Missing or ambiguous native revision",
    class = "artifact_experiment_error"
  )
  altered <- migration_fixture
  altered$history[[2]] <- altered$history[[1]]
  expect_error(
    migration_validate(altered),
    "Duplicate native revision",
    class = "artifact_experiment_error"
  )
  altered <- migration_fixture
  changed <- which(vapply(
    altered$history,
    \(row) row$revision_number > 1L,
    logical(1)
  ))
  altered$history[[changed]]$prior_revision_id <- "absent"
  expect_error(
    migration_validate(altered),
    "Missing or ambiguous native revision",
    class = "artifact_experiment_error"
  )
  altered <- migration_fixture
  altered$history[[1]]$operation <- "delete"
  expect_error(
    migration_validate(altered),
    "Tombstone or other native operation is unsupported",
    class = "artifact_experiment_error"
  )
  altered <- migration_fixture
  altered$receipts$initial$store_id <- "another-store"
  expect_error(
    migration_validate(altered),
    "Receipt identity",
    class = "artifact_experiment_error"
  )
  altered <- migration_fixture
  altered$checkpoints$initial$snapshot$store_id <- "another-store"
  expect_error(
    migration_validate(altered),
    "another store",
    class = "artifact_experiment_error"
  )
  altered <- migration_fixture
  altered$schema_file_text <- "changed schema"
  expect_error(
    migration_validate(altered),
    "schema bytes do not match",
    class = "artifact_experiment_error"
  )
})

test_that("selection and evidence dependencies cannot be dropped together", {
  altered <- migration_fixture
  altered$checkpoints$initial$record_ids <- altered$checkpoints$initial$record_ids[
    -1
  ]
  expect_error(
    migration_validate(altered),
    "complete selection",
    class = "artifact_experiment_error"
  )
  altered <- migration_fixture
  checkpoint <- altered$checkpoints$initial
  source <- which(vapply(
    checkpoint$resources,
    \(resource) resource$metadata$graft_record_class == "Source",
    logical(1)
  ))
  source_id <- checkpoint$record_ids[[source]]
  checkpoint$record_ids <- checkpoint$record_ids[-source]
  checkpoint$revision_ids <- checkpoint$revision_ids[-source]
  checkpoint$resources <- checkpoint$resources[-source]
  checkpoint$selections <- lapply(checkpoint$selections, function(selection) {
    Filter(\(ref) !identical(ref$record_id, source_id), selection)
  })
  altered$checkpoints$initial <- checkpoint
  expect_error(
    migration_validate(altered),
    "required evidence dependency",
    class = "artifact_experiment_error"
  )
})

test_that("the handoff digest and retained content detect changed bytes", {
  target <- withr::local_tempdir()
  expect_error(
    migration_import(migration_fixture_path, strrep("0", 64), target),
    "trusted handoff digest",
    class = "artifact_experiment_error"
  )
  expect_length(list.files(target), 0L)
  target <- local_migration()
  export <- migration_open(target$target, target$handle)
  store <- artifact_store(target$target, "manifest", "unused")
  metadata <- artifact_metadata(store, export$identity_map[[1]])
  path <- artifact_digest_path(target$target, "content", metadata$payload)
  writeBin(charToRaw("corrupt history"), path)
  expect_error(
    migration_read(target$target, target$handle, "initial"),
    "digest or size mismatch",
    class = "artifact_experiment_error"
  )
})

test_that("withdrawal survives reopening and an import retry cannot reapprove it", {
  target <- local_migration()
  store <- artifact_store(target$target, "manifest", "unused")
  artifact_revoke(store, target$handle$basis)
  policy_path <- artifact_digest_path(
    target$target,
    "policy",
    target$handle$basis
  )
  policy <- artifact_read_bytes(policy_path)
  expect_error(
    migration_read(target$target, target$handle, "initial"),
    "not eligible",
    class = "artifact_experiment_error"
  )
  expect_identical(
    migration_read(target$target, target$handle, "initial", consult = FALSE),
    migration_fixture$checkpoints$initial
  )
  expect_error(
    migration_import(
      migration_fixture_path,
      migration_fixture_digest,
      target$target
    ),
    "target must be empty",
    class = "artifact_experiment_error"
  )
  expect_identical(artifact_read_bytes(policy_path), policy)
})
