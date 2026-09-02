changes_fixture_store <- function(env = parent.frame()) {
  store <- local_graft_ingest_store(env = env)
  fixture <- retrieval_fixture_records()
  graft_ingest(
    store,
    fixture$records,
    graft_provenance("changes-fixture", idempotency_key = "changes-1")
  )
  first <- graft_snapshot(store)
  revised <- fixture$records
  revised$Claim$statement_text[[1L]] <- "Polyethylene remains very durable."
  revised$Claim <- rbind(
    revised$Claim,
    data.frame(
      id = test_graft_id("changes-new-claim"),
      statement_text = "Polyethylene resists moisture.",
      primary_subject = fixture$ids$entity,
      claim_type = "finding",
      importance = "medium",
      polarity = "positive",
      status = "active",
      superseded_by = NA_character_,
      about = I(list(fixture$ids$entity))
    )
  )
  graft_ingest(
    store,
    revised,
    graft_provenance("changes-fixture", idempotency_key = "changes-2")
  )
  second <- graft_snapshot(store)
  revised$Claim$importance[[1L]] <- "medium"
  graft_ingest(
    store,
    revised,
    graft_provenance("changes-fixture", idempotency_key = "changes-3")
  )
  list(
    store = store,
    ids = fixture$ids,
    first = first,
    second = second,
    third = graft_snapshot(store)
  )
}

test_that("graft_changes reports records accepted since a snapshot", {
  fixture <- changes_fixture_store()
  columns <- c(
    "class",
    "record_id",
    "action",
    "revisions",
    "changed_fields",
    "revision_id",
    "revision_number",
    "batch_id",
    "commit_order",
    "committed_at",
    "record"
  )

  changes <- graft_changes(fixture$store, since = fixture$first)

  expect_identical(names(changes), columns)
  expect_identical(changes$class, c("Claim", "Claim"))
  expect_identical(
    changes$record_id,
    sort(
      c(fixture$ids$active_claim, test_graft_id("changes-new-claim")),
      method = "radix"
    )
  )
  active <- changes[changes$record_id == fixture$ids$active_claim, ]
  added <- changes[changes$record_id != fixture$ids$active_claim, ]
  expect_identical(active$action, "update")
  expect_identical(active$revisions, 2L)
  expect_identical(
    active$changed_fields[[1L]],
    c("importance", "statement_text")
  )
  expect_identical(active$revision_number, 3)
  expect_identical(
    active$record[[1L]]$statement_text,
    "Polyethylene remains very durable."
  )
  expect_identical(added$action, "insert")
  expect_identical(added$revisions, 1L)
  expect_identical(added$revision_number, 1)
  expect_identical(
    attr(changes, "since_commit_order"),
    fixture$first@commit_order
  )
  expect_identical(attr(changes, "since_batch_id"), fixture$first@batch_id)
  expect_identical(
    attr(changes, "until_commit_order"),
    fixture$third@commit_order
  )
  expect_identical(attr(changes, "until_batch_id"), fixture$third@batch_id)
  expect_identical(attr(changes, "truncated"), FALSE)
})

test_that("graft_changes bounds the window with until, views, and classes", {
  fixture <- changes_fixture_store()

  bounded <- graft_changes(
    fixture$store,
    since = fixture$first,
    until = fixture$second
  )
  expect_identical(nrow(bounded), 2L)
  expect_identical(
    bounded$revisions[bounded$record_id == fixture$ids$active_claim],
    1L
  )
  expect_identical(
    bounded$changed_fields[[which(
      bounded$record_id == fixture$ids$active_claim
    )]],
    "statement_text"
  )

  view <- graft_at(fixture$store, fixture$second)
  expect_identical(
    graft_changes(view, since = fixture$first)$revision_id,
    bounded$revision_id
  )
  expect_identical(
    graft_changes(view, since = fixture$first@batch_id)$revision_id,
    bounded$revision_id
  )

  everything <- graft_changes(fixture$store, until = fixture$first)
  expect_identical(unique(everything$action), "insert")
  expect_identical(nrow(everything), 10L)
  expect_identical(attr(everything, "since_batch_id"), NA_character_)

  entities <- graft_changes(
    fixture$store,
    until = fixture$first,
    class = "Entity"
  )
  expect_identical(unique(entities$class), "Entity")
  expect_identical(nrow(entities), 2L)

  limited <- graft_changes(fixture$store, until = fixture$first, limit = 3L)
  expect_identical(nrow(limited), 3L)
  expect_identical(attr(limited, "truncated"), TRUE)
  expect_identical(attr(limited, "limit"), 3L)

  none <- graft_changes(
    fixture$store,
    since = fixture$third,
    until = fixture$third
  )
  expect_identical(nrow(none), 0L)
  expect_identical(names(none), names(everything))
})

test_that("graft_changes rejects inverted, foreign, and late boundaries", {
  fixture <- changes_fixture_store()

  expect_error(
    graft_changes(fixture$store, since = fixture$third, until = fixture$first),
    class = "graft_validation_error"
  )
  expect_error(
    graft_changes(fixture$store, class = "Missing"),
    class = "graft_validation_error"
  )
  view <- graft_at(fixture$store, fixture$first)
  expect_error(
    graft_changes(view, until = fixture$second),
    class = "graft_snapshot_boundary_error"
  )
  other <- local_graft_ingest_store()
  expect_error(
    graft_changes(fixture$store, since = graft_snapshot(other)),
    class = "graft_snapshot_store_error"
  )
})
