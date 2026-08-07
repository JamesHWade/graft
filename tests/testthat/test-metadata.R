test_that("canonical JSON preserves distinct finite doubles", {
  values <- c(
    0.1,
    pi,
    9007199254740990,
    9007199254740991
  )

  encoded <- canonical_json(as.list(values))
  decoded <- unlist(
    jsonlite::fromJSON(encoded, simplifyVector = FALSE),
    use.names = FALSE
  )

  expect_identical(decoded, values)
  expect_identical(
    canonical_json(list(value = values[[3L]])) ==
      canonical_json(list(value = values[[4L]])),
    FALSE
  )
  expect_identical(
    canonical_identity_value(values[[3L]]) ==
      canonical_identity_value(values[[4L]]),
    FALSE
  )
  expect_identical(canonical_json(list(value = -0)), '{"value":0}')
  expect_identical(
    canonical_identity_value(-0),
    canonical_identity_value(0)
  )
  expect_identical(
    canonical_json(list(
      first = NULL,
      nested = list(value = NULL),
      last = NULL
    )),
    '{"first":null,"nested":{"value":null},"last":null}'
  )
})

test_that("stored manifests require canonical JSON", {
  manifest <- graft_schema(data_dict_personinfo_export_path())@manifest
  manifest$dictionary$document$custom_numeric <- 9007199254740991
  manifest$fingerprints$build_digest <- manifest_build_digest(manifest)
  canonical <- canonical_manifest_json(manifest)
  aliased <- sub(
    '"custom_numeric":9007199254740991',
    '"custom_numeric":9007199254740991.1',
    canonical,
    fixed = TRUE
  )
  expect_identical(aliased == canonical, FALSE)

  condition <- rlang::catch_cnd(compiled_schema_from_json(aliased))

  expect_s3_class(condition, "graft_backend_error")
  expect_identical(condition$rule, "stored_manifest_canonical_json")
})

test_that("stored manifests reject duplicate JSON object keys", {
  manifest <- graft_schema(data_dict_personinfo_export_path())@manifest
  canonical <- canonical_manifest_json(manifest)
  duplicated <- sub(
    '"manifest_version":"2.0.0"',
    paste0(
      '"manifest_version":"2.0.0",',
      '"manifest_version":"2.0.0"'
    ),
    canonical,
    fixed = TRUE
  )

  condition <- rlang::catch_cnd(compiled_schema_from_json(duplicated))

  expect_s3_class(condition, "graft_backend_error")
  expect_identical(condition$rule, "duplicate_json_key")
})
