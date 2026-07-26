mi_deliverable_specs <- function() {
  list(
    briefing = tempest::tempest_deliverable_spec(
      "market-intelligence-briefing",
      version = "1",
      title = "Market intelligence briefing",
      purpose = "Present the source-attributed scheduled market scan.",
      instructions = paste(
        "Render the evidence, interpretation, continuity, and proposed action",
        "without claiming that the assessment entered durable memory."
      ),
      content_schema = list(
        type = "object",
        required = c(
          "scan_date",
          "headline",
          "summary",
          "implication",
          "materiality",
          "continuity",
          "memory_used",
          "markdown"
        )
      ),
      required_fields = c(
        "scan_date",
        "headline",
        "summary",
        "implication",
        "materiality",
        "continuity",
        "memory_used",
        "markdown"
      ),
      evidence_policy = "source_attributed",
      generator_id = "tempest.generator.provided_content",
      validator_ids = "tempest.validator.required_fields",
      renderer_ids = "example.market.renderer.markdown",
      content_type = "market-intelligence-briefing",
      media_types = "text/markdown",
      operation_versions = c(
        "tempest.generator.provided_content" = "1",
        "tempest.validator.required_fields" = "1",
        "example.market.renderer.markdown" = "1"
      )
    ),
    change_set = tempest::tempest_deliverable_spec(
      "market-intelligence-change-set",
      version = "1",
      title = "Market intelligence assessment package",
      purpose = paste(
        "Place the proposed assessment, action, and supporting observations",
        "behind an explicit approval boundary."
      ),
      instructions = paste(
        "Return the exact source, observation, assessment, and action records",
        "that the host may commit after approval."
      ),
      content_schema = list(
        type = "object",
        required = c(
          "scan_date",
          "headline",
          "summary",
          "implication",
          "materiality",
          "confidence",
          "businesses",
          "competitors",
          "downstream_markets",
          "sources",
          "observations",
          "action",
          "memory_used"
        )
      ),
      required_fields = c(
        "scan_date",
        "headline",
        "summary",
        "implication",
        "materiality",
        "confidence",
        "businesses",
        "competitors",
        "downstream_markets",
        "sources",
        "observations",
        "action",
        "memory_used"
      ),
      evidence_policy = "source_attributed",
      generator_id = "tempest.generator.provided_content",
      validator_ids = "tempest.validator.required_fields",
      renderer_ids = "example.market.renderer.json",
      content_type = "market-intelligence-change-set",
      media_types = "application/json",
      operation_versions = c(
        "tempest.generator.provided_content" = "1",
        "tempest.validator.required_fields" = "1",
        "example.market.renderer.json" = "1"
      ),
      requires_approval = TRUE
    )
  )
}

