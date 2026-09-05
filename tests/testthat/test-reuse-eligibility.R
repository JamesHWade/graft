test_that("Archive and restore change consultation without erasing accepted history", {
  skip_if_not_installed("ellmer", minimum_version = "0.5.0")
  store <- local_narrative_store()
  example <- reuse_example()
  basis <- capture_consumer_basis(store)
  state <- new.env()
  state$epoch <- 1L
  state$allowed <- basis$records$record_id
  state$forgotten <- character()
  allow_read <- function(ids) {
    all(ids %in% state$allowed) && !any(ids %in% state$forgotten)
  }
  eligible <- function(basis) {
    if (state$epoch != 1L) {
      return(FALSE)
    }
    all(vapply(
      basis$roots,
      function(id) {
        identical(
          graft_get(store, id, include = character())$record$lifecycle,
          "active"
        )
      },
      logical(1)
    ))
  }
  tool <- example$reuse_consultation_tool(store, basis, allow_read, eligible)
  expect_identical(tool@name, "consult_selected_knowledge")
  original <- example$read_reuse_basis(store, basis, allow_read)
  expect_named(
    jsonlite::fromJSON(tool(), simplifyVector = FALSE),
    names(original)
  )
  # Policy invalidates the run as well as subsequent tool requests.
  record <- narrative_fixture()$narrative_records()$knowledge[
    2L,
    ,
    drop = FALSE
  ]
  record$lifecycle <- "archived"
  graft_ingest(
    store,
    list(knowledge = record),
    graft_provenance("reader-archive", idempotency_key = "archive")
  )
  expect_snapshot(error = TRUE, tool())
  state$epoch <- 2L
  expect_identical(example$read_reuse_basis(store, basis, allow_read), original)
  expect_identical(graft_get(store, record$id)$record$lifecycle, "archived")
  expect_contains(graft_find(store, "café")$id, record$id)
  record$lifecycle <- "active"
  graft_ingest(
    store,
    list(knowledge = record),
    graft_provenance("reader-restore", idempotency_key = "restore")
  )
  expect_snapshot(error = TRUE, tool())
  # Restore permits a newly authorized run, never resumes the old epoch.
  restored <- example$reuse_consultation_tool(
    store,
    basis,
    allow_read,
    \(basis) state$epoch == 2L
  )
  expect_named(jsonlite::fromJSON(restored()), names(original))
  state$allowed <- setdiff(state$allowed, "source:trial-v1")
  expect_snapshot(error = TRUE, restored())
  state$allowed <- basis$records$record_id
  state$forgotten <- "source:trial-v1"
  expect_snapshot(error = TRUE, restored())
  # Host denial is demonstrated here; retained Graft bytes are not a purge proof.
  expect_identical(
    graft_get(graft_at(store, basis$snapshot), "source:trial-v1")$record,
    original[["source:trial-v1"]]
  )
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

test_that("host-owned supersession rejects cycles and preserves separate identities", {
  store <- local_narrative_store()
  example <- reuse_example()
  basis <- capture_consumer_basis(store)
  old <- basis$roots[[1L]]
  edges <- data.frame(outcome = old, dependency = "knowledge:replacement")
  replacement <- narrative_fixture()$narrative_records()$knowledge[
    2L,
    ,
    drop = FALSE
  ]
  replacement$id <- "knowledge:replacement"
  replacement$body <- "A separately accepted synthesis for a different purpose."
  replacement$purpose <- "later synthesis"
  # Missing targets cannot become a complete host selection.
  expect_error(
    example$capture_reuse_basis(store, old, edges),
    class = "graft_reference_error"
  )
  graft_ingest(
    store,
    list(knowledge = replacement),
    graft_provenance("reader", idempotency_key = "replacement")
  )
  expect_contains(example$reuse_closure(old, edges), c(old, replacement$id))
  cyclic <- rbind(edges, data.frame(outcome = replacement$id, dependency = old))
  expect_snapshot(error = TRUE, example$reuse_closure(old, cyclic))
  expect_identical(
    graft_get(store, replacement$id)$record$purpose,
    "later synthesis"
  )
  expect_identical(
    graft_get(store, old)$record$purpose,
    "reading interpretation"
  )
  # The host excludes the replaced identity; Graft does not infer this edge.
  tool <- example$reuse_consultation_tool(
    store,
    basis,
    \(ids) TRUE,
    \(basis) !any(basis$roots %in% edges$outcome)
  )
  expect_snapshot(error = TRUE, tool())
  expect_equal(nrow(graft_history(store, old)), 1L)
})
