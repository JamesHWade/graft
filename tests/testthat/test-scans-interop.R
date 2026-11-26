test_that("graft_tool attaches plain-data @extra$graft metadata for all states", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  tool <- graft_tool(
    store,
    stream = "metric:active-customer",
    purpose = "project-assistance",
    eligible = function() TRUE
  )

  missing_meta <- tool()@extra$graft
  expect_identical(missing_meta$status, "missing")
  expect_identical(missing_meta$stream, "metric:active-customer")
  expect_identical(missing_meta$purpose, "project-assistance")
  expect_null(missing_meta$decision_id)
  expect_null(missing_meta$selection_id)
  expect_identical(missing_meta$root_refs, list())
  expect_identical(missing_meta$artifact_refs, list())
  expect_identical(missing_meta$artifact_count, 0L)
  expect_identical(missing_meta$text_bytes, 0L)
  expect_identical(missing_meta$truncated, FALSE)
  expect_identical(missing_meta$omitted_refs, list())
  expect_identical(missing_meta$omitted_count, 0L)

  source_ref <- graft_save(
    store,
    "Secret handbook body",
    id = "handbook",
    media_type = "text/plain"
  )
  note_ref <- graft_save(
    store,
    "Reviewed definition text",
    id = "metric:active-customer",
    media_type = "text/plain",
    dependencies = source_ref
  )
  accepted <- graft_accept(
    store,
    note_ref,
    stream = "metric:active-customer",
    expected = NULL,
    key = "review-1",
    actor = "reviewer",
    reason = "Checked",
    purpose = "project-assistance"
  )

  accepted_meta <- tool()@extra$graft
  expect_identical(accepted_meta$status, "accepted")
  expect_identical(accepted_meta$decision_id, accepted@id)
  expect_identical(accepted_meta$selection_id, accepted@selection)
  expect_identical(accepted_meta$artifact_count, 2L)
  expect_identical(
    accepted_meta$root_refs,
    list(list(id = note_ref@id, revision = note_ref@revision))
  )
  expect_identical(
    vapply(accepted_meta$artifact_refs, `[[`, character(1), "id"),
    c("metric:active-customer", "handbook")
  )
  expect_identical(accepted_meta$truncated, FALSE)
  expect_identical(accepted_meta$omitted_count, 0L)
  expect_gt(accepted_meta$text_bytes, 0L)

  encoded <- jsonlite::toJSON(accepted_meta, auto_unbox = TRUE, null = "null")
  expect_identical(grepl(path, encoded, fixed = TRUE), FALSE)
  expect_identical(grepl("Secret handbook body", encoded, fixed = TRUE), FALSE)
  expect_identical(
    grepl("Reviewed definition text", encoded, fixed = TRUE),
    FALSE
  )

  withdrawn <- graft_withdraw(
    store,
    stream = "metric:active-customer",
    expected = accepted,
    key = "withdraw-1",
    actor = "reviewer",
    reason = "Superseded"
  )
  withdrawn_meta <- tool()@extra$graft
  expect_identical(withdrawn_meta$status, "withdrawn")
  expect_identical(withdrawn_meta$decision_id, withdrawn@id)
  expect_null(withdrawn_meta$selection_id)
  expect_identical(withdrawn_meta$artifact_count, 0L)
  expect_identical(withdrawn_meta$truncated, FALSE)
  expect_identical(withdrawn_meta$omitted_count, 0L)
})

test_that("@extra$graft records truncation and omitted references accurately", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  binary_ref <- graft_save(
    store,
    as.raw(1:6),
    id = "plot.png",
    media_type = "image/png"
  )
  note_ref <- graft_save(
    store,
    "Long reviewed note that exceeds the preview limit.",
    id = "note",
    media_type = "text/plain",
    dependencies = binary_ref
  )
  graft_accept(
    store,
    note_ref,
    stream = "note",
    expected = NULL,
    key = "review-1",
    actor = "reviewer",
    reason = "Checked",
    purpose = "project-assistance"
  )

  tool <- graft_tool(
    store,
    stream = "note",
    purpose = "project-assistance",
    eligible = function() TRUE,
    max_text_bytes = 8L
  )
  meta <- tool()@extra$graft
  expect_identical(meta$status, "accepted")
  expect_identical(meta$artifact_count, 2L)
  expect_identical(meta$text_bytes, 8L)
  expect_identical(meta$truncated, TRUE)
  expect_identical(meta$omitted_count, 1L)
  expect_identical(
    meta$omitted_refs,
    list(list(id = binary_ref@id, revision = binary_ref@revision))
  )
})

test_that("graft persists a scans investigation and links promoted memory", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)

  investigation_json <- jsonlite::toJSON(
    list(
      application = "Analytics assistant",
      manifest = list(
        snapshot_id = "inv-snap-001",
        revision_id = "inv-rev-001",
        content_policy = "retained-v1"
      ),
      findings = list(
        list(
          trajectory_id = "run-42",
          route_class = "untrusted",
          promotion_candidate = "active_customer_window"
        )
      )
    ),
    auto_unbox = TRUE
  )
  investigation_ref <- graft_save(
    store,
    as.character(investigation_json),
    id = "scans:investigation:inv-snap-001",
    media_type = "application/json"
  )
  promoted_note <- graft_save(
    store,
    "Count paid accounts with product activity in the past 30 days.",
    id = "metric:active-customer",
    media_type = "text/plain",
    dependencies = investigation_ref
  )
  decision <- graft_accept(
    store,
    promoted_note,
    stream = "metric:active-customer",
    expected = NULL,
    key = "promote-from-scans-1",
    actor = "reviewer:alice",
    reason = "Promoted recurring untrusted route from scans investigation inv-snap-001",
    purpose = "project-assistance"
  )

  reopened <- graft_store(path)
  tool <- graft_tool(
    reopened,
    stream = "metric:active-customer",
    purpose = "project-assistance",
    eligible = function() TRUE
  )
  result <- tool()
  meta <- result@extra$graft

  expect_identical(meta$status, "accepted")
  expect_identical(meta$decision_id, decision@id)
  expect_identical(
    vapply(meta$artifact_refs, `[[`, character(1), "id"),
    c("metric:active-customer", "scans:investigation:inv-snap-001")
  )
  expect_identical(
    meta$artifact_refs[[2L]]$revision,
    investigation_ref@revision
  )
})
