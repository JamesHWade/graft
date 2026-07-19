ci_read_json <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

ci_character <- function(x) {
  unname(unlist(x, use.names = FALSE))
}

ci_rows_to_records <- function(rows, schema) {
  if (length(rows) == 0L) {
    return(list())
  }
  records <- jsonlite::fromJSON(
    jsonlite::toJSON(rows, auto_unbox = TRUE, null = "null"),
    simplifyVector = TRUE
  )
  for (record_class in names(rows)) {
    slots <- graft::kg_slots(schema, record_class)
    multivalued <- slots$slot[slots$multivalued]
    scalar <- setdiff(slots$slot, multivalued)
    for (field in intersect(scalar, names(records[[record_class]]))) {
      all_missing <- all(vapply(
        rows[[record_class]],
        function(row) {
          value <- row[[field]]
          is.null(value) ||
            length(value) == 0L ||
            (length(value) == 1L && is.na(value))
        },
        logical(1)
      ))
      if (all_missing) {
        records[[record_class]][[field]] <- NULL
      }
    }
    for (field in intersect(multivalued, names(records[[record_class]]))) {
      records[[record_class]][[field]] <- I(lapply(
        rows[[record_class]],
        function(row) {
          value <- row[[field]]
          if (is.null(value)) {
            return(logical())
          }
          if (is.list(value)) {
            value <- unlist(value, use.names = FALSE)
          }
          unname(value)
        }
      ))
    }
  }
  records
}

ci_plain_record <- function(record) {
  jsonlite::fromJSON(
    jsonlite::toJSON(
      record,
      auto_unbox = TRUE,
      null = "null",
      na = "null",
      digits = NA,
      POSIXt = "ISO8601",
      UTC = TRUE
    ),
    simplifyVector = FALSE
  )
}

ci_record_digest <- function(record) {
  payload <- jsonlite::toJSON(
    ci_plain_record(record),
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    POSIXt = "ISO8601",
    UTC = TRUE
  )
  digest::digest(payload, algo = "sha256", serialize = FALSE)
}

ci_record_precondition <- function(record, expected_status = NULL) {
  list(
    id = record$id,
    class = record$class,
    record_digest = ci_record_digest(record$record),
    expected_status = expected_status
  )
}

ci_validate_record_preconditions <- function(store, preconditions) {
  for (precondition in preconditions) {
    current <- graft::kg_get(
      store,
      precondition$id,
      include = character()
    )
    status_matches <- is.null(precondition$expected_status) ||
      identical(
        current$record$status,
        precondition$expected_status
      )
    if (
      !identical(current$class, precondition$class) ||
        !status_matches ||
        !identical(
          ci_record_digest(current$record),
          precondition$record_digest
        )
    ) {
      stop(
        paste0(
          "Knowledge precondition failed for `",
          precondition$id,
          "`; relied-upon knowledge changed before commit."
        )
      )
    }
  }
  invisible(TRUE)
}

ci_validate_absent_records <- function(store, record_ids) {
  for (record_id in ci_character(record_ids)) {
    existing <- tryCatch(
      graft::kg_get(
        store,
        record_id,
        include = character()
      ),
      graft_reference_error = function(error) NULL
    )
    if (!is.null(existing)) {
      stop(
        paste0(
          "New record target `",
          record_id,
          "` already exists; no knowledge changes were mapped."
        )
      )
    }
  }
  invisible(TRUE)
}

ci_require_text <- function(value, field) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(trimws(value))
  ) {
    stop(paste0("`", field, "` must be one nonempty string."))
  }
  trimws(value)
}

ci_knowledge_change_targets <- function(knowledge_changes) {
  targets <- list()
  for (record_class in names(knowledge_changes)) {
    for (record in knowledge_changes[[record_class]]) {
      targets[[length(targets) + 1L]] <- list(
        id = ci_require_text(record$id, "knowledge change id"),
        class = record_class
      )
    }
  }
  target_ids <- vapply(targets, `[[`, character(1), "id")
  if (anyDuplicated(target_ids)) {
    stop("A knowledge change set cannot contain duplicate record targets.")
  }
  targets
}

