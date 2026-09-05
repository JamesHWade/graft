test_that("consultation refuses when access or eligibility changes between checks", {
  skip_if_not_installed("ellmer", minimum_version = "0.5.0")
  store <- local_narrative_store()
  basis <- capture_consumer_basis(store)
  example <- reuse_example()
  for (policy in c("access", "eligibility")) {
    calls <- 0L
    revoke_during_read <- function(selection) {
      calls <<- calls + 1L
      calls == 1L
    }
    tool <- example$reuse_consultation_tool(
      store,
      basis,
      if (policy == "access") revoke_during_read else \(ids) TRUE,
      if (policy == "eligibility") revoke_during_read else \(basis) TRUE
    )
    result <- "not returned"
    expect_snapshot(error = TRUE, result <- tool())
    expect_identical(result, "not returned", info = policy)
    expect_identical(calls, 2L, info = policy)
  }
  tool <- example$reuse_consultation_tool(store, basis, \(ids) TRUE, \(basis) {
    TRUE
  })
  expect_named(jsonlite::fromJSON(tool()), basis$records$record_id)
})

test_that("a real agent cannot consult a bundle whose eligibility was revoked", {
  skip_if_not_installed("ellmer", minimum_version = "0.5.0")
  store <- local_narrative_store()
  basis <- capture_consumer_basis(store)
  allowed <- TRUE
  tool <- reuse_example()$reuse_consultation_tool(
    store,
    basis,
    \(ids) TRUE,
    \(basis) allowed
  )
  tools <- list(consult_selected_knowledge = tool)
  server <- local_host_responses(
    list(list(
      name = "consult_selected_knowledge",
      arguments = list()
    )),
    "No accepted knowledge was available."
  )
  chat <- host_chat(server)
  chat$set_tools(tools)
  allowed <- FALSE
  expect_warning(
    chat$chat("Consult the selected knowledge.", echo = "none"),
    class = "ellmer_tool_failure"
  )
  expect_identical(names(chat$get_tools()), "consult_selected_knowledge")
  expect_identical(
    grepl(
      "café|lower temperature|morning",
      canonical_json(host_result_values(chat))
    ),
    FALSE
  )
  expect_identical(graft_verify(chat)$label[[1L]], "untrusted")
})

test_that("correction conflicts and retries preserve the accepted identity", {
  store <- local_narrative_store()
  basis <- capture_consumer_basis(store)
  example <- reuse_example()
  original <- example$read_reuse_basis(store, basis, \(ids) TRUE)
  record <- narrative_fixture()$narrative_records()$knowledge[
    2L,
    ,
    drop = FALSE
  ]
  record$body <- "First proposed correction."
  first <- graft_plan(
    store,
    list(knowledge = record),
    graft_provenance("reader", idempotency_key = "first-correction")
  )
  record$body <- "Conflicting proposed correction."
  conflicting <- graft_plan(
    store,
    list(knowledge = record),
    graft_provenance("reader", idempotency_key = "second-correction")
  )
  graft_commit(store, first)
  accepted <- graft_snapshot(store)
  graft_commit(store, first)
  expect_identical(graft_snapshot(store), accepted)
  expect_error(
    graft_commit(store, conflicting),
    class = "graft_commit_plan_stale"
  )
  expect_equal(nrow(graft_history(store, record$id)), 2L)
  expect_identical(
    graft_get(store, record$id)$record$body,
    "First proposed correction."
  )
  expect_identical(
    example$read_reuse_basis(store, basis, \(ids) TRUE),
    original
  )
  expect_identical(
    example$review_reuse_basis(store, basis)$needs_review,
    "knowledge:interpretation"
  )
})
