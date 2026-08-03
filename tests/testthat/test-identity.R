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

test_that("authoritative identifiers have one deterministic primary", {
  store <- local_ingest_store()

  graft_ingest(
    store,
    list(
      Entity = data.frame(
        preferred_name = "Water",
        inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
        cas_number = "7732-18-5"
      )
    ),
    graft_provenance("identifier-status")
  )
  registry <- DBI::dbGetQuery(
    store$connection,
    paste0(
      "SELECT namespace, status FROM _graft_identifiers ",
      "ORDER BY namespace"
    )
  )

  expect_identical(registry$namespace, c("cas", "inchikey"))
  expect_identical(registry$status, c("primary", "equivalent"))
})

test_that("a later authoritative identifier is equivalent", {
  store <- local_ingest_store()
  record_id <- test_graft_id("later-identifier")
  provenance <- graft_provenance("identifier-status")

  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = record_id,
        preferred_name = "Water",
        inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
      )
    ),
    provenance
  )
  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = record_id,
        preferred_name = "Water",
        inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
        cas_number = "7732-18-5"
      )
    ),
    provenance
  )
  registry <- DBI::dbGetQuery(
    store$connection,
    paste0(
      "SELECT namespace, status FROM _graft_identifiers ",
      "ORDER BY namespace"
    )
  )

  expect_identical(registry$namespace, c("cas", "inchikey"))
  expect_identical(registry$status, c("equivalent", "primary"))
})