ci_target_state_preconditions <- function(store, knowledge_changes) {
  lapply(
    ci_knowledge_change_targets(knowledge_changes),
    function(target) {
      existing <- tryCatch(
        graft::kg_get(
          store,
          target$id,
          include = character()
        ),
        graft_reference_error = function(error) NULL
      )
      if (is.null(existing)) {
        return(list(
          id = target$id,
          class = target$class,
          expected_state = "absent"
        ))
      }
      if (!identical(existing$class, target$class)) {
        stop(
          paste0(
            "Knowledge change target `",
            target$id,
            "` already belongs to class `",
            existing$class,
            "`."
          )
        )
      }
      list(
        id = target$id,
        class = target$class,
        expected_state = "present",
        record_digest = ci_record_digest(existing$record)
      )
    }
  )
}

ci_validate_target_state_preconditions <- function(store, preconditions) {
  for (precondition in preconditions) {
    current <- tryCatch(
      graft::kg_get(
        store,
        precondition$id,
        include = character()
      ),
      graft_reference_error = function(error) NULL
    )
    valid <- if (identical(precondition$expected_state, "absent")) {
      is.null(current)
    } else if (identical(precondition$expected_state, "present")) {
      !is.null(current) &&
        identical(current$class, precondition$class) &&
        identical(
          ci_record_digest(current$record),
          precondition$record_digest
        )
    } else {
      FALSE
    }
    if (!valid) {
      stop(
        paste0(
          "Target-state precondition failed for `",
          precondition$id,
          "`; the proposal target changed before commit."
        )
      )
    }
  }
  invisible(TRUE)
}

ci_promotion_store <- function() {
  store <- new.env(parent = emptyenv())
  store$records <- list()
  class(store) <- "ci_promotion_store"
  store
}

ci_record_promotion <- function(
  store,
  promotion_id,
  referral,
  reviewer,
  decided_at,
  note = NULL,
  decision = "approved"
) {
  if (!inherits(store, "ci_promotion_store")) {
    stop("`store` must be a continuous-intelligence promotion store.")
  }
  promotion_id <- ci_require_text(promotion_id, "promotion_id")
  referral_id <- ci_require_text(referral$referral_id, "referral$referral_id")
  workflow_id <- ci_require_text(referral$workflow_id, "referral$workflow_id")
  reviewer <- ci_require_text(reviewer, "reviewer")
  decided_at <- ci_require_text(decided_at, "decided_at")
  decision <- ci_require_text(decision, "decision")
  if (!is.null(store$records[[promotion_id]])) {
    stop(paste0("Promotion record `", promotion_id, "` already exists."))
  }
  store$records[[promotion_id]] <- list(
    promotion_id = promotion_id,
    referral_id = referral_id,
    workflow_id = workflow_id,
    referral_digest = ci_record_digest(referral),
    decision = decision,
    reviewer = reviewer,
    decided_at = decided_at,
    note = note
  )
  promotion_id
}

ci_resolve_promotion <- function(store, promotion_id, referral) {
  if (!inherits(store, "ci_promotion_store")) {
    stop(
      paste(
        "The active profile requires an approved human-promotion",
        "record from the host approval store."
      )
    )
  }
  promotion_id <- ci_require_text(promotion_id, "promotion_id")
  promotion <- store$records[[promotion_id]]
  if (is.null(promotion)) {
    stop(paste0("Promotion record `", promotion_id, "` was not found."))
  }
  if (!identical(promotion$decision, "approved")) {
    stop("The host promotion record is not approved.")
  }
  if (
    !identical(promotion$referral_id, referral$referral_id) ||
      !identical(promotion$workflow_id, referral$workflow_id) ||
      !identical(
        promotion$referral_digest,
        ci_record_digest(referral)
      )
  ) {
    stop(
      paste(
        "The host promotion record does not match the approved",
        "referral content and workflow."
      )
    )
  }
  promotion
}

ci_proposal_count <- function(proposals) {
  if (length(proposals) == 0L) {
    return(0L)
  }
  as.integer(sum(lengths(proposals)))
}

