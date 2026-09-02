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
