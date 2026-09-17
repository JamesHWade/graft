test_that("real Tempest admits exact initial and corrected artifact evidence", {
  fixture <- reuse_fixture
  for (name in c("initial", "correction")) {
    input <- fixture$inputs[[name]]
    observed <- fixture$consumer[[name]]
    expect_identical(
      observed$selection,
      tempest::tempest_artifact_knowledge(
        input$selection,
        input$contents
      )@artifact_selection
    )
    expect_equal(nrow(observed$sources), 4L)
    expect_identical(observed$no_native_view, TRUE)
    expect_setequal(
      observed$sources$content,
      unlist(input$contents, use.names = FALSE)
    )
    expect_identical(
      reuse_order_object_members(observed$selection$provenance$source_receipt),
      reuse_order_object_members(fixture$export$receipts[[name]])
    )
    expect_setequal(
      vapply(
        observed$selection$records,
        \(ref) ref$revision_id,
        character(1)
      ),
      vapply(
        observed$selection$provenance$artifact_map,
        \(ref) ref$revision,
        character(1)
      )
    )
  }
  expect_identical(fixture$graft_available, FALSE)
  expect_identical(fixture$graft_loaded, FALSE)
  expect_match(
    paste(fixture$consumer$initial$sources$content, collapse = "\n"),
    "82%",
    fixed = TRUE
  )
  expect_match(
    paste(fixture$consumer$correction$sources$content, collapse = "\n"),
    "62%",
    fixed = TRUE
  )
  expect_identical(
    fixture$consumer$initial$selection,
    fixture$consumer$unchanged$selection
  )
  expect_identical(
    fixture$consumer$initial$sources$content,
    fixture$consumer$unchanged$sources$content
  )
})

test_that("the host checks purpose and withdrawal before Tempest admission", {
  fixture <- reuse_fixture
  expect_error(
    reuse_input(fixture$target, fixture$historical_handle, "initial"),
    "not eligible",
    class = "artifact_experiment_error"
  )
  path <- file.path(fixture$sessions, "initial")
  expect_error(
    reuse_resume(path, NULL, fixture$target, fixture$handle, "correction"),
    "differs from the currently eligible selection",
    class = "artifact_experiment_error"
  )
  expect_error(
    reuse_resume(
      path,
      NULL,
      fixture$target,
      fixture$historical_handle,
      "initial"
    ),
    "not eligible",
    class = "artifact_experiment_error"
  )
  store <- artifact_store(fixture$target, "manifest", "unused")
  artifact_revoke(store, fixture$handle$basis)
  expect_error(
    reuse_resume(path, NULL, fixture$target, fixture$handle, "initial"),
    "not eligible",
    class = "artifact_experiment_error"
  )
  expect_error(
    reuse_input(fixture$target, fixture$handle, "initial"),
    "not eligible",
    class = "artifact_experiment_error"
  )
  expect_error(
    reuse_input(fixture$target, fixture$handle, "correction"),
    "not eligible",
    class = "artifact_experiment_error"
  )
  historical <- migration_read(
    fixture$target,
    fixture$historical_handle,
    "initial"
  )
  expect_identical(
    historical$report_md,
    fixture$export$checkpoints$initial$report_md
  )
})

test_that("incomplete contents and revision substitutions fail at the public input", {
  input <- reuse_fixture$inputs$initial
  altered <- input
  altered$contents <- altered$contents[-1L]
  expect_error(
    do.call(tempest::tempest_artifact_knowledge, altered),
    "exactly once",
    class = "tempest_knowledge_error"
  )
  altered <- input
  altered$contents[[1L]] <- "Changed content"
  expect_error(
    do.call(tempest::tempest_artifact_knowledge, altered),
    "SHA-256",
    class = "tempest_knowledge_error"
  )
  altered <- input
  support <- which(vapply(
    altered$selection$records,
    \(ref) ref$class == "ClaimSupport",
    logical(1)
  ))
  altered$selection$records[[support]]$dependencies[[
    1L
  ]]$revision_id <- "changed-revision"
  expect_error(
    do.call(tempest::tempest_artifact_knowledge, altered),
    "exact dependency",
    class = "tempest_knowledge_error"
  )
})