ci_iso_time <- function(x) {
  if (length(x) == 0L || is.na(x[[1L]])) {
    return(NULL)
  }
  if (inherits(x, "POSIXt")) {
    return(format(x[[1L]], "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  }
  as.character(x[[1L]])
}

ci_accepted_context <- function(store, record_ids) {
  hydrated <- lapply(record_ids, function(id) {
    graft::kg_get(
      store,
      id,
      include = c("claims", "evidence"),
      limits = list(
        identifiers = 10L,
        claims = 50L,
        evidence = 100L
      )
    )
  })

  records <- lapply(hydrated, function(record) {
    values <- record$record
    record_snapshot <- ci_plain_record(values)
    display <- values$name
    if (is.null(display) || is.na(display)) {
      display <- values$title
    }
    if (is.null(display) || is.na(display)) {
      display <- values$label
    }
    list(
      id = record$id,
      class = record$class,
      display = if (is.null(display) || is.na(display)) {
        record$id
      } else {
        display
      },
      record = record_snapshot,
      record_digest = ci_record_digest(record_snapshot)
    )
  })

  claims <- list()
  for (record in hydrated) {
    if (nrow(record$claims) == 0L) {
      next
    }
    for (index in seq_len(nrow(record$claims))) {
      claim <- record$claims[index, , drop = FALSE]
      evidence <- claim$evidence[[1L]]
      claim_record <- graft::kg_get(
        store,
        claim$id[[1L]],
        include = character()
      )
      record_snapshot <- ci_plain_record(claim_record$record)
      claims[[claim$id[[1L]]]] <- list(
        id = claim$id[[1L]],
        class = claim$class[[1L]],
        statement_text = claim$statement_text[[1L]],
        status = claim$status[[1L]],
        polarity = claim$polarity[[1L]],
        confidence = claim$confidence[[1L]],
        asserted_at = ci_iso_time(claim$asserted_at),
        evidence_ids = if (nrow(evidence) == 0L) {
          character()
        } else {
          evidence$id
        },
        record = record_snapshot,
        record_digest = ci_record_digest(record_snapshot)
      )
    }
  }

  list(
    records = unname(records),
    claims = unname(claims)
  )
}

ci_accepted_context_preconditions <- function(accepted_context) {
  c(
    lapply(
      accepted_context$records,
      ci_record_precondition
    ),
    lapply(
      accepted_context$claims,
      function(claim) {
        ci_record_precondition(
          claim,
          expected_status = claim$status
        )
      }
    )
  )
}

ci_accepted_evidence <- function(store, record_ids, accepted_context) {
  record_ids <- ci_character(record_ids)
  if (length(record_ids) == 0L) {
    stop("A promoted referral must cite at least one evidence record.")
  }
  accepted_claims <- accepted_context$claims
  hydrated <- lapply(record_ids, function(id) {
    evidence <- graft::kg_get(store, id, include = character())
    statement_id <- evidence$record$statement_id
    if (
      is.null(statement_id) ||
        !is.character(statement_id) ||
        length(statement_id) != 1L ||
        is.na(statement_id) ||
        !nzchar(statement_id)
    ) {
      stop(
        paste0(
          "Referral evidence record `",
          id,
          "` does not identify a supported statement."
        )
      )
    }
    matching_claims <- Filter(
      function(claim) {
        identical(claim$id, statement_id) &&
          id %in% claim$evidence_ids
      },
      accepted_claims
    )
    if (length(matching_claims) != 1L) {
      stop(
        paste0(
          "Referral evidence record `",
          id,
          "` is not attached to an accepted claim in the referral context."
        )
      )
    }
    evidence$source <- graft::kg_get(
      store,
      evidence$record$source_id,
      include = character()
    )
    evidence
  })
  names(hydrated) <- record_ids
  hydrated
}

ci_monitor_content <- function(profile, daily_bundle, store) {
  record_ids <- ci_character(profile$monitor_scope$record_ids)
  proposals <- daily_bundle$proposals
  referrals <- daily_bundle$referrals
  list(
    profile_id = profile$profile_id,
    profile_version = profile$version,
    title = profile$title,
    audience = profile$audience,
    cadence = profile$cadence,
    scan_date = daily_bundle$scan_date,
    status = daily_bundle$status,
    headline = daily_bundle$headline,
    summary = daily_bundle$summary,
    checked = ci_character(daily_bundle$checked),
    changes = ci_character(daily_bundle$changes),
    unchanged = ci_character(daily_bundle$unchanged),
    proposals = proposals,
    proposal_count = ci_proposal_count(proposals),
    proposal_target_preconditions = ci_target_state_preconditions(
      store,
      proposals
    ),
    referrals = referrals,
    accepted_context = ci_accepted_context(store, record_ids)
  )
}

ci_markdown_items <- function(values, empty = "None.") {
  values <- ci_character(values)
  if (length(values) == 0L) {
    return(empty)
  }
  paste0("- ", values, collapse = "\n")
}

ci_markdown_referrals <- function(referrals) {
  if (length(referrals) == 0L) {
    return("None.")
  }
  paste0(
    "- **",
    vapply(referrals, `[[`, character(1), "workflow_id"),
    "** — ",
    vapply(referrals, `[[`, character(1), "reason"),
    collapse = "\n"
  )
}

ci_render_section <- function(section, content) {
  field <- section$field
  title <- section$title
  body <- switch(
    field,
    changes = ci_markdown_items(content$changes),
    unchanged = ci_markdown_items(content$unchanged),
    referrals = ci_markdown_referrals(content$referrals),
    proposals = if (content$proposal_count == 0L) {
      "No knowledge changes require review."
    } else {
      paste(
        content$proposal_count,
        "candidate records await host review."
      )
    },
    "Section is not configured."
  )
  paste0("## ", title, "\n\n", body)
}

ci_render_briefing <- function(content, profile) {
  sections <- vapply(
    profile$briefing_sections,
    ci_render_section,
    character(1),
    content = content
  )
  paste(
    paste0("# ", content$title),
    paste0("**", content$scan_date, " · ", content$status, "**"),
    paste0("## ", content$headline),
    content$summary,
    paste(sections, collapse = "\n\n"),
    paste0(
      "## What was checked\n\n",
      ci_markdown_items(content$checked)
    ),
    sep = "\n\n"
  )
}

ci_register_renderers <- function(registry) {
  registry$register(
    "example.ci.renderer.json",
    kind = "renderer",
    version = "1",
    implementation = function(content) {
      tempest::tempest_artifact_representation(
        content = content,
        artifact_kind = "structured-data",
        media_type = "application/json"
      )
    }
  )
  registry$register(
    "example.ci.renderer.markdown",
    kind = "renderer",
    version = "1",
    implementation = function(content, runtime) {
      tempest::tempest_artifact_representation(
        content = ci_render_briefing(content, runtime$profile),
        artifact_kind = "briefing",
        media_type = "text/markdown"
      )
    }
  )
  invisible(registry)
}

ci_deliverable <- function(
  deliverable_id,
  title,
  purpose,
  required_fields,
  renderer_id,
  content_type,
  media_type,
  requires_approval = FALSE
) {
  tempest::tempest_deliverable_spec(
    deliverable_id,
    version = "1",
    title = title,
    purpose = purpose,
    instructions = purpose,
    content_schema = list(
      type = "object",
      required = required_fields
    ),
    required_fields = required_fields,
    evidence_policy = "source_attributed",
    generator_id = "tempest.generator.provided_content",
    validator_ids = "tempest.validator.required_fields",
    renderer_ids = renderer_id,
    content_type = content_type,
    media_types = media_type,
    operation_versions = c(
      "tempest.generator.provided_content" = "1",
      "tempest.validator.required_fields" = "1",
      stats::setNames("1", renderer_id)
    ),
    requires_approval = requires_approval
  )
}

ci_monitor_specs <- function() {
  list(
    briefing = ci_deliverable(
      "continuous-briefing",
      "Continuous intelligence briefing",
      "Summarize the scheduled scan for the configured audience.",
      c(
        "profile_id",
        "scan_date",
        "status",
        "headline",
        "summary"
      ),
      "example.ci.renderer.markdown",
      "continuous-briefing",
      "text/markdown"
    ),
    result = ci_deliverable(
      "monitor-result",
      "Monitor result",
      "Preserve findings, proposals, referrals, and accepted context.",
      c(
        "profile_id",
        "scan_date",
        "status",
        "accepted_context",
        "proposal_target_preconditions"
      ),
      "example.ci.renderer.json",
      "monitor-result",
      "application/json"
    )
  )
}

ci_generate <- function(
  spec,
  content,
  registry,
  artifact_catalog,
  run_id,
  step,
  expert_id,
  artifact_id,
  runtime = list()
) {
  tempest::tempest_generate_deliverable(
    spec,
    context = list(content = content),
    registry = registry,
    catalog = artifact_catalog,
    runtime = runtime,
    provenance = list(
      artifact_id = artifact_id,
      run_id = run_id,
      step_id = step@step_id,
      expert_id = expert_id
    )
  )
}

ci_monitor_registry <- function() {
  registry <- tempest::tempest_builtin_operation_registry()
  ci_register_renderers(registry)
  registry$register(
    "example.ci.step.monitor",
    kind = "step",
    version = "1",
    implementation = function(
      profile,
      daily_bundle,
      knowledge_store,
      deliverables,
      artifact_catalog,
      run_id,
      step,
      expert_id,
      runtime
    ) {
      content <- ci_monitor_content(
        profile,
        daily_bundle,
        knowledge_store
      )
      briefing <- ci_generate(
        deliverables$briefing,
        content,
        runtime,
        artifact_catalog,
        run_id,
        step,
        expert_id,
        "daily-briefing-md",
        runtime = list(profile = profile)
      )
      result <- ci_generate(
        deliverables$result,
        content,
        runtime,
        artifact_catalog,
        run_id,
        step,
        expert_id,
        "monitor-result-json"
      )
      list(artifacts = c(briefing$artifacts, result$artifacts))
    }
  )
  registry
}

ci_monitor_workflow <- function() {
  tempest::tempest_workflow_spec(
    "continuous-intelligence.monitor",
    version = "1",
    title = "Continuous intelligence monitor",
    purpose = paste(
      "Reconcile a scheduled signal bundle with accepted knowledge and",
      "produce a briefing, knowledge proposals, and workflow referrals."
    ),
    supported_deliverable_types = c(
      "continuous-briefing",
      "monitor-result"
    ),
    steps = list(tempest::tempest_workflow_step(
      "monitor",
      title = "Monitor",
      purpose = "Prepare the scheduled intelligence result.",
      operation_id = "example.ci.step.monitor",
      produced_artifact_ids = c(
        "daily-briefing-md",
        "monitor-result-json"
      ),
      assignment_rule = "expert.continuous-intelligence"
    ))
  )
}

ci_expert <- function() {
  tempest::tempest_expert(
    expert_id = "expert.continuous-intelligence",
    name = "Continuous Intelligence Analyst",
    title = "Evidence reconciliation specialist",
    description = paste(
      "Reconciles scheduled signals with accepted organizational",
      "knowledge."
    ),
    instructions = paste(
      "Keep unreviewed evidence separate from accepted knowledge.",
      "Prefer an explicit no-material-change result to manufactured urgency."
    ),
    focus_areas = c(
      "evidence reconciliation",
      "materiality",
      "workflow routing"
    )
  )
}

ci_run_monitor <- function(
  profile,
  daily_bundle,
  store,
  run_id
) {
  registry <- ci_monitor_registry()
  deliverables <- ci_monitor_specs()
  objective <- tempest::tempest_objective(
    paste(
      "Run the scheduled monitor for",
      profile$title,
      "on",
      daily_bundle$scan_date
    ),
    title = daily_bundle$headline,
    context = list(
      profile_id = profile$profile_id,
      scan_date = daily_bundle$scan_date
    ),
    constraints = c(
      "Do not commit unreviewed knowledge.",
      "Do not manufacture materiality."
    ),
    acceptance_criteria = c(
      "The briefing reports what changed and what remained true.",
      "Candidate records and workflow referrals are explicit."
    ),
    deliverable_ids = c("continuous-briefing", "monitor-result")
  )
  tempest::tempest_run_workflow(
    objective,
    ci_monitor_workflow(),
    runtime = registry,
    experts = list(ci_expert()),
    deliverables = deliverables,
    runtime_context = list(
      profile = profile,
      daily_bundle = daily_bundle,
      knowledge_store = store,
      deliverables = deliverables
    ),
    run_id = run_id
  )
}

ci_review_spec <- function() {
  ci_deliverable(
    "knowledge-change-set",
    "Knowledge change set",
    "Present candidate records for explicit host review.",
    c(
      "profile_id",
      "scan_date",
      "source_monitor_run_id",
      "knowledge_changes",
      "target_preconditions",
      "context_preconditions"
    ),
    "example.ci.renderer.json",
    "knowledge-change-set",
    "application/json",
    requires_approval = TRUE
  )
}

ci_review_registry <- function() {
  registry <- tempest::tempest_builtin_operation_registry()
  ci_register_renderers(registry)
  registry$register(
    "example.ci.step.review-knowledge",
    kind = "step",
    version = "1",
    implementation = function(
      monitor_content,
      source_monitor_run_id,
      deliverable,
      artifact_catalog,
      run_id,
      step,
      expert_id,
      runtime
    ) {
      content <- list(
        profile_id = monitor_content$profile_id,
        scan_date = monitor_content$scan_date,
        source_monitor_run_id = source_monitor_run_id,
        knowledge_changes = monitor_content$proposals,
        target_preconditions = monitor_content$proposal_target_preconditions,
        context_preconditions = ci_accepted_context_preconditions(
          monitor_content$accepted_context
        )
      )
      ci_generate(
        deliverable,
        content,
        runtime,
        artifact_catalog,
        run_id,
        step,
        expert_id,
        "knowledge-change-set-json"
      )
    }
  )
  registry
}

ci_run_knowledge_review <- function(
  monitor_run,
  source_monitor_run_id,
  run_id,
  store
) {
  monitor_artifact <- tempest::tempest_run_artifact(
    monitor_run,
    "monitor-result-json"
  )
  if (!identical(source_monitor_run_id, monitor_artifact@run_id)) {
    stop(
      paste(
        "The supplied source monitor run identifier does not match",
        "the monitor artifact provenance."
      )
    )
  }
  source_monitor_run_id <- monitor_artifact@run_id
  monitor <- monitor_artifact@content
  if (ci_proposal_count(monitor$proposals) == 0L) {
    stop("The monitor result has no knowledge changes to review.")
  }
  ci_validate_target_state_preconditions(
    store,
    monitor$proposal_target_preconditions
  )
  deliverable <- ci_review_spec()
  registry <- ci_review_registry()
  workflow <- tempest::tempest_workflow_spec(
    "continuous-intelligence.review-knowledge",
    version = "1",
    title = "Review proposed knowledge",
    purpose = "Place candidate records behind an approval boundary.",
    supported_deliverable_types = "knowledge-change-set",
    steps = list(tempest::tempest_workflow_step(
      "review-knowledge",
      title = "Review knowledge",
      purpose = "Prepare a validated knowledge change set.",
      operation_id = "example.ci.step.review-knowledge",
      produced_artifact_ids = "knowledge-change-set-json",
      assignment_rule = "expert.continuous-intelligence"
    ))
  )
  objective <- tempest::tempest_objective(
    "Review candidate knowledge from a scheduled monitor run.",
    title = paste("Review", monitor$scan_date, "knowledge changes"),
    context = list(source_monitor_run_id = source_monitor_run_id),
    constraints = "Do not write to the knowledge store.",
    acceptance_criteria = "Every candidate record remains inspectable.",
    deliverable_ids = "knowledge-change-set"
  )
  tempest::tempest_run_workflow(
    objective,
    workflow,
    runtime = registry,
    experts = list(ci_expert()),
    deliverables = list(deliverable),
    runtime_context = list(
      monitor_content = monitor,
      source_monitor_run_id = source_monitor_run_id,
      deliverable = deliverable
    ),
    run_id = run_id
  )
}

ci_referral_spec <- function() {
  ci_deliverable(
    "workflow-referral-result",
    "Workflow referral result",
    "Prepare an evidence-backed result for a promoted workflow referral.",
    c(
      "workflow_id",
      "decision",
      "recommendation",
      "evidence_record_ids",
      "knowledge_changes",
      "workflow_lineage"
    ),
    "example.ci.renderer.json",
    "workflow-referral-result",
    "application/json",
    requires_approval = TRUE
  )
}

ci_referral_registry <- function() {
  registry <- tempest::tempest_builtin_operation_registry()
  ci_register_renderers(registry)
  registry$register(
    "example.ci.step.run-referral",
    kind = "step",
    version = "1",
    implementation = function(
      referral,
      accepted_context,
      accepted_evidence,
      promotion,
      result_builder,
      deliverable,
      artifact_catalog,
      run_id,
      step,
      expert_id,
      runtime
    ) {
      content <- result_builder(
        referral,
        accepted_context,
        accepted_evidence
      )
      content$promotion <- promotion
      content$workflow_lineage <- list(
        run_id = run_id,
        workflow_id = referral$workflow_id,
        evidence_record_ids = names(accepted_evidence),
        synthesis_method = "approved-workflow-synthesis"
      )
      ci_generate(
        deliverable,
        content,
        runtime,
        artifact_catalog,
        run_id,
        step,
        expert_id,
        "workflow-referral-result-json"
      )
    }
  )
  registry
}

ci_run_referral <- function(
  referral,
  profile,
  store,
  result_builder,
  run_id,
  promotion_store = NULL,
  promotion_id = NULL
) {
  workflow_id <- referral$workflow_id
  allowed <- vapply(
    profile$routing_policy$allowed_workflow_ids,
    as.character,
    character(1)
  )
  if (!workflow_id %in% allowed) {
    stop("The referral workflow is not allowed by the active profile.")
  }
  promotion_required <- isTRUE(
    profile$routing_policy$human_promotion_required
  )
  promotion <- NULL
  if (promotion_required || !is.null(promotion_id)) {
    promotion <- ci_resolve_promotion(
      promotion_store,
      promotion_id,
      referral
    )
  }
  accepted_context <- ci_accepted_context(
    store,
    ci_character(referral$context_record_ids)
  )
  accepted_evidence <- ci_accepted_evidence(
    store,
    referral$evidence_record_ids,
    accepted_context
  )
  referral$evidence_record_ids <- names(accepted_evidence)
  deliverable <- ci_referral_spec()
  registry <- ci_referral_registry()
  workflow <- tempest::tempest_workflow_spec(
    workflow_id,
    version = "1",
    title = "Promoted continuous-intelligence referral",
    purpose = referral$objective,
    supported_deliverable_types = "workflow-referral-result",
    steps = list(tempest::tempest_workflow_step(
      "run-referral",
      title = "Run referral",
      purpose = referral$reason,
      operation_id = "example.ci.step.run-referral",
      produced_artifact_ids = "workflow-referral-result-json",
      assignment_rule = "expert.continuous-intelligence"
    ))
  )
  objective <- tempest::tempest_objective(
    referral$objective,
    title = referral$objective,
    context = list(
      workflow_id = workflow_id,
      priority = referral$priority,
      evidence_record_ids = names(accepted_evidence),
      promotion = promotion
    ),
    constraints = c(
      "Use only accepted knowledge and the cited referral evidence.",
      "Do not commit a recommendation without host approval."
    ),
    acceptance_criteria = c(
      "The result explains why the prior position changed or remained.",
      "The recommendation is bounded by unresolved uncertainty."
    ),
    deliverable_ids = "workflow-referral-result"
  )
  tempest::tempest_run_workflow(
    objective,
    workflow,
    runtime = registry,
    experts = list(ci_expert()),
    deliverables = list(deliverable),
    runtime_context = list(
      referral = referral,
      accepted_context = accepted_context,
      accepted_evidence = accepted_evidence,
      promotion = promotion,
      result_builder = result_builder,
      deliverable = deliverable
    ),
    run_id = run_id
  )
}

ci_default_record_mapper <- function(content, approval, store) {
  ci_validate_record_preconditions(
    store,
    content$context_preconditions
  )
  ci_validate_target_state_preconditions(
    store,
    content$target_preconditions
  )
  ci_rows_to_records(content$knowledge_changes, store$schema)
}

ci_artifact_approvals <- function(run, artifact_id, status) {
  approvals <- tempest::tempest_run_approvals(run, status = status)
  Filter(
    function(approval) {
      identical(approval$approval_kind, "artifact") &&
        identical(approval$artifact_ids, artifact_id)
    },
    approvals
  )
}

ci_artifact_ingest_stage <- function(artifact_id, artifact, approval) {
  identity <- list(
    artifact_id = artifact_id,
    run_id = artifact@run_id,
    content = artifact@content,
    approval = approval
  )
  paste0(
    "approved-artifact:",
    artifact_id,
    ":",
    ci_record_digest(identity)
  )
}

ci_tempest_ingest_committed <- function(store, run_id, stage) {
  idempotency_key <- paste0(run_id, ":", stage)
  committed <- DBI::dbGetQuery(
    store$connection,
    paste(
      "SELECT COUNT(*) AS n FROM _graft_batches",
      "WHERE producer = ? AND idempotency_key = ?",
      "AND source_run_id = ?",
      "AND status = 'committed'"
    ),
    params = list("tempest", idempotency_key, run_id)
  )$n[[1L]]
  identical(as.integer(committed), 1L)
}

ci_approve_and_commit <- function(
  run,
  artifact_id,
  store,
  run_id,
  note,
  record_mapper = ci_default_record_mapper
) {
  artifact <- tempest::tempest_run_artifact(run, artifact_id)
  if (!identical(run_id, artifact@run_id)) {
    stop(
      paste(
        "The supplied commit run identifier does not match",
        "the approved artifact provenance."
      )
    )
  }
  run_id <- artifact@run_id
  if (identical(artifact@status, "awaiting_approval")) {
    approvals <- ci_artifact_approvals(run, artifact_id, "pending")
    if (length(approvals) != 1L) {
      stop(
        paste(
          "Exactly one pending approval for the target artifact",
          "is required."
        )
      )
    }
    approval_id <- names(approvals)[[1L]]
    tempest::tempest_run_record_approval(
      run,
      approval_id,
      decision = "approved",
      note = note
    )
    artifact <- tempest::tempest_run_artifact(run, artifact_id)
    approvals <- ci_artifact_approvals(run, artifact_id, "approved")
    if (length(approvals) != 1L) {
      stop(
        paste(
          "The approval decision did not produce exactly one approved",
          "record for the target artifact."
        )
      )
    }
  } else if (identical(artifact@status, "approved")) {
    approvals <- ci_artifact_approvals(run, artifact_id, "approved")
    if (length(approvals) != 1L) {
      stop(
        paste(
          "The approved artifact does not have exactly one matching",
          "approval record."
        )
      )
    }
    approval_id <- names(approvals)[[1L]]
  } else {
    stop(
      paste(
        "The target artifact must be awaiting approval or already",
        "approved before a Graft write is attempted."
      )
    )
  }
  if (!identical(artifact@status, "approved")) {
    stop("The artifact was not approved; no Graft write was attempted.")
  }
  approval_record <- approvals[[1L]]
  approval <- list(
    approval_id = approval_id,
    decision = "approved",
    note = approval_record$note
  )
  stage <- ci_artifact_ingest_stage(
    artifact_id,
    artifact,
    approval
  )
  if (ci_tempest_ingest_committed(store, run_id, stage)) {
    result <- graft::kg_ingest_tempest_records(
      store,
      run_id = run_id,
      records = list(),
      stage = stage,
      producer_version = as.character(
        utils::packageVersion("tempest")
      )
    )
    return(list(
      run = run,
      artifact = artifact,
      approval = approval,
      ingest = result
    ))
  }
  records <- record_mapper(artifact@content, approval, store)
  result <- graft::kg_ingest_tempest_records(
    store,
    run_id = run_id,
    records = records,
    stage = stage,
    producer_version = as.character(utils::packageVersion("tempest"))
  )
  list(
    run = run,
    artifact = artifact,
    approval = approval,
    ingest = result
  )
}
