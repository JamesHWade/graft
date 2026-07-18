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
