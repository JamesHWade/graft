test_that("backup descriptors require canonical fields and bytes", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  artifact_save(source, "report", charToRaw("report bytes"), "text/plain")
  backup_path <- file.path(withr::local_tempdir(), "closed-backup")
  receipt <- graft_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "generation-1"
  )
  descriptor <- artifact_backup_validation_descriptor(backup_path)$value
  variants_parent <- withr::local_tempdir()

  variants <- list(
    unsupported_format = function(value) {
      value$format <- "graft-artifact-backup/999"
      value
    },
    extra_field = function(value) {
      value$unexpected <- "field"
      value
    },
    missing_format = function(value) {
      value$format <- NULL
      value
    },
    missing_scope = function(value) {
      value$scope <- NULL
      value
    },
    missing_generation = function(value) {
      value$generation <- NULL
      value
    },
    missing_manifest = function(value) {
      value$manifest <- NULL
      value
    }
  )
  for (name in names(variants)) {
    variant_path <- artifact_backup_validation_clone(
      backup_path,
      variants_parent,
      name
    )
    variant <- variants[[name]](descriptor)
    variant_receipt <- artifact_backup_validation_write_descriptor(
      variant_path,
      variant,
      scope = receipt$scope,
      generation = receipt$generation,
      manifest = receipt$manifest
    )
    expect_error(
      graft_verify_backup(variant_path, variant_receipt),
      class = "graft_artifact_error"
    )
  }

  reordered_path <- artifact_backup_validation_clone(
    backup_path,
    variants_parent,
    "reordered"
  )
  reordered <- descriptor[c("scope", "format", "generation", "manifest")]
  reordered_receipt <- artifact_backup_validation_write_descriptor(
    reordered_path,
    reordered,
    scope = receipt$scope,
    generation = receipt$generation,
    manifest = receipt$manifest
  )
  expect_error(
    graft_verify_backup(reordered_path, reordered_receipt),
    class = "graft_artifact_error"
  )

  whitespace_path <- artifact_backup_validation_clone(
    backup_path,
    variants_parent,
    "whitespace"
  )
  whitespace_bytes <- charToRaw(paste0(
    "\n  ",
    rawToChar(artifact_encode(descriptor)),
    "  \n"
  ))
  whitespace_receipt <- artifact_backup_validation_write_descriptor(
    whitespace_path,
    descriptor,
    scope = receipt$scope,
    generation = receipt$generation,
    manifest = receipt$manifest,
    bytes = whitespace_bytes
  )
  expect_error(
    graft_verify_backup(whitespace_path, whitespace_receipt),
    class = "graft_artifact_error"
  )
})

test_that("manifest identity, duplicate entries, and object files are verified", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  ref <- artifact_save(
    source,
    "report",
    charToRaw("report bytes"),
    "text/plain"
  )
  backup_path <- file.path(withr::local_tempdir(), "closed-backup")
  receipt <- graft_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "generation-1"
  )
  descriptor <- artifact_backup_validation_descriptor(backup_path)$value
  variants_parent <- withr::local_tempdir()

  duplicate_path <- artifact_backup_validation_clone(
    backup_path,
    variants_parent,
    "duplicate"
  )
  duplicate <- descriptor
  duplicate$manifest$objects <- c(
    duplicate$manifest$objects,
    list(duplicate$manifest$objects[[1L]])
  )
  duplicate$manifest <- artifact_recovery_manifest(
    duplicate$manifest$objects
  )
  duplicate_receipt <- artifact_backup_validation_write_descriptor(
    duplicate_path,
    duplicate,
    scope = receipt$scope,
    generation = receipt$generation,
    manifest = duplicate$manifest$id
  )
  expect_error(
    graft_verify_backup(duplicate_path, duplicate_receipt),
    regexp = "duplicate",
    class = "graft_artifact_error"
  )

  corrupt_path <- artifact_backup_validation_clone(
    backup_path,
    variants_parent,
    "corrupt-manifest-id"
  )
  corrupt <- descriptor
  corrupt$manifest$id <- strrep("0", 64)
  corrupt_receipt <- artifact_backup_validation_write_descriptor(
    corrupt_path,
    corrupt,
    scope = receipt$scope,
    generation = receipt$generation,
    manifest = corrupt$manifest$id
  )
  expect_error(
    graft_verify_backup(corrupt_path, corrupt_receipt),
    class = "graft_artifact_error"
  )

  extra_path <- artifact_backup_validation_clone(
    backup_path,
    variants_parent,
    "extra-object"
  )
  extra_bytes <- charToRaw("unlisted orphan content")
  extra_key <- digest::digest(
    extra_bytes,
    algo = "sha256",
    serialize = FALSE
  )
  writeBin(
    extra_bytes,
    file.path(extra_path, "objects", "content", extra_key)
  )
  expect_error(
    graft_verify_backup(extra_path, receipt),
    class = "graft_artifact_error"
  )

  missing_path <- artifact_backup_validation_clone(
    backup_path,
    variants_parent,
    "missing-object"
  )
  object <- descriptor$manifest$objects[[1L]]
  object_path <- file.path(
    missing_path,
    "objects",
    object$kind,
    object$key
  )
  unlink(object_path)
  expect_error(
    graft_verify_backup(missing_path, receipt),
    class = "graft_artifact_error"
  )

  target <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_error(
    graft_restore(missing_path, target, receipt),
    class = "graft_artifact_error"
  )
  expect_identical(graft_manifest(target)$objects, list())
  expect_identical(
    artifact_read(source, ref)$bytes,
    charToRaw("report bytes")
  )
})

test_that("backup verification applies each independent caller limit", {
  source <- graft_store(withr::local_tempdir(), create = TRUE)
  fixture <- artifact_recovery_fixture(source)
  backup_path <- file.path(withr::local_tempdir(), "closed-backup")
  receipt <- graft_backup(
    source,
    backup_path,
    scope = "reader-a",
    generation = "generation-1"
  )

  limits <- list(
    max_objects = 1L,
    max_total_bytes = 1L,
    max_revision_bytes = 1L,
    max_metadata_bytes = 1L,
    max_bundle_metadata_bytes = 1L
  )
  for (name in names(limits)) {
    expect_error(
      do.call(
        graft_verify_backup,
        c(
          list(path = backup_path, expected = receipt),
          setNames(list(limits[[name]]), name)
        )
      ),
      class = "graft_artifact_error"
    )
  }

  expect_identical(
    artifact_read_decision(source, "mixed-stream"),
    fixture$mixed_second
  )
})