test_that("Source canonical URLs reconcile superficial HTTP variants", {
  store <- local_ingest_store()
  first <- kg_write(
    store,
    kg_batch("tempest", idempotency_key = "canonical-url-1"),
    "Source",
    data.frame(
      title = "First title",
      uri = paste0(
        "HTTPS://WWW.Example.COM:443/reports/Result/",
        "?Study=ABC#overview"
      )
    )
  )
  source_id <- DBI::dbReadTable(store$connection, "source")$id

  second <- kg_write(
    store,
    kg_batch("tempest", idempotency_key = "canonical-url-2"),
    "Source",
    data.frame(
      title = "Updated title",
      uri = "https://example.com/reports/Result?Study=ABC#details"
    )
  )
  registry <- DBI::dbReadTable(store$connection, "_graft_identifiers")

  expect_identical(first$inserted[["Source"]], 1L)
  expect_identical(second$updated[["Source"]], 1L)
  expect_identical(DBI::dbReadTable(store$connection, "source")$id, source_id)
  expect_identical(
    registry$normalized_value,
    "https://example.com/reports/Result?Study=ABC"
  )

  kg_write(
    store,
    kg_batch("tempest", idempotency_key = "canonical-url-path"),
    "Source",
    data.frame(
      title = "Distinct path",
      uri = "https://example.com/reports/result?Study=ABC"
    )
  )
  kg_write(
    store,
    kg_batch("tempest", idempotency_key = "canonical-url-query"),
    "Source",
    data.frame(
      title = "Distinct query",
      uri = "https://example.com/reports/Result?Study=abc"
    )
  )

  expect_equal(nrow(DBI::dbReadTable(store$connection, "source")), 3L)
  expect_identical(
    normalize_external_identifier(
      "canonical_url",
      " HTTP://WWW.Example.COM:80#fragment "
    ),
    "http://example.com/"
  )
  expect_identical(
    normalize_external_identifier("canonical_url", " urn:Example#Fragment "),
    "urn:Example#Fragment"
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
  expect_in(
    "internal_external_identity_agreement",
    condition$issues$rule
  )
})

test_that("commit never reassigns a candidate identifier", {
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

  condition <- catch_graft_ingest_condition(
    kg_write(
      store,
      kg_batch("authoritative", idempotency_key = "promote-candidate"),
      "Entity",
      data.frame(
        preferred_name = "Authoritative record",
        cas_number = "CAS: 50-00-0"
      )
    )
  )
  entities <- DBI::dbReadTable(store$connection, "entity")
  registry <- DBI::dbReadTable(store$connection, "_graft_identifiers")

  expect_s3_class(condition, "graft_identity_error")
  expect_identical(condition$rule, "active_identifier_agreement")
  expect_identical(entities$id, candidate_record_id)
  expect_identical(registry$record_id, candidate_record_id)
  expect_identical(registry$status, "candidate")
  expect_identical(registry$value, "50-00-0")
  expect_identical(registry$assigned_by, "resolver")
  expect_identical(registry$confidence, 0.4)
  expect_identical(registry$created_at, candidate_created_at)
})

test_that("commit promotes a candidate identifier for the same record", {
  store <- local_ingest_store()
  record_id <- test_graft_id("same-candidate-record")
  kg_write(
    store,
    kg_batch("seed", idempotency_key = "same-candidate-record"),
    "Entity",
    data.frame(id = record_id, preferred_name = "Candidate record")
  )
  candidate_created_at <- as.POSIXct("2025-01-01", tz = "UTC")
  DBI::dbAppendTable(
    store$connection,
    "_graft_identifiers",
    data.frame(
      record_id = record_id,
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

  result <- graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = record_id,
        preferred_name = "Authoritative record",
        cas_number = "CAS: 50-00-0"
      )
    ),
    graft_provenance("authoritative")
  )
  registry <- DBI::dbReadTable(store$connection, "_graft_identifiers")

  expect_identical(result$updated, c(Entity = 1L))
  expect_identical(registry$record_id, record_id)
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

test_that("planning reports external identifiers resolving to different IDs", {
  store <- local_ingest_store()
  now <- as.POSIXct("2026-01-01", tz = "UTC")
  DBI::dbAppendTable(
    store$connection,
    "_graft_identifiers",
    data.frame(
      record_id = c(
        test_graft_id("inchikey-record"),
        test_graft_id("cas-record")
      ),
      class = "Entity",
      namespace = c("inchikey", "cas"),
      value = c("XLYOFNOQVPJJNP-UHFFFAOYSA-N", "50-00-0"),
      normalized_value = c(
        "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
        "50-00-0"
      ),
      status = "primary",
      assigned_by = "fixture",
      confidence = 1,
      created_at = now,
      stringsAsFactors = FALSE
    )
  )

  plan <- graft_plan(
    store,
    list(
      Entity = data.frame(
        preferred_name = "Conflicting identity",
        inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
        cas_number = "CAS: 50-00-0"
      )
    ),
    graft_provenance("identity-test")
  )

  expect_identical(plan@valid, FALSE)
  matching <- which(plan@issues$rule == "consistent_exact_identity")
  expect_gt(length(matching), 0L)
  expect_setequal(
    plan@issues$condition_class[matching],
    "graft_identity_error"
  )
})

test_that("unresolved exact and deterministic IDs are producer-independent", {
  store <- local_ingest_store()
  entity <- list(
    Entity = data.frame(
      preferred_name = "Water",
      inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
    )
  )
  run <- list(
    Run = data.frame(run_identifier = "stable-run", name = "Run")
  )

  entity_a <- graft_plan(store, entity, graft_provenance("producer-a"))
  entity_b <- graft_plan(store, entity, graft_provenance("producer-b"))
  run_a <- graft_plan(store, run, graft_provenance("producer-a"))
  run_b <- graft_plan(store, run, graft_provenance("producer-b"))

  expect_identical(entity_a@changes$record_id, entity_b@changes$record_id)
  expect_identical(entity_a@changes$identity_reason, "exact_identifier_mint")
  expect_identical(run_a@changes$record_id, run_b@changes$record_id)
  expect_identical(run_a@changes$identity_reason, "deterministic_key")
  expect_match(run_a@changes$identity_evidence, "value_digest")
  expect_no_match(run_a@changes$identity_evidence, "stable-run")
  expect_no_match(run_a@changes$identity_evidence, "producer-a")
})

test_that("plan changes preserve specific agreeing identity evidence", {
  store <- local_ingest_store()
  record_id <- test_graft_id("agreeing-evidence")
  DBI::dbAppendTable(
    store$connection,
    "_graft_identifiers",
    data.frame(
      record_id = record_id,
      class = "Entity",
      namespace = "inchikey",
      value = "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
      normalized_value = "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
      status = "primary",
      assigned_by = "fixture",
      confidence = 1,
      created_at = as.POSIXct("2026-01-01", tz = "UTC"),
      stringsAsFactors = FALSE
    )
  )

  plan <- graft_plan(
    store,
    list(
      Entity = data.frame(
        id = record_id,
        preferred_name = "Water",
        inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
      )
    ),
    graft_provenance("evidence-test")
  )
  evidence <- jsonlite::fromJSON(
    plan@changes$identity_evidence,
    simplifyVector = FALSE
  )
  kinds <- vapply(evidence, \(.x) .x$kind, character(1))

  expect_identical(plan@changes$identity_reason, "agreeing_identity")
  expect_setequal(kinds, c("supplied_id", "external_identifier"))
  expect_match(plan@changes$identity_evidence, "inchikey")
})
