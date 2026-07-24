test_that("coworker planner contract stays application-owned and generic", {
  if (!coworker_runtime_available()) {
    testthat::skip("The current coworker runtime is unavailable.")
  }
  environment <- local_coworker_environment()
  bundle <- environment$cw_read_json(
    coworker_example_path("corpus", "project-atlas.json")
  )
  planner <- environment$cw_reference_planner(bundle)
  result <- environment$cw_run_planner(
    planner,
    bundle$suggested_request,
    bundle,
    "No accepted workspace memory yet."
  )
  host <- unlist(lapply(
    c("planner.R", "workflow.R", "worker.R"),
    function(path) {
      readLines(coworker_example_path("R", path), warn = FALSE)
    }
  ))
  schema <- kg_schema(
    coworker_example_path("schema", "coworker.graft.json")
  )

  expect_s3_class(planner, "Module")
  expect_named(
    result,
    c(
      "title",
      "plan_markdown",
      "summary",
      "deliverable_markdown",
      "action_summary"
    )
  )
  expect_match(result$deliverable_markdown, bundle$workspace$name)
  expect_length(
    grep("Project Atlas|launch-blocker|ATLAS-27", host),
    0L
  )
  expect_setequal(
    kg_classes(schema)$class,
    c(
      "ApprovalDecision",
      "CoworkerWorkspace",
      "Deliverable",
      "Memory",
      "SourceSnapshot",
      "WorkRun",
      "WorkSession"
    )
  )
})

test_that("coworker uses Tempest configuration and extensible tools", {
  if (!coworker_runtime_available()) {
    testthat::skip("The current coworker runtime is unavailable.")
  }
  environment <- local_coworker_environment(include_app = TRUE)
  withr::local_options(
    tempest.chat = "anthropic/claude-sonnet-4-20250514"
  )
  ambient <- environment$cw_app_config()
  explicit <- tempest::tempest_config(models = "openai/gpt-5-mini")
  custom_tool <- ellmer::tool(
    function() "ready",
    "Report whether the custom tool is ready.",
    name = "custom_ready"
  )
  context <- list(
    worker = NULL,
    input = NULL,
    revision = NULL,
    session = NULL,
    example_dir = coworker_example_path()
  )
  provider <- function(received) {
    expect_setequal(names(received), names(context))
    list(custom_tool)
  }

  expect_s3_class(ambient$tempest, "tempest::TempestConfig")
  expect_identical(
    environment$cw_chat_model(ambient$tempest, "assistant"),
    "anthropic/claude-sonnet-4-20250514"
  )
  expect_identical(
    environment$cw_chat_model(explicit, "planner"),
    "openai/gpt-5-mini"
  )
  expect_identical(environment$cw_chat_role("assistant"), "coordinator")
  expect_identical(environment$cw_chat_role("planner"), "writer")
  expect_length(
    environment$cw_extension_tools(provider, context),
    1L
  )
  expect_identical(
    environment$cw_extension_tools(provider, context)[[1L]]@name,
    "custom_ready"
  )
})

test_that("coworker preserves Tempest chat templates and factories", {
  if (!coworker_runtime_available()) {
    testthat::skip("The current coworker runtime is unavailable.")
  }
  environment <- local_coworker_environment()
  withr::local_envvar(OPENAI_API_KEY = "not-a-real-key")
  template <- ellmer::chat_openai(
    system_prompt = "Keep my local provider instructions.",
    model = "gpt-4o-mini"
  )
  withr::local_options(tempest.chat = template)
  template_config <- environment$cw_app_config()
  assistant <- environment$cw_chat_client(
    "assistant",
    config = template_config$tempest
  )
  calls <- new.env(parent = emptyenv())
  factory_config <- tempest::tempest_config(
    models = "anthropic/claude-sonnet-4-20250514",
    chat_fn = function(role, model, system_prompt, echo) {
      calls$role <- role
      calls$model <- model
      calls$system_prompt <- system_prompt
      calls$echo <- echo
      template$clone(deep = TRUE)
    }
  )
  planner <- environment$cw_chat_client(
    "planner",
    config = factory_config
  )

  expect_match(
    assistant$get_system_prompt(),
    "You are Graft Coworker",
    fixed = TRUE
  )
  expect_match(
    assistant$get_system_prompt(),
    "Keep my local provider instructions.",
    fixed = TRUE
  )
  expect_identical(
    template$get_system_prompt(),
    "Keep my local provider instructions."
  )
  expect_identical(identical(assistant, template), FALSE)
  expect_s3_class(planner, "Chat")
  expect_identical(calls$role, "writer")
  expect_identical(
    calls$model,
    "anthropic/claude-sonnet-4-20250514"
  )
  expect_match(calls$system_prompt, "grounded work products")
  expect_identical(calls$echo, "none")
})

