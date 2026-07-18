vertical_slice_id <- function(index) {
  paste0("graft:", sprintf("%026d", as.integer(index)))
}

vertical_slice_ids <- function() {
  list(
    lldpe = vertical_slice_id(1),
    crystallinity = vertical_slice_id(2),
    branching = vertical_slice_id(3),
    density = vertical_slice_id(4),
    source_review = vertical_slice_id(5),
    source_study = vertical_slice_id(6),
    claim_branching = vertical_slice_id(7),
    claim_range_old = vertical_slice_id(8),
    semantic_branching = vertical_slice_id(9),
    evidence_branching_support = vertical_slice_id(10),
    evidence_range_old = vertical_slice_id(11),
    evidence_semantic_branching = vertical_slice_id(12),
    mention_resolved = vertical_slice_id(13),
    claim_range_new = vertical_slice_id(14),
    claim_competing = vertical_slice_id(15),
    semantic_crystallinity = vertical_slice_id(16),
    evidence_branching_contradict = vertical_slice_id(17),
    evidence_range_new = vertical_slice_id(18),
    evidence_competing = vertical_slice_id(19),
    evidence_semantic_crystallinity = vertical_slice_id(20),
    mention_unresolved = vertical_slice_id(21),
    activity_one = vertical_slice_id(22),
    question_one = vertical_slice_id(23),
    section_one = vertical_slice_id(24),
    activity_two = vertical_slice_id(25),
    question_two = vertical_slice_id(26),
    section_two = vertical_slice_id(27)
  )
}

vertical_slice_run_one_records <- function(ids = vertical_slice_ids()) {
  list(
    Entity = data.frame(
      id = c(ids$lldpe, ids$crystallinity, ids$branching),
      preferred_name = c(
        "Linear low-density polyethylene (LLDPE)",
        "Polymer crystallinity",
        "Short-chain branching"
      ),
      description = c(
        "A polyethylene with controlled short-chain branching.",
        "The ordered fraction of a polymer material.",
        "Short branches attached to a polyethylene backbone."
      ),
      cas_number = c("9002-88-4", NA_character_, NA_character_)
    ),
    Source = data.frame(
      id = ids$source_review,
      uri = "https://example.org/lldpe/review/",
      title = "LLDPE branching and crystallinity review",
      content_hash = "sha256:lldpe-review-v1",
      doi = "10.1000/lldpe.review"
    ),
    Claim = data.frame(
      id = c(ids$claim_branching, ids$claim_range_old),
      statement_text = c(
        paste(
          "Increasing short-chain branching generally lowers LLDPE",
          "crystallinity."
        ),
        "Published LLDPE crystallinity values commonly fall between 45% and 60%."
      ),
      primary_subject = c(ids$lldpe, ids$lldpe),
      claim_type = c("finding", "observation"),
      importance = c("high", "medium"),
      polarity = c("positive", "positive"),
      confidence = c(0.91, 0.72),
      status = c("active", "active"),
      superseded_by = c(NA_character_, NA_character_),
      about = I(list(
        c(ids$lldpe, ids$branching, ids$crystallinity),
        c(ids$lldpe, ids$crystallinity)
      ))
    ),
    SemanticClaim = data.frame(
      id = ids$semantic_branching,
      subject = ids$lldpe,
      predicate = "graft:branchingLowers",
      object_entity = ids$crystallinity,
      derived_from_statement = ids$claim_branching,
      status = "active",
      polarity = "positive",
      measurement_method = "review synthesis",
      temperature = 23
    ),
    ClaimEvidence = data.frame(
      id = c(
        ids$evidence_branching_support,
        ids$evidence_range_old,
        ids$evidence_semantic_branching
      ),
      statement_id = c(
        ids$claim_branching,
        ids$claim_range_old,
        ids$semantic_branching
      ),
      source_id = rep(ids$source_review, 3L),
      support_type = rep("supports", 3L),
      locator_type = c("page", "page", "section"),
      locator_value = c("p. 12", "p. 13", "sec. 3.2"),
      page_start = c(12, 13, 12),
      page_end = c(12, 13, 12),
      excerpt = c(
        paste(
          "Additional short-chain branches interrupt chain packing and",
          "reduce crystalline order."
        ),
        "Reported crystallinity values for LLDPE span approximately 45-60%.",
        "Branching is associated with reduced crystalline order in LLDPE."
      )
    ),
    EntityMention = data.frame(
      id = ids$mention_resolved,
      source_id = ids$source_review,
      entity_id = ids$lldpe,
      surface_form = "linear low-density polyethylene",
      locator_type = "paragraph",
      locator_value = "para. 2"
    ),
    Run = data.frame(
      run_identifier = "tempest-lldpe-001",
      name = "LLDPE literature review"
    ),
    Activity = data.frame(
      id = ids$activity_one,
      name = "Review polymer literature"
    ),
    Question = data.frame(
      id = ids$question_one,
      text = paste(
        "How does short-chain branching affect LLDPE crystallinity?"
      )
    ),
    Section = data.frame(
      id = ids$section_one,
      title = "Branching background",
      text = "Initial source-backed review of branching and crystallinity."
    )
  )
}

