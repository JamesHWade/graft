test_that("graft_tools lists only eligible accepted streams and recalls safely", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)

  active_ref <- graft_save(store, "Active = paid + 30d.", id = "active")
  churn_ref <- graft_save(store, "Churn = canceled in month.", id = "churn")
  secret_ref <- graft_save(store, "Secret HR rule.", id = "secret")
  other_ref <- graft_save(store, "Internal deploy note.", id = "deploy")

  graft_accept(
    store,
    active_ref,
    stream = "metric:active-customer",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Active metric reviewed",
    purpose = "project-assistance"
  )
  churn_accepted <- graft_accept(
    store,
    churn_ref,
    stream = "metric:churn",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Churn metric reviewed",
    purpose = "project-assistance"
  )
  graft_withdraw(
    store,
    stream = "metric:churn",
    expected = churn_accepted,
    key = "w1",
    actor = "reviewer",
    reason = "Needs revision"
  )
  graft_accept(
    store,
    secret_ref,
    stream = "hr:compensation",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "HR only",
    purpose = "project-assistance"
  )
  graft_accept(
    store,
    other_ref,
    stream = "ops:deploy",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Ops purpose",
    purpose = "ops-runbook"
  )

  allowed_streams <- c(
    "metric:active-customer",
    "metric:churn",
    "hr:compensation"
  )
  tools <- graft_tools(
    store,
    purpose = "project-assistance",
    eligible = function(stream) !identical(stream, "hr:compensation"),
    streams = allowed_streams
  )

  expect_identical(
    names(tools),
    c("list_project_memory", "recall_project_memory")
  )
  expect_identical(tools$list_project_memory@annotations$read_only_hint, TRUE)
  expect_identical(tools$recall_project_memory@annotations$read_only_hint, TRUE)

  listed <- tools$list_project_memory()
  list_payload <- jsonlite::fromJSON(listed@value, simplifyVector = FALSE)
  expect_identical(list_payload$count, 1L)
  expect_identical(list_payload$truncated, FALSE)
  expect_identical(
    list_payload$streams[[1L]]$stream,
    "metric:active-customer"
  )
  expect_identical(listed@extra$graft$action, "list")
  expect_identical(listed@extra$graft$streams, "metric:active-customer")
  expect_identical(grepl("hr:compensation", listed@value, fixed = TRUE), FALSE)
  expect_identical(grepl("metric:churn", listed@value, fixed = TRUE), FALSE)
  expect_identical(grepl("ops:deploy", listed@value, fixed = TRUE), FALSE)

  recalled <- tools$recall_project_memory(stream = "metric:active-customer")
  recall_payload <- jsonlite::fromJSON(recalled@value, simplifyVector = FALSE)
  expect_identical(recall_payload$status, "accepted")
  expect_identical(recall_payload$artifacts[[1L]]$data, "Active = paid + 30d.")
  expect_identical(recalled@extra$graft$status, "accepted")
  expect_identical(recalled@extra$graft$stream, "metric:active-customer")
})

test_that("graft_tools rejects unlisted and ineligible streams identically", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  public_ref <- graft_save(store, "Public note", id = "public")
  hidden_ref <- graft_save(store, "Hidden note", id = "hidden")

  graft_accept(
    store,
    public_ref,
    stream = "public",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Reviewed",
    purpose = "assist"
  )
  graft_accept(
    store,
    hidden_ref,
    stream = "hidden",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Reviewed",
    purpose = "assist"
  )

  tools <- graft_tools(
    store,
    purpose = "assist",
    eligible = function(stream) identical(stream, "public"),
    streams = c("public", "denied-listed")
  )

  unlisted_err <- tryCatch(
    tools$recall_project_memory(stream = "hidden"),
    error = identity
  )
  ineligible_err <- tryCatch(
    tools$recall_project_memory(stream = "denied-listed"),
    error = identity
  )
  nonexistent_err <- tryCatch(
    tools$recall_project_memory(stream = "does-not-exist"),
    error = identity
  )

  expect_s3_class(unlisted_err, "graft_ineligible_error")
  expect_s3_class(ineligible_err, "graft_ineligible_error")
  expect_s3_class(nonexistent_err, "graft_ineligible_error")
  expect_identical(
    conditionMessage(unlisted_err),
    conditionMessage(ineligible_err)
  )
  expect_identical(
    conditionMessage(unlisted_err),
    conditionMessage(nonexistent_err)
  )
  expect_identical(
    grepl("Hidden note", conditionMessage(unlisted_err), fixed = TRUE),
    FALSE
  )
})

test_that("graft_tools discovers dynamic streams and bounds text previews", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  first_ref <- graft_save(store, "First reviewed definition", id = "first")
  second_ref <- graft_save(store, "Second reviewed definition", id = "second")

  graft_accept(
    store,
    first_ref,
    stream = "alpha",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "First",
    purpose = "assist"
  )
  graft_accept(
    store,
    second_ref,
    stream = "beta",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Second",
    purpose = "assist"
  )

  tools <- graft_tools(
    store,
    purpose = "assist",
    eligible = function(stream) TRUE,
    max_text_bytes = 5L
  )

  listed <- jsonlite::fromJSON(
    tools$list_project_memory()@value,
    simplifyVector = FALSE
  )
  expect_identical(
    vapply(listed$streams, `[[`, character(1), "stream"),
    c("alpha", "beta")
  )

  recalled <- tools$recall_project_memory(stream = "alpha")
  payload <- jsonlite::fromJSON(recalled@value, simplifyVector = FALSE)
  expect_identical(payload$artifacts[[1L]]$data, "First")
  expect_identical(payload$truncated, TRUE)
  expect_identical(recalled@extra$graft$truncated, TRUE)
})