test_that("coworker offers a read-only btw tool profile", {
  if (
    !coworker_runtime_available() || !requireNamespace("btw", quietly = TRUE)
  ) {
    testthat::skip("The coworker runtime with btw is unavailable.")
  }
  environment <- local_coworker_environment(include_app = TRUE)
  tools <- environment$cw_btw_tools("read_only")
  tool_names <- vapply(tools, \(tool) tool@name, character(1))

  expect_gt(length(tool_names), 10L)
  expect_length(
    grep(
      paste(
        "write|edit|patch|replace|commit|branch_create|branch_checkout|",
        "pkg_|run_r|github|agent_subagent",
        sep = ""
      ),
      tool_names
    ),
    0L
  )
  expect_length(
    environment$cw_toolset(tools),
    length(tool_names)
  )
})

test_that("coworker prepares work without crossing the approval boundary", {
  if (!coworker_runtime_available()) {
    testthat::skip("The current coworker runtime is unavailable.")
  }
  environment <- local_coworker_environment()
  worker <- local_coworker_worker(environment)

  snapshot <- environment$cw_worker_prepare(
    worker,
    worker$bundle$suggested_request,
    environment$cw_reference_planner(worker$bundle)
  )

  expect_identical(snapshot$status, "awaiting_approval")
  expect_length(snapshot$pending, 1L)
  expect_identical(
    snapshot$pending[[1L]]$approval_kind,
    "artifact"
  )
  expect_match(snapshot$plan$plan_markdown, "Ask before publishing")
  expect_length(list.files(worker$output_dir), 0L)
  expect_equal(
    nrow(environment$cw_worker_records(worker, "WorkRun")),
    0L
  )
  expect_equal(
    nrow(environment$cw_worker_records(worker, "Memory")),
    0L
  )
})

test_that("coworker rejection publishes and remembers nothing", {
  if (!coworker_runtime_available()) {
    testthat::skip("The current coworker runtime is unavailable.")
  }
  environment <- local_coworker_environment()
  worker <- local_coworker_worker(environment)
  environment$cw_worker_prepare(
    worker,
    worker$bundle$suggested_request,
    environment$cw_reference_planner(worker$bundle)
  )

  snapshot <- environment$cw_worker_resolve(
    worker,
    "rejected",
    note = "The operator requested a revision."
  )

  expect_identical(snapshot$status, "failed")
  expect_length(snapshot$pending, 0L)
  expect_length(list.files(worker$output_dir), 0L)
  expect_equal(
    nrow(environment$cw_worker_records(worker, "Deliverable")),
    0L
  )
  expect_equal(
    nrow(environment$cw_worker_records(worker, "Memory")),
    0L
  )
})

test_that("coworker approval publishes and adds accepted continuity", {
  if (!coworker_runtime_available()) {
    testthat::skip("The current coworker runtime is unavailable.")
  }
  environment <- local_coworker_environment()
  worker <- local_coworker_worker(environment)
  pending <- environment$cw_worker_prepare(
    worker,
    worker$bundle$suggested_request,
    environment$cw_reference_planner(worker$bundle)
  )

  approved <- environment$cw_worker_resolve(
    worker,
    "approved",
    note = "The local operator approved this exact file."
  )
  published <- paste(
    readLines(approved$exported_path, warn = FALSE),
    collapse = "\n"
  )
  memories <- environment$cw_worker_records(worker, "Memory")
  approvals <- environment$cw_worker_records(
    worker,
    "ApprovalDecision"
  )

  expect_identical(approved$status, "succeeded")
  expect_identical(published, pending$deliverable)
  expect_equal(nrow(memories), 1L)
  expect_equal(
    nrow(environment$cw_worker_records(worker, "Deliverable")),
    1L
  )
  expect_equal(nrow(approvals), 1L)
  expect_identical(approvals$decision, "approved")
  expect_match(
    environment$cw_worker_memory_context(worker),
    pending$plan$summary,
    fixed = TRUE
  )

  next_run <- environment$cw_worker_prepare(
    worker,
    "Prepare tomorrow's follow-up.",
    environment$cw_reference_planner(worker$bundle)
  )
  expect_match(
    next_run$deliverable,
    "Earlier accepted workspace memory was supplied"
  )
  expect_equal(nrow(environment$cw_worker_records(worker, "Memory")), 1L)
})

