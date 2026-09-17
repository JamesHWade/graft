test_that("real Tempest admits exact initial and corrected artifact evidence", {
  fixture <- reuse_fixture
  for (name in c("initial", "unchanged", "correction")) {
    checkpoint <- name
    input <- fixture$inputs[[checkpoint]]
    observed <- fixture$consumer[[name]]
    expected_selection <- input$selection
    ids <- vapply(
      expected_selection$records,
      \(ref) ref$record_id,
      character(1)
    )
    expected_selection$records <- expected_selection$records[order(
      ids,
      method = "radix"
    )]
    expect_identical(
      observed$selection,
      reuse_order_object_members(expected_selection)
    )
    expect_equal(nrow(observed$sources), 4L)
    expect_identical(fixture$saved[[name]]$no_native_view, TRUE)
    expect_identical(observed$sources, fixture$saved[[name]]$sources)
    expect_identical(observed$selection, fixture$saved[[name]]$selection)
    bindings <- reuse_source_bindings(observed$sources)
    expected <- lapply(input$selection$records, function(ref) {
      list(
        record_id = ref$record_id,
        revision_id = ref$revision_id,
        class = ref$class,
        content = input$contents[[ref$record_id]]
      )
    })
    names(expected) <- vapply(expected, \(ref) ref$record_id, character(1))
    expect_identical(
      bindings[order(names(bindings), method = "radix")],
      expected[order(names(expected), method = "radix")]
    )
    expect_length(unique(observed$sources[["id"]]), length(expected))
    expect_identical(
      reuse_order_object_members(observed$selection$provenance$source_receipt),
      reuse_order_object_members(fixture$export$receipts[[checkpoint]])
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
  expect_length(
    unique(c(
      fixture$save_process$process_id,
      fixture$resume_process$process_id
    )),
    2L
  )
  expect_identical(fixture$save_process$graft_available, FALSE)
  expect_identical(fixture$save_process$graft_loaded, FALSE)
  expect_identical(fixture$graft_available, FALSE)
  expect_identical(fixture$graft_loaded, FALSE)
  expect_match(
    paste(fixture$consumer$initial$sources[["content_text"]], collapse = "\n"),
    "82%",
    fixed = TRUE
  )
  expect_match(
    paste(
      fixture$consumer$correction$sources[["content_text"]],
      collapse = "\n"
    ),
    "62%",
    fixed = TRUE
  )
  expect_identical(
    fixture$consumer$initial$selection$records,
    fixture$consumer$unchanged$selection$records
  )
  expect_identical(
    fixture$consumer$unchanged$selection$provenance$source_snapshot,
    reuse_order_object_members(fixture$export$receipts$unchanged$snapshot)
  )
  expect_length(
    unique(c(
      fixture$consumer$initial$selection$provenance$source_receipt$receipt_id,
      fixture$consumer$unchanged$selection$provenance$source_receipt$receipt_id
    )),
    2L
  )
  expect_identical(
    fixture$consumer$initial$sources[["content_text"]],
    fixture$consumer$unchanged$sources[["content_text"]]
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
