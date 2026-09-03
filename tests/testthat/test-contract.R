test_that("graft_contract_version reports pinnable versions", {
  version <- graft_contract_version()

  expect_identical(
    names(version),
    c("contract", "store_format", "plan", "snapshot_schema", "manifest", "okf")
  )
  expect_all_true(vapply(version, rlang::is_string, logical(1)))
  expect_match(version$contract, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  expect_identical(version$store_format, graft:::graft_store_format_version)
  expect_identical(version$plan, graft:::graft_plan_version)
  expect_identical(
    version$snapshot_schema,
    as.character(graft:::graft_snapshot_schema_version)
  )
  expect_identical(version$manifest, graft:::graft_manifest_version)
  expect_identical(version$okf, graft:::graft_okf_version)
})