test_that("coworker Shiny host exposes work, inbox, memory, and activity", {
  if (!coworker_runtime_available()) {
    testthat::skip("The current coworker runtime is unavailable.")
  }
  environment <- local_coworker_environment(include_app = TRUE)
  app_dir <- coworker_example_path("app")
  ui <- as.character(environment$cw_app_ui(app_dir))
  data_dir <- tempfile("graft-coworker-app-test-")
  worker_factory <- function(example_dir) {
    environment$cw_worker_new(example_dir, data_dir)
  }
  withr::local_options(
    tempest.chat = "openai/gpt-5-mini"
  )

  expect_null(attr(environment$cw_app_theme(), "brand"))
  expect_match(ui, "coworker_chat")
  expect_match(ui, "Run example")
  expect_match(ui, "Provider-free. No model key required.")
  expect_match(ui, "Approval inbox")
  expect_match(ui, "Accepted workspace memory")
  expect_match(ui, "Workflow activity")
  expect_match(ui, "work_context")
  expect_match(ui, "work_header")
  expect_match(ui, "<h1")
  expect_identical(
    environment$cw_app_demote_markdown_headings(
      "# Title\n\n## Section"
    ),
    "### Title\n\n#### Section"
  )

  shiny::testServer(
    environment$cw_app_server(
      coworker_example_path(),
      worker_factory = worker_factory,
      client_factory = environment$cw_chat_client
    ),
    {
      session$flushReact()
      expect_match(output$memory_body$html, "No accepted memory yet")
      expect_match(
        output$deliverable_body$html,
        "No published deliverables yet"
      )
      expect_match(
        output$approval_body$html,
        "No approval decisions yet"
      )
      expect_match(output$activity_body$html, "No workflow activity yet")
      expect_match(output$work_header$html, "Outcome workspace")
      expect_match(output$work_context$html, "3 sources")
      expect_match(output$work_context$html, "No accepted memory")
      expect_match(output$runtime_status$html, "openai/gpt-5-mini")
      expect_match(output$runtime_status$html, "2 tools loaded")

      session$setInputs(run_reference = 0)
      session$flushReact()
      session$setInputs(run_reference = 1)
      session$flushReact()

      expect_match(
        output$session_status$html,
        "awaiting approval"
      )
      expect_match(
        output$plan_body$html,
        "Project Atlas release-readiness brief"
      )
      expect_match(
        output$work_header$html,
        "Project Atlas release-readiness brief"
      )
      expect_match(output$plan_body$html, "Approval needed")
      expect_match(output$plan_body$html, "Review approval")
      expect_match(output$plan_body$html, "View task plan")
      expect_match(output$plan_body$html, "Needs your approval")
      expect_match(output$approval_inbox$html, "Review deliverable")
      expect_length(
        list.files(file.path(data_dir, "deliverables")),
        0L
      )

      session$setInputs(approve_current = 0)
      session$flushReact()
      session$setInputs(approve_current = 1)
      session$flushReact()

      expect_match(output$session_status$html, "succeeded")
      expect_match(output$plan_body$html, "Published and remembered")
      expect_match(output$work_context$html, "1 accepted memory")
      expect_length(
        list.files(file.path(data_dir, "deliverables")),
        1L
      )
      expect_named(
        environment$cw_app_memory_rows(
          environment$cw_worker_records(worker, "Memory")
        ),
        c("Accepted outcome", "Accepted")
      )
      expect_named(
        environment$cw_app_deliverable_rows(
          environment$cw_worker_records(worker, "Deliverable")
        ),
        c("Title", "Completed")
      )
      expect_named(
        environment$cw_app_approval_rows(
          environment$cw_worker_records(worker, "ApprovalDecision")
        ),
        c("Decision", "Reviewer", "Decided")
      )
      activity <- environment$cw_app_activity_rows(
        environment$cw_worker_events(worker)
      )
      expect_named(activity, c("#", "Event", "Status", "Workflow step"))
      expect_length(grep("_", activity[["Status"]], fixed = TRUE), 0L)
    }
  )
})

test_that("coworker approval empty states match the workflow outcome", {
  environment <- local_coworker_environment(include_app = TRUE)
  ready <- environment$cw_app_approval_card(
    list(pending = list(), status = "ready"),
    tempdir()
  )
  rejected <- environment$cw_app_approval_card(
    list(pending = list(), status = "failed"),
    tempdir()
  )
  succeeded <- environment$cw_app_approval_card(
    list(pending = list(), status = "succeeded"),
    tempdir()
  )

  expect_match(as.character(ready), "is-ready")
  expect_match(as.character(ready), "Inbox clear")
  expect_match(as.character(rejected), "is-rejected")
  expect_match(as.character(rejected), "Publication rejected")
  expect_match(as.character(rejected), "no draft memory entered")
  expect_match(as.character(succeeded), "is-succeeded")
  expect_match(as.character(succeeded), "approved, published locally")
})
