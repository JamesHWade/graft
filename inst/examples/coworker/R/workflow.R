cw_safe_filename <- function(value) {
  value <- tolower(cw_text(value, "filename"))
  value <- gsub("[^a-z0-9]+", "-", value)
  value <- gsub("(^-+|-+$)", "", value)
  if (!nzchar(value)) {
    value <- "coworker-deliverable"
  }
  paste0(substr(value, 1L, 80L), ".md")
}

cw_output_filename <- function(workspace_name, run_id) {
  cw_safe_filename(paste(workspace_name, run_id))
}

cw_output_path <- function(output_dir, output_filename, must_work = FALSE) {
  normalizePath(
    file.path(output_dir, basename(output_filename)),
    mustWork = must_work
  )
}

cw_deliverable_specs <- function() {
  list(
    plan = tempest::tempest_deliverable_spec(
      "coworker-work-plan",
      version = "1",
      title = "Coworker work plan",
      purpose = "Preserve the plan, synthesis, and proposed local action.",
      instructions = "Return the structured result from the selected planner.",
      content_schema = list(
        type = "object",
        required = c(
          "title",
          "plan_markdown",
          "summary",
          "action_summary"
        )
      ),
      required_fields = c(
        "title",
        "plan_markdown",
        "summary",
        "action_summary"
      ),
      evidence_policy = "source_attributed",
      generator_id = "tempest.generator.provided_content",
      validator_ids = "tempest.validator.required_fields",
      renderer_ids = "example.coworker.renderer.json",
      content_type = "coworker-work-plan",
      media_types = "application/json",
      operation_versions = c(
        "tempest.generator.provided_content" = "1",
        "tempest.validator.required_fields" = "1",
        "example.coworker.renderer.json" = "1"
      )
    ),
    outcome = tempest::tempest_deliverable_spec(
      "coworker-outcome-package",
      version = "1",
      title = "Coworker outcome package",
      purpose = "Publish the finished Markdown deliverable to local storage.",
      instructions = paste(
        "Render the approved work product exactly as reviewed and export it",
        "to the local deliverables directory."
      ),
      content_schema = list(
        type = "object",
        required = c("title", "summary", "markdown")
      ),
      required_fields = c("title", "summary", "markdown"),
      evidence_policy = "source_attributed",
      generator_id = "tempest.generator.provided_content",
      validator_ids = "tempest.validator.required_fields",
      renderer_ids = "example.coworker.renderer.markdown",
      exporter_ids = "example.coworker.exporter.file",
      content_type = "coworker-outcome-package",
      media_types = "text/markdown",
      operation_versions = c(
        "tempest.generator.provided_content" = "1",
        "tempest.validator.required_fields" = "1",
        "example.coworker.renderer.markdown" = "1",
        "example.coworker.exporter.file" = "1"
      ),
      requires_approval = TRUE
    )
  )
}

cw_workflow_registry <- function() {
  registry <- tempest::tempest_builtin_operation_registry()
  registry$register(
    "example.coworker.renderer.json",
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
    "example.coworker.renderer.markdown",
    kind = "renderer",
    version = "1",
    implementation = function(content) {
      tempest::tempest_artifact_representation(
        content = content$markdown,
        artifact_kind = "document",
        media_type = "text/markdown",
        metadata = list(
          title = content$title,
          summary = content$summary
        )
      )
    }
  )
  registry$register(
    "example.coworker.exporter.file",
    kind = "exporter",
    version = "1",
    implementation = function(artifact, runtime) {
      output_dir <- normalizePath(
        runtime$output_dir,
        mustWork = FALSE
      )
      dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
      filename <- basename(runtime$output_filename)
      path <- cw_output_path(output_dir, filename)
      writeLines(
        enc2utf8(artifact@content),
        path,
        useBytes = TRUE
      )
      artifact@metadata <- utils::modifyList(
        artifact@metadata,
        list(
          exported_path = cw_output_path(
            output_dir,
            filename,
            must_work = TRUE
          ),
          exported_filename = filename
        )
      )
      artifact
    }
  )
  registry
}

