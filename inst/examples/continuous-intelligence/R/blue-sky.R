blue_sky_result_builder <- function(
  referral,
  accepted_context,
  accepted_evidence
) {
  accepted_ids <- vapply(
    accepted_context$claims,
    `[[`,
    character(1),
    "id"
  )
  required <- c(
    "graft:00000000000000000000000106",
    "graft:00000000000000000000000115",
    "graft:00000000000000000000000118",
    "graft:00000000000000000000000119"
  )
  if (!all(required %in% accepted_ids)) {
    stop(
      paste(
        "The promoted referral requires the accepted baseline, supplier,",
        "and independent observations."
      )
    )
  }
  list(
    workflow_id = referral$workflow_id,
    decision = paste(
      "Should Project Ember authorize a bounded bench test of the Nova",
      "compact actuator?"
    ),
    prior_position = paste(
      "Hold the prototype gate until comparable independent evidence",
      "is available."
    ),
    why_now = paste(
      "Independent testing supports the torque requirement and exposes",
      "a testable duty-cycle limitation."
    ),
    options = list(
      list(
        option = "Continue to hold",
        consequence = "Avoid test cost but leave the duty-cycle question open."
      ),
      list(
        option = "Run a bounded bench test",
        consequence = paste(
          "Test the representative twelve-minute cycle without",
          "authorizing deployment."
        )
      ),
      list(
        option = "Proceed toward deployment",
        consequence = "Exceeds the current evidence and is not recommended."
      )
    ),
    recommendation = paste(
      "Authorize a bounded twelve-minute bench test under Project Ember's",
      "representative load and thermal conditions."
    ),
    uncertainty = paste(
      "Independent evidence stops at ten minutes; thermal behavior during",
      "the final two minutes remains unresolved."
    ),
    owner = "Project Ember test lead",
    next_step = paste(
      "Publish the bench protocol and acceptance criteria before",
      "procuring test hardware."
    ),
    evidence_record_ids = names(accepted_evidence),
    accepted_claim_ids = accepted_ids,
    knowledge_changes = list(
      Assessment = list(list(
        id = "graft:00000000000000000000000122",
        statement_text = paste(
          "Accepted evidence supports a bounded Project Ember bench test",
          "but does not support deployment."
        ),
        primary_subject = "graft:00000000000000000000000101",
        about = c(
          "graft:00000000000000000000000101",
          "graft:00000000000000000000000104",
          "graft:00000000000000000000000102",
          "graft:00000000000000000000000103"
        ),
        disposition = "prototype",
        decision_confidence = 0.86,
        polarity = "positive",
        confidence = 0.86,
        status = "active",
        asserted_at = "2026-07-15T14:00:00Z"
      )),
      ReviewDecision = list(list(
        id = "graft:00000000000000000000000123",
        statement_text = paste(
          "Authorize a bounded twelve-minute Project Ember actuator bench",
          "test; do not authorize deployment."
        ),
        primary_subject = "graft:00000000000000000000000101",
        about = c(
          "graft:00000000000000000000000101",
          "graft:00000000000000000000000104",
          "graft:00000000000000000000000102",
          "graft:00000000000000000000000103"
        ),
        disposition = "prototype",
        reviewer_role = "technology portfolio owner",
        polarity = "positive",
        confidence = 1,
        status = "active",
        asserted_at = "2026-07-15T14:30:00Z"
      )),
      Evidence = list(list(
        id = "graft:00000000000000000000000124",
        statement_id = "graft:00000000000000000000000122",
        source_id = "graft:00000000000000000000000117",
        support_type = "derived_from",
        locator_type = "other",
        locator_value = "table 2 and Thermal behavior",
        excerpt = paste(
          "The test sustained 105 Nm through minute ten and then",
          "required thermal derating."
        ),
        source_content_hash = "sha256:independent-test-v1",
        extraction_method = "approved-workflow-synthesis",
        extraction_version = "1"
      ))
    )
  )
}

blue_sky_decision_record_mapper <- function(content, approval) {
  records <- ci_rows_to_records(content$knowledge_changes)
  records$ReviewDecision$review_outcome <- approval$decision
  records
}
