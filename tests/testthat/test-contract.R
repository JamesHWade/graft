test_that("consumer contract names only retained formats", {
  expect_identical(
    graft_contract_version(),
    list(
      contract = "3.0.0",
      artifact = "1",
      selection = "1",
      decision = "1",
      vocabulary = "graft-vocabulary/1",
      bindings = "graft-bindings/1",
      vocabulary_release = "graft-vocabulary-release/1"
    )
  )
  expect_setequal(
    getNamespaceExports("graft"),
    c(
      "graft_contract_version",
      "graft_artifact_store",
      "graft_artifact_store_postgres",
      "graft_artifact_save",
      "graft_artifact_read",
      "graft_artifact_select",
      "graft_artifact_read_selection",
      "graft_artifact_decide",
      "graft_artifact_read_decision",
      "graft_artifact_reuse",
      "graft_vocabulary_publish",
      "graft_vocabulary_read"
    )
  )
})
