test_that("consumer contract names only retained formats", {
  expect_identical(
    graft_contract_version(),
    list(
      contract = "4.2.0",
      artifact = "1",
      manifest = "graft-artifact-manifest/1",
      replacement = "graft-artifact-replacement/1",
      backup = "graft-artifact-backup/1",
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
      "ArtifactStore",
      "LocalArtifactStore",
      "PostgresArtifactStore",
      "ArtifactRef",
      "Artifact",
      "ArtifactSelection",
      "Decision",
      "Recall",
      "VocabularyRelease",
      "graft_contract_version",
      "graft_store",
      "graft_store_postgres",
      "graft_save",
      "graft_save_file",
      "graft_read",
      "graft_select",
      "graft_read_selection",
      "graft_accept",
      "graft_withdraw",
      "graft_recall",
      "graft_history",
      "graft_streams",
      "graft_with_store_lock",
      "graft_tool",
      "graft_publish_vocabulary",
      "graft_read_vocabulary",
      "graft_manifest",
      "graft_backup",
      "graft_verify_backup",
      "graft_restore",
      "graft_plan_replacement",
      "graft_replace"
    )
  )
})