cw_workflow_spec <- function() {
  tempest::tempest_workflow_spec(
    "graft-coworker.prepare-outcome",
    version = "1",
    title = "Prepare a governed work outcome",
    purpose = paste(
      "Plan a requested outcome, produce a finished deliverable, and stop",
      "for approval before publishing the file."
    ),
    supported_deliverable_types = c(
      "coworker-work-plan",
      "coworker-outcome-package"
    ),
    steps = list(tempest::tempest_workflow_step(
      "prepare",
      title = "Prepare outcome",
      purpose = "Reconcile evidence and memory into the requested deliverable.",
      operation_id = "example.coworker.step.prepare",
      produced_artifact_ids = c(
        "coworker-work-plan-json",
        "coworker-outcome-package-md"
      ),
      assignment_rule = "expert.graft-coworker"
    ))
  )
}

cw_workflow_expert <- function() {
  tempest::tempest_expert(
    expert_id = "expert.graft-coworker",
    name = "Graft Coworker",
    title = "Outcome and continuity specialist",
    description = paste(
      "Turns bounded source snapshots and accepted workspace memory into",
      "reviewable work products."
    ),
    instructions = paste(
      "Keep unreviewed work outside Graft.",
      "Use only supplied evidence and accepted memory.",
      "Ask before publishing the local deliverable."
    ),
    focus_areas = c(
      "outcome planning",
      "evidence reconciliation",
      "organizational memory"
    )
  )
}

cw_register_prepare_step <- function(registry) {
  registry$register(
    "example.coworker.step.prepare",
    kind = "step",
    version = "1",
    implementation = function(
      request,
      source_bundle,
      accepted_memory,
      planner,
      deliverables,
      artifact_catalog,
      run_id,
      step,
      expert_id,
      runtime
    ) {
      result <- cw_run_planner(
        planner,
        request,
        source_bundle,
        accepted_memory
      )
      plan <- tempest::tempest_generate_deliverable(
        deliverables$plan,
        context = list(
          content = result[c(
            "title",
            "plan_markdown",
            "summary",
            "action_summary"
          )]
        ),
        registry = runtime,
        catalog = artifact_catalog,
        provenance = list(
          artifact_id = "coworker-work-plan-json",
          run_id = run_id,
          step_id = step@step_id,
          expert_id = expert_id
        )
      )
      outcome <- tempest::tempest_generate_deliverable(
        deliverables$outcome,
        context = list(
          content = list(
            title = result$title,
            summary = result$summary,
            markdown = result$deliverable_markdown
          )
        ),
        registry = runtime,
        catalog = artifact_catalog,
        provenance = list(
          artifact_id = "coworker-outcome-package-md",
          run_id = run_id,
          step_id = step@step_id,
          expert_id = expert_id
        )
      )
      list(artifacts = c(plan$artifacts, outcome$artifacts))
    }
  )
  invisible(registry)
}

cw_run_workflow <- function(
  request,
  planner,
  source_bundle,
  accepted_memory,
  output_dir,
  run_id
) {
  registry <- cw_workflow_registry()
  cw_register_prepare_step(registry)
  deliverables <- cw_deliverable_specs()
  objective <- tempest::tempest_objective(
    request,
    title = "Prepare a finished work product",
    context = list(
      workspace_id = source_bundle$workspace$id,
      source_ids = cw_source_ids(source_bundle)
    ),
    constraints = c(
      "Use only the supplied source snapshots and accepted memory.",
      "Do not publish a file until its artifact approval is recorded.",
      "Do not claim that an external message or system update occurred."
    ),
    acceptance_criteria = c(
      "The result includes a concrete Markdown deliverable.",
      "Material conflicts and blockers are explicit.",
      "The proposed local publication is approval-gated."
    ),
    deliverable_ids = vapply(
      deliverables,
      \(deliverable) deliverable@deliverable_id,
      character(1)
    )
  )
  tempest::tempest_run_workflow(
    objective,
    cw_workflow_spec(),
    runtime = registry,
    experts = list(cw_workflow_expert()),
    deliverables = deliverables,
    runtime_context = list(
      request = request,
      source_bundle = source_bundle,
      accepted_memory = accepted_memory,
      planner = planner,
      deliverables = deliverables,
      output_dir = output_dir,
      output_filename = cw_output_filename(
        source_bundle$workspace$name,
        run_id
      )
    ),
    run_id = run_id
  )
}