vertical_slice_run_two_records <- function(ids = vertical_slice_ids()) {
  list(
    Entity = data.frame(
      id = c(
        ids$lldpe,
        ids$crystallinity,
        ids$branching,
        ids$density
      ),
      preferred_name = c(
        "Linear low-density polyethylene (LLDPE)",
        "Polymer crystallinity",
        "Short-chain branching",
        "Polymer density"
      ),
      description = c(
        "A polyethylene with controlled short-chain branching.",
        "The ordered fraction of a polymer material.",
        "Short branches attached to a polyethylene backbone.",
        "Mass per unit volume of a polymer material."
      ),
      cas_number = c(
        "9002-88-4",
        NA_character_,
        NA_character_,
        NA_character_
      )
    ),
    Source = data.frame(
      id = c(NA_character_, ids$source_study),
      uri = c(
        "HTTPS://WWW.EXAMPLE.ORG:443/lldpe/review/#overview",
        "https://example.org/lldpe/dsc-study"
      ),
      title = c(
        "LLDPE branching and crystallinity review",
        "Controlled DSC study of LLDPE crystallinity"
      ),
      content_hash = c(
        "sha256:lldpe-review-v1",
        "sha256:lldpe-dsc-study-v1"
      ),
      doi = c(
        "https://doi.org/10.1000/LLDPE.REVIEW",
        "10.1000/lldpe.dsc"
      )
    ),
    Claim = data.frame(
      id = c(
        ids$claim_range_old,
        ids$claim_range_new,
        ids$claim_competing
      ),
      statement_text = c(
        "Published LLDPE crystallinity values commonly fall between 45% and 60%.",
        "A controlled DSC experiment measured 37% crystallinity for the LLDPE sample.",
        paste(
          "The tested high-density reference did not show the same",
          "branching-related crystallinity decrease."
        )
      ),
      primary_subject = rep(ids$lldpe, 3L),
      claim_type = c("observation", "finding", "finding"),
      importance = c("medium", "high", "medium"),
      polarity = c("positive", "positive", "negative"),
      confidence = c(0.72, 0.95, 0.81),
      status = c("superseded", "active", "active"),
      superseded_by = c(
        ids$claim_range_new,
        NA_character_,
        NA_character_
      ),
      about = I(list(
        c(ids$lldpe, ids$crystallinity),
        c(ids$lldpe, ids$crystallinity),
        c(ids$lldpe, ids$branching, ids$crystallinity, ids$density)
      ))
    ),
    SemanticClaim = data.frame(
      id = ids$semantic_crystallinity,
      subject = ids$lldpe,
      predicate = "graft:crystallinityPercent",
      object_value = "37",
      object_datatype = "xsd:decimal",
      derived_from_statement = ids$claim_range_new,
      status = "active",
      polarity = "positive",
      measurement_method = "DSC",
      temperature = 25
    ),
    ClaimEvidence = data.frame(
      id = c(
        ids$evidence_branching_contradict,
        ids$evidence_range_new,
        ids$evidence_competing,
        ids$evidence_semantic_crystallinity
      ),
      statement_id = c(
        ids$claim_branching,
        ids$claim_range_new,
        ids$claim_competing,
        ids$semantic_crystallinity
      ),
      source_id = rep(ids$source_study, 4L),
      support_type = c(
        "contradicts",
        "supports",
        "supports",
        "supports"
      ),
      locator_type = c("page", "other", "page", "other"),
      locator_value = c("p. 6", "table 1", "p. 7", "table 1"),
      page_start = c(6, 5, 7, 5),
      page_end = c(6, 5, 7, 5),
      excerpt = c(
        paste(
          "Within experimental uncertainty, no monotonic branching effect",
          "was observed for one formulation."
        ),
        "The LLDPE sample showed 37% crystallinity by DSC.",
        paste(
          "The high-density reference retained crystallinity under the",
          "same cooling protocol."
        ),
        "Crystallinity (%) for the LLDPE sample: 37."
      )
    ),
    EntityMention = data.frame(
      id = ids$mention_unresolved,
      source_id = ids$source_study,
      entity_id = NA_character_,
      surface_form = "metallocene-rich fraction",
      locator_type = "paragraph",
      locator_value = "para. 9"
    ),
    Run = data.frame(
      run_identifier = "tempest-lldpe-002",
      name = "LLDPE controlled-study follow-up"
    ),
    Activity = data.frame(
      id = ids$activity_two,
      name = "Compare controlled DSC evidence"
    ),
    Question = data.frame(
      id = ids$question_two,
      text = paste(
        "What evidence supports or challenges the LLDPE crystallinity",
        "conclusion?"
      )
    ),
    Section = data.frame(
      id = ids$section_two,
      title = "Controlled-study update",
      text = "Follow-up evidence, supersession, and unresolved terminology."
    )
  )
}