test_that("graft_tools applies max_streams after filtering when discovering streams", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  ref <- graft_save(store, "Reviewed note", id = "note")

  withdrawn_acc <- graft_accept(
    store,
    ref,
    stream = "a:withdrawn",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Initial",
    purpose = "assist"
  )
  graft_withdraw(
    store,
    stream = "a:withdrawn",
    expected = withdrawn_acc,
    key = "w1",
    actor = "reviewer",
    reason = "Withdrawn"
  )
  graft_accept(
    store,
    ref,
    stream = "b:ineligible",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Ineligible",
    purpose = "assist"
  )
  graft_accept(
    store,
    ref,
    stream = "c:eligible-1",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "First eligible",
    purpose = "assist"
  )
  graft_accept(
    store,
    ref,
    stream = "d:eligible-2",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Second eligible",
    purpose = "assist"
  )

  tools <- graft_tools(
    store,
    purpose = "assist",
    eligible = function(stream) !identical(stream, "b:ineligible"),
    max_streams = 1L
  )
  listed <- tools$list_project_memory()
  payload <- jsonlite::fromJSON(listed@value, simplifyVector = FALSE)

  expect_identical(payload$count, 1L)
  expect_identical(payload$truncated, TRUE)
  expect_identical(payload$streams[[1L]]$stream, "c:eligible-1")
  expect_identical(listed@extra$graft$truncated, TRUE)
  expect_identical(listed@extra$graft$streams, "c:eligible-1")
})

test_that("stale search index hit on a withdrawn or corrected stream cannot leak stale memory", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)

  v1 <- graft_save(store, "Active window is 30 days.", id = "active")
  d1 <- graft_accept(
    store,
    v1,
    stream = "metric:active-customer",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Initial",
    purpose = "assist"
  )
  retired_ref <- graft_save(store, "Legacy retention rule.", id = "legacy")
  d_legacy <- graft_accept(
    store,
    retired_ref,
    stream = "metric:legacy",
    expected = NULL,
    key = "r1",
    actor = "reviewer",
    reason = "Initial legacy",
    purpose = "assist"
  )

  # Simulated search index (e.g., ragnar) captured at t1.
  stale_index <- data.frame(
    stream = c("metric:active-customer", "metric:legacy"),
    revision = c(v1@revision, retired_ref@revision),
    text = c("Active window is 30 days.", "Legacy retention rule."),
    stringsAsFactors = FALSE
  )

  # Later: active-customer is corrected to 60 days; legacy is withdrawn.
  v2 <- graft_save(store, "Active window is 60 days.", id = "active")
  d2 <- graft_accept(
    store,
    v2,
    stream = "metric:active-customer",
    expected = d1,
    key = "r2",
    actor = "reviewer",
    reason = "Updated to 60 days",
    purpose = "assist"
  )
  graft_withdraw(
    store,
    stream = "metric:legacy",
    expected = d_legacy,
    key = "w1",
    actor = "reviewer",
    reason = "Retired"
  )

  # Passing stale index hits through graft_recall() / graft_tools() verifies
  # current status instead of trusting indexed text.
  tools <- graft_tools(
    store,
    purpose = "assist",
    eligible = function(stream) TRUE
  )

  corrected_hit <- tools$recall_project_memory(
    stream = stale_index$stream[[1L]]
  )
  corrected_payload <- jsonlite::fromJSON(
    corrected_hit@value,
    simplifyVector = FALSE
  )
  expect_identical(corrected_payload$status, "accepted")
  expect_identical(corrected_payload$decision_id, d2@id)
  expect_identical(
    corrected_payload$artifacts[[1L]]$data,
    "Active window is 60 days."
  )

  withdrawn_hit <- tools$recall_project_memory(
    stream = stale_index$stream[[2L]]
  )
  withdrawn_payload <- jsonlite::fromJSON(
    withdrawn_hit@value,
    simplifyVector = FALSE
  )
  expect_identical(withdrawn_payload$status, "withdrawn")
  expect_null(withdrawn_payload$artifacts)
  expect_identical(
    grepl("Legacy retention rule", withdrawn_hit@value, fixed = TRUE),
    FALSE
  )
})

test_that("graft_tools validates arguments cleanly", {
  skip_if_not_installed("ellmer")

  store <- graft_store(withr::local_tempdir(), create = TRUE)
  expect_error(
    graft_tools(store, purpose = "assist", eligible = function() TRUE),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_tools(
      store,
      purpose = "assist",
      eligible = function(stream) TRUE,
      list_name = "same",
      recall_name = "same"
    ),
    class = "graft_artifact_error"
  )
  expect_error(
    graft_tools(
      store,
      purpose = "assist",
      eligible = function(stream) TRUE,
      streams = 123
    ),
    class = "graft_artifact_error"
  )
})

test_that("graft_tools validates store on empty allowlist and formats recall description cleanly", {
  skip_if_not_installed("ellmer")

  path <- withr::local_tempdir()
  store <- graft_store(path, create = TRUE)
  tools <- graft_tools(
    store,
    purpose = "assist",
    eligible = function(stream) TRUE,
    streams = character()
  )
  expect_identical(
    grepl(" . ", tools$recall_project_memory@description, fixed = TRUE),
    FALSE
  )
  unlink(file.path(path, "store.json"))
  expect_error(
    tools$list_project_memory(),
    class = "graft_artifact_error"
  )
})
