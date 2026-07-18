local_ingest_store <- function(
  path = ":memory:",
  schema = NULL,
  env = parent.frame()
) {
  if (is.null(schema)) {
    schema <- kg_schema(tempest_manifest_path())
  }
  store <- kg_connect_duckdb(schema, path)
  withr::defer(kg_disconnect(store), envir = env)
  kg_init(store)
  store
}

test_graft_id <- function(seed) {
  deterministic_graft_id("TestFixture", list(seed = seed))
}

catch_graft_ingest_condition <- function(code) {
  tryCatch(code, graft_error = identity)
}

modified_ingest_schema <- function(schema) {
  unserialize(serialize(schema, NULL))
}

valid_atomic_records <- function() {
  entity_id <- test_graft_id("entity")
  source_id <- test_graft_id("source")
  claim_id <- test_graft_id("claim")
  semantic_id <- test_graft_id("semantic")
  evidence_id <- test_graft_id("evidence")
  mention_id <- test_graft_id("mention")
  list(
    Entity = data.frame(
      id = entity_id,
      preferred_name = "Polyethylene",
      inchikey = "XLYOFNOQVPJJNP-UHFFFAOYSA-N"
    ),
    Source = data.frame(
      id = source_id,
      title = "A durable source",
      doi = "https://doi.org/10.1000/GRAFT"
    ),
    Claim = data.frame(
      id = claim_id,
      statement_text = "Polyethylene is discussed.",
      confidence = 0.9,
      about = I(list(entity_id))
    ),
    SemanticClaim = data.frame(
      id = semantic_id,
      subject = entity_id,
      predicate = "schema:relatedTo",
      object_entity = entity_id
    ),
    ClaimEvidence = data.frame(
      id = evidence_id,
      statement_id = claim_id,
      source_id = source_id,
      support_type = "supports"
    ),
    EntityMention = data.frame(
      id = mention_id,
      source_id = source_id,
      entity_id = entity_id,
      surface_form = "polyethylene"
    ),
    Run = data.frame(run_identifier = "run-001", name = "Run 1")
  )
}

retrieval_fixture_records <- function() {
  ids <- list(
    entity = test_graft_id("retrieval-entity"),
    other_entity = test_graft_id("retrieval-other-entity"),
    source = test_graft_id("retrieval-source"),
    active_claim = test_graft_id("retrieval-active-claim"),
    competing_claim = test_graft_id("retrieval-competing-claim"),
    superseded_claim = test_graft_id("retrieval-superseded-claim"),
    semantic_claim = test_graft_id("retrieval-semantic-claim"),
    evidence = test_graft_id("retrieval-evidence"),
    unresolved = test_graft_id("retrieval-unresolved"),
    resolved = test_graft_id("retrieval-resolved")
  )
  records <- list(
    Entity = data.frame(
      id = c(ids$entity, ids$other_entity),
      preferred_name = c("Polyethylene", "Water"),
      description = c("A durable thermoplastic", "A reference liquid"),
      inchikey = c(
        "XLYOFNOQVPJJNP-UHFFFAOYSA-N",
        "AAAAAAAAAAAAAA-BBBBBBBBBB-C"
      ),
      cas_number = c("9002-88-4", "7732-18-5")
    ),
    Source = data.frame(
      id = ids$source,
      uri = paste0(
        "HTTPS://WWW.Example.COM:443/reports/Result/",
        "?Study=ABC#overview"
      ),
      title = "Polymer durability study",
      content_hash = "ABC123",
      doi = "https://doi.org/10.1000/GRAFT"
    ),
    Claim = data.frame(
      id = c(
        ids$active_claim,
        ids$competing_claim,
        ids$superseded_claim
      ),
      statement_text = c(
        "Polyethylene remains durable.",
        "Polyethylene durability is uncertain.",
        "Polyethylene was believed fragile."
      ),
      primary_subject = rep(ids$entity, 3L),
      claim_type = c("finding", "observation", "finding"),
      importance = c("high", "medium", "low"),
      polarity = c("positive", "uncertain", "negative"),
      status = c("active", "active", "superseded"),
      superseded_by = c(
        NA_character_,
        NA_character_,
        ids$active_claim
      ),
      about = I(list(
        ids$entity,
        ids$entity,
        ids$entity
      ))
    ),
    SemanticClaim = data.frame(
      id = ids$semantic_claim,
      subject = ids$entity,
      predicate = "schema:relatedTo",
      object_entity = ids$other_entity,
      status = "active",
      polarity = "positive",
      measurement_method = "tensile test",
      temperature = 23
    ),
    ClaimEvidence = data.frame(
      id = ids$evidence,
      statement_id = ids$active_claim,
      source_id = ids$source,
      support_type = "supports",
      locator_type = "page",
      locator_value = "p. 4",
      page_start = 4,
      page_end = 4,
      excerpt = "Polyethylene retained its strength."
    ),
    EntityMention = data.frame(
      id = c(ids$unresolved, ids$resolved),
      source_id = rep(ids$source, 2L),
      entity_id = c(NA_character_, ids$entity),
      surface_form = c("unknown polymer", "polyethylene"),
      locator_type = c("paragraph", "paragraph"),
      locator_value = c("para-2", "para-3")
    )
  )
  list(ids = ids, records = records)
}

local_retrieval_store <- function(env = parent.frame()) {
  fixture <- retrieval_fixture_records()
  store <- local_ingest_store(env = env)
  kg_ingest(
    store,
    kg_batch("retrieval-fixture", idempotency_key = "retrieval-fixture"),
    fixture$records
  )
  list(store = store, ids = fixture$ids)
}