mi_workflow_registry <- function() {
  registry <- tempest::tempest_builtin_operation_registry()
  registry$register(
    "example.market.renderer.markdown",
    kind = "renderer",
    version = "1",
    implementation = function(content) {
      tempest::tempest_artifact_representation(
        content = content$markdown,
        artifact_kind = "briefing",
        media_type = "text/markdown",
        metadata = list(
          scan_date = content$scan_date,
          headline = content$headline,
          materiality = content$materiality
        )
      )
    }
  )
  registry$register(
    "example.market.renderer.json",
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
  registry
}

mi_workflow_spec <- function() {
  tempest::tempest_workflow_spec(
    "market-intelligence.monitor",
    version = "1",
    title = "Run a governed market-intelligence scan",
    purpose = paste(
      "Reconcile a bounded external signal bundle with accepted Graft",
      "history, publish a briefing, and pause before durable interpretation."
    ),
    supported_deliverable_types = c(
      "market-intelligence-briefing",
      "market-intelligence-change-set"
    ),
    steps = list(tempest::tempest_workflow_step(
      "reconcile",
      title = "Reconcile market signals",
      purpose = paste(
        "Separate observations from interpretation and prepare one",
        "owner-assigned action."
      ),
      operation_id = "example.market.step.reconcile",
      produced_artifact_ids = c(
        "market-briefing-md",
        "market-change-set-json"
      ),
      assignment_rule = "expert.materials-market-intelligence"
    ))
  )
}

mi_workflow_expert <- function() {
  tempest::tempest_expert(
    expert_id = "expert.materials-market-intelligence",
    name = "Materials Market Intelligence Analyst",
    title = "Evidence and portfolio specialist",
    description = paste(
      "Connects company, competitor, and downstream-market evidence across",
      "a multi-business materials portfolio."
    ),
    instructions = paste(
      "Keep source-faithful observations separate from assessments.",
      "Use accepted history when it changes the interpretation.",
      "Prefer a bounded action to a generic watch recommendation."
    ),
    focus_areas = c(
      "competitor strategy",
      "downstream demand",
      "portfolio implications",
      "organizational memory"
    )
  )
}

mi_register_reconcile_step <- function(registry) {
  registry$register(
    "example.market.step.reconcile",
    kind = "step",
    version = "1",
    implementation = function(
      request,
      bundle,
      accepted_memory,
      planner,
      deliverables,
      artifact_catalog,
      run_id,
      step,
      expert_id,
      runtime
    ) {
      result <- mi_run_planner(
        planner,
        request,
        bundle,
        accepted_memory
      )
      briefing_content <- list(
        scan_date = bundle$scan_date,
        headline = result$headline,
        summary = result$summary,
        implication = result$implication,
        materiality = result$materiality,
        continuity = result$continuity,
        memory_used = result$memory_used,
        markdown = result$briefing_markdown
      )
      change_content <- list(
        bundle_id = bundle$bundle_id,
        scan_date = bundle$scan_date,
        headline = result$headline,
        summary = result$summary,
        implication = result$implication,
        materiality = result$materiality,
        confidence = result$confidence,
        businesses = result$businesses,
        competitors = result$competitors,
        downstream_markets = result$downstream_markets,
        sources = result$sources,
        observations = result$observations,
        action = list(
          title = result$action_title,
          owner = result$action_owner,
          due_date = result$due_date
        ),
        continuity = result$continuity,
        memory_used = result$memory_used
      )
      briefing <- tempest::tempest_generate_deliverable(
        deliverables$briefing,
        context = list(content = briefing_content),
        registry = runtime,
        catalog = artifact_catalog,
        provenance = list(
          artifact_id = "market-briefing-md",
          run_id = run_id,
          step_id = step@step_id,
          expert_id = expert_id
        )
      )
      change_set <- tempest::tempest_generate_deliverable(
        deliverables$change_set,
        context = list(content = change_content),
        registry = runtime,
        catalog = artifact_catalog,
        provenance = list(
          artifact_id = "market-change-set-json",
          run_id = run_id,
          step_id = step@step_id,
          expert_id = expert_id
        )
      )
      list(artifacts = c(briefing$artifacts, change_set$artifacts))
    }
  )
  invisible(registry)
}

mi_run_workflow <- function(
  request,
  planner,
  bundle,
  accepted_memory,
  run_id
) {
  registry <- mi_workflow_registry()
  mi_register_reconcile_step(registry)
  deliverables <- mi_deliverable_specs()
  objective <- tempest::tempest_objective(
    request,
    title = bundle$title,
    context = list(
      bundle_id = bundle$bundle_id,
      scan_date = bundle$scan_date,
      source_ids = vapply(bundle$sources, `[[`, character(1), "id")
    ),
    constraints = c(
      "Use only the supplied signal bundle and accepted Graft history.",
      "Do not commit an assessment or action before approval.",
      "Do not infer customer-specific behavior from public evidence."
    ),
    acceptance_criteria = c(
      "Every conclusion is traceable to supplied observations.",
      "The briefing states whether accepted memory changed the readout.",
      "The proposal contains one bounded owner-assigned action."
    ),
    deliverable_ids = vapply(
      deliverables,
      \(deliverable) deliverable@deliverable_id,
      character(1)
    )
  )
  tempest::tempest_run_workflow(
    objective,
    mi_workflow_spec(),
    runtime = registry,
    experts = list(mi_workflow_expert()),
    deliverables = deliverables,
    runtime_context = list(
      request = request,
      bundle = bundle,
      accepted_memory = accepted_memory,
      planner = planner,
      deliverables = deliverables
    ),
    run_id = run_id
  )
}