vertical_slice_client_tables <- function() {
  c(
    Entity = "entity",
    Source = "source",
    Claim = "claim",
    SemanticClaim = "semantic_claim",
    ClaimEvidence = "claim_evidence",
    EntityMention = "entity_mention",
    Run = "run",
    Activity = "activity",
    Question = "question",
    Section = "section"
  )
}

vertical_slice_table_counts <- function(store) {
  tables <- c(
    vertical_slice_client_tables(),
    batches = "_graft_batches",
    observations = "_graft_record_observations"
  )
  vapply(
    tables,
    function(table) {
      nrow(DBI::dbReadTable(store$connection, table))
    },
    integer(1)
  )
}

local_vertical_slice_store <- function(env = parent.frame()) {
  ids <- vertical_slice_ids()
  schema <- kg_schema(tempest_manifest_path())
  store <- kg_connect_duckdb(schema, ":memory:")
  withr::defer(kg_disconnect(store), envir = env)
  kg_init(store)

  run_one <- vertical_slice_run_one_records(ids)
  run_two <- vertical_slice_run_two_records(ids)
  result_one <- kg_ingest(
    store,
    kg_batch(
      producer = "tempest",
      producer_version = "0.9.0",
      source_run_id = "tempest-lldpe-001",
      idempotency_key = "tempest-lldpe-001",
      metadata = list(topic = "LLDPE crystallinity", stage = "review")
    ),
    run_one
  )
  result_two <- kg_ingest(
    store,
    kg_batch(
      producer = "tempest",
      producer_version = "0.9.0",
      source_run_id = "tempest-lldpe-002",
      idempotency_key = "tempest-lldpe-002",
      metadata = list(topic = "LLDPE crystallinity", stage = "follow-up")
    ),
    run_two
  )
  before_replay <- vertical_slice_table_counts(store)
  replay_condition <- NULL
  replay <- withCallingHandlers(
    kg_ingest(
      store,
      kg_batch(
        producer = "tempest",
        producer_version = "0.9.1",
        source_run_id = "tempest-lldpe-002-replay",
        idempotency_key = "tempest-lldpe-002",
        metadata = list(topic = "LLDPE crystallinity", stage = "replay")
      ),
      run_two
    ),
    graft_batch_replay = function(condition) {
      replay_condition <<- condition
    }
  )
  after_replay <- vertical_slice_table_counts(store)

  list(
    store = store,
    ids = ids,
    result_one = result_one,
    result_two = result_two,
    replay = replay,
    replay_condition = replay_condition,
    before_replay = before_replay,
    after_replay = after_replay
  )
}

