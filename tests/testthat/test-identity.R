test_that("entity and source identifiers reconcile exactly", {
  store <- local_ingest_store()
  first <- kg_ingest(
    store,
    kg_batch("tempest", idempotency_key = "identity-1"),
    list(
      Entity = data.frame(
        preferred_name = "Water",
        inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
      ),
      Source = data.frame(
        title = "Paper",
        doi = "https://doi.org/10.1000/GRAFT"
      )
    )
  )
  first_entity <- DBI::dbReadTable(store$connection, "entity")$id
  first_source <- DBI::dbReadTable(store$connection, "source")$id

  second <- kg_ingest(
    store,
    kg_batch("another-producer", idempotency_key = "identity-2"),
    list(
      Entity = data.frame(
        preferred_name = "Water updated",
        inchikey = "xlyofnoqvpjjnp-uhfffaoysa-n"
      ),
      Source = data.frame(
        title = "Paper updated",
        doi = "DOI:10.1000/graft"
      )
    )
  )

  expect_identical(second$updated, c(Entity = 1L, Source = 1L))
  expect_identical(
    DBI::dbReadTable(store$connection, "entity")$id,
    first_entity
  )
  expect_identical(
    DBI::dbReadTable(store$connection, "source")$id,
    first_source
  )
  expect_identical(sum(first$inserted), 2L)
  expect_equal(
    nrow(DBI::dbReadTable(store$connection, "_graft_identifiers")),
    2L
  )
})

test_that("conflicting exact identifiers fail without mutation", {
  store <- local_ingest_store()
  id_one <- test_graft_id("conflict-one")
  id_two <- test_graft_id("conflict-two")
  kg_write(
    store,
    kg_batch("tempest", idempotency_key = "conflict-1"),
    "Entity",
    data.frame(
      id = id_one,
      preferred_name = "One",
      inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
    )
  )
  kg_write(
    store,
    kg_batch("tempest", idempotency_key = "conflict-2"),
    "Entity",
    data.frame(
      id = id_two,
      preferred_name = "Two",
      cas_number = "50-00-0"
    )
  )
  before <- DBI::dbReadTable(store$connection, "_graft_identifiers")

  condition <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "conflict-3"),
      "Entity",
      data.frame(
        preferred_name = "Conflict",
        inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
        cas_number = "CAS: 50-00-0"
      )
    )
  )

  expect_s3_class(condition, "graft_identity_error")
  expect_identical(condition$rule, "consistent_exact_identity")
  expect_equal(nrow(DBI::dbReadTable(store$connection, "entity")), 2L)
  expect_identical(
    DBI::dbReadTable(store$connection, "_graft_identifiers"),
    before
  )
})

test_that("an internal ID cannot conflict with exact identity", {
  store <- local_ingest_store()
  existing_id <- test_graft_id("existing-identity")
  kg_write(
    store,
    kg_batch("tempest", idempotency_key = "internal-1"),
    "Entity",
    data.frame(
      id = existing_id,
      preferred_name = "Existing",
      cas_number = "50-00-0"
    )
  )

  condition <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("tempest", idempotency_key = "internal-2"),
      "Entity",
      data.frame(
        id = test_graft_id("new-identity"),
        preferred_name = "Conflicting",
        cas_number = "50-00-0"
      )
    )
  )

  expect_s3_class(condition, "graft_identity_error")
  expect_identical(condition$rule, "internal_external_identity_agreement")
})

test_that("authoritative ingestion promotes a candidate identifier", {
  store <- local_ingest_store()
  candidate_record_id <- test_graft_id("candidate-record")
  kg_write(
    store,
    kg_batch("seed", idempotency_key = "candidate-record"),
    "Entity",
    data.frame(
      id = candidate_record_id,
      preferred_name = "Candidate record"
    )
  )
  candidate_created_at <- as.POSIXct(
    "2025-01-01 00:00:00",
    tz = "UTC"
  )
  DBI::dbAppendTable(
    store$connection,
    "_graft_identifiers",
    data.frame(
      record_id = candidate_record_id,
      class = "Entity",
      namespace = "cas",
      value = "50-00-0",
      normalized_value = "50-00-0",
      status = "candidate",
      assigned_by = "resolver",
      confidence = 0.4,
      created_at = candidate_created_at,
      stringsAsFactors = FALSE
    )
  )

  result <- kg_write(
    store,
    kg_batch("authoritative", idempotency_key = "promote-candidate"),
    "Entity",
    data.frame(
      preferred_name = "Authoritative record",
      cas_number = "CAS: 50-00-0"
    )
  )
  entities <- DBI::dbReadTable(store$connection, "entity")
  registry <- DBI::dbReadTable(store$connection, "_graft_identifiers")
  authoritative_id <- setdiff(entities$id, candidate_record_id)

  expect_identical(result$inserted[["Entity"]], 1L)
  expect_length(authoritative_id, 1L)
  expect_identical(registry$record_id, authoritative_id)
  expect_identical(registry$status, "primary")
  expect_identical(registry$value, "CAS: 50-00-0")
  expect_identical(registry$assigned_by, "authoritative")
  expect_identical(registry$confidence, 1)
  expect_gt(registry$created_at, candidate_created_at)
})

test_that("deterministic identity is stable and valid", {
  store <- local_ingest_store()
  first <- kg_write(
    store,
    kg_batch("tempest", idempotency_key = "run-det-1"),
    "Run",
    data.frame(run_identifier = "stable-run", name = "First")
  )
  record <- DBI::dbReadTable(store$connection, "run")

  second <- kg_write(
    store,
    kg_batch("other", idempotency_key = "run-det-2"),
    "Run",
    data.frame(run_identifier = "stable-run", name = "Second")
  )
  updated <- DBI::dbReadTable(store$connection, "run")

  expect_match(record$id, graft_id_pattern)
  expect_identical(updated$id, record$id)
  expect_identical(first$inserted[["Run"]], 1L)
  expect_identical(second$updated[["Run"]], 1L)
})
