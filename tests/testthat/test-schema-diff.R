test_that("schema compatibility is an ordinary structural result", {
  schema <- as_graft_schema_internal(graft_schema(tempest_manifest_path()))

  compatibility <- schema_compatibility(schema, schema)

  expect_identical(is.object(compatibility), FALSE)
  expect_identical(compatibility$compatible, TRUE)
  expect_identical(compatibility$classification, "compatible")
  expect_identical(
    compatibility$old_structural_digest,
    compatibility$new_structural_digest
  )
})

test_that("compiler provenance does not change semantic compatibility", {
  old <- as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  rebuilt <- unserialize(serialize(old, NULL))
  rebuilt$manifest$fingerprints$source_digest <- graft_sha256("new source")
  rebuilt$manifest$fingerprints$build_digest <- graft_sha256("new build")

  compatibility <- schema_compatibility(old, rebuilt)

  expect_identical(compatibility$compatible, TRUE)
  expect_identical(compatibility$classification, "compatible")
})

test_that("structural changes are incompatible", {
  old <- as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  changed <- unserialize(serialize(old, NULL))
  changed$manifest$classes$Entity$slots$description$sensitive <- TRUE
  changed <- refresh_schema_structural_digest(changed)

  compatibility <- schema_compatibility(old, changed)

  expect_identical(compatibility$compatible, FALSE)
  expect_identical(compatibility$classification, "structural change")
  expect_identical(
    identical(
      compatibility$old_structural_digest,
      compatibility$new_structural_digest
    ),
    FALSE
  )
})

test_that("stale structural digests are never compatible", {
  old <- as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  stale <- unserialize(serialize(old, NULL))
  stale$manifest$classes$Entity$slots$description$sensitive <- TRUE

  compatibility <- schema_compatibility(old, stale)

  expect_identical(compatibility$compatible, FALSE)
  expect_identical(
    compatibility$classification,
    "invalid structural digest"
  )
})