vertical_slice_tool_evaluation <- function(store, ids = vertical_slice_ids()) {
  question <- paste(
    "What do we know about LLDPE crystallinity, which sources support",
    "or challenge those conclusions, and are there competing claims?"
  )
  calls <- list(
    kg_describe = kg_context(store, token_budget = 80),
    kg_find = kg_find(store, "LLDPE", limit = 1),
    kg_get = kg_get(
      store,
      ids$lldpe,
      limits = list(identifiers = 10L, claims = 10L, evidence = 20L)
    ),
    kg_neighbors = kg_neighbors(
      store,
      ids$claim_branching,
      direction = "out",
      hops = 2,
      projection = "combined",
      max_nodes = 3,
      max_edges = 2
    ),
    kg_claims = kg_claims(
      store,
      ids$lldpe,
      include_superseded = TRUE,
      limit = 20
    ),
    kg_select = kg_select(
      store,
      "EntityMention",
      fields = c(
        "id",
        "source_id",
        "surface_form",
        "locator_type",
        "locator_value",
        "entity_id"
      ),
      filters = list(list(field = "entity_id", operator = "is_null")),
      limit = 10
    )
  )
  list(question = question, calls = calls)
}

vertical_slice_answer_material <- function(evaluation) {
  claims <- evaluation$calls$kg_claims
  evidence <- Filter(\(.x) nrow(.x) > 0L, claims$evidence)
  citations <- if (length(evidence) == 0L) {
    data.frame()
  } else {
    result <- do.call(rbind, evidence)
    rownames(result) <- NULL
    result
  }
  list(
    question = evaluation$question,
    active_narrative = claims[
      claims$statement_shape == "narrative" &
        claims$status == "active",
      c("id", "statement_text", "polarity", "status"),
      drop = FALSE
    ],
    superseded = claims[
      claims$status == "superseded",
      c("id", "statement_text", "superseded_by"),
      drop = FALSE
    ],
    semantic = claims[
      claims$statement_shape == "semantic",
      c(
        "id",
        "predicate",
        "object_entity",
        "object_value",
        "object_datatype"
      ),
      drop = FALSE
    ],
    citations = citations,
    unresolved_mentions = evaluation$calls$kg_select
  )
}

vertical_slice_tooldef_evaluation <- function(
  store,
  ids = vertical_slice_ids()
) {
  tools <- kg_tools(store)
  outputs <- list(
    kg_describe = tools$kg_describe(token_budget = 80),
    kg_find = tools$kg_find(query = "LLDPE", limit = 1),
    kg_get = tools$kg_get(
      id = ids$lldpe,
      limits = list(identifiers = 10L, claims = 10L, evidence = 20L)
    ),
    kg_neighbors = tools$kg_neighbors(
      id = ids$claim_branching,
      direction = "out",
      hops = 2,
      projection = "combined",
      max_nodes = 3,
      max_edges = 2
    ),
    kg_claims = tools$kg_claims(
      entity_id = ids$lldpe,
      include_superseded = TRUE,
      limit = 20
    ),
    kg_select = tools$kg_select(
      class = "EntityMention",
      fields = c(
        "id",
        "source_id",
        "surface_form",
        "locator_type",
        "locator_value",
        "entity_id"
      ),
      filters = list(list(field = "entity_id", operator = "is_null")),
      limit = 10
    )
  )
  list(tools = tools, outputs = outputs)
}
