test_that("market planner contract stays application-owned and generic", {
  if (!market_intelligence_runtime_available()) {
    testthat::skip("The current market-intelligence runtime is unavailable.")
  }
  environment <- local_market_intelligence_environment()
  bundle <- environment$mi_read_json(
    market_intelligence_example_path(
      "corpus",
      "2026-07-23-quarterly-results.json"
    )
  )
  planner <- environment$mi_reference_planner(bundle)
  result <- environment$mi_run_planner(
    planner,
    bundle$suggested_request,
    bundle,
    "No accepted market assessments yet."
  )
  host <- unlist(lapply(
    c("planner.R", "workflow.R", "worker.R"),
    function(path) {
      readLines(
        market_intelligence_example_path("R", path),
        warn = FALSE
      )
    }
  ))
  schema <- kg_schema(
    market_intelligence_example_path(
      "schema",
      "market-intelligence.graft.json"
    )
  )

  expect_s3_class(planner, "Module")
  expect_named(
    result,
    c(
      "headline",
      "summary",
      "implication",
      "materiality",
      "confidence",
      "action_title",
      "action_owner",
      "due_date",
      "continuity",
      "briefing_markdown",
      "memory_used",
      "businesses",
      "competitors",
      "downstream_markets",
      "sources",
      "observations"
    )
  )
  expect_identical(result$memory_used, FALSE)
  expect_match(result$briefing_markdown, "Approval")
  expect_length(
    grep("Data-center materials|LyondellBasell|BASF", host),
    0L
  )
  expect_setequal(
    kg_classes(schema)$class,
    c(
      "Assessment",
      "Business",
      "Competitor",
      "DownstreamMarket",
      "IntelligenceAction",
      "MonitorRun",
      "Observation",
      "SourceDocument"
    )
  )
})

test_that("market planner visibly uses accepted memory", {
  if (!market_intelligence_runtime_available()) {
    testthat::skip("The current market-intelligence runtime is unavailable.")
  }
  environment <- local_market_intelligence_environment()
  bundle <- environment$mi_read_json(
    market_intelligence_example_path(
      "corpus",
      "2026-07-24-competitor-moves.json"
    )
  )
  result <- environment$mi_run_planner(
    environment$mi_reference_planner(bundle),
    bundle$suggested_request,
    bundle,
    paste(
      "- Data-center materials emerge as a cross-business demand signal:",
      "retain the accepted cross-business watch theme."
    )
  )

  expect_identical(result$memory_used, TRUE)
  expect_match(result$continuity, "accepted Graft assessments")
  expect_match(result$briefing_markdown, "## Continuity")
})

test_that("market worker keeps assessment outside Graft until approval", {
  if (!market_intelligence_runtime_available()) {
    testthat::skip("The current market-intelligence runtime is unavailable.")
  }
  environment <- local_market_intelligence_environment()
  worker <- local_market_intelligence_worker(environment)

  pending <- environment$mi_worker_prepare(worker)

  expect_identical(pending$status, "awaiting_approval")
  expect_length(pending$pending, 1L)
  expect_equal(
    nrow(environment$mi_worker_records(worker, "Assessment")),
    0L
  )
  expect_equal(
    nrow(environment$mi_worker_records(worker, "Observation")),
    0L
  )

  accepted <- environment$mi_worker_resolve(
    worker,
    "approved",
    note = "Accepted for the market watch."
  )

  expect_identical(accepted$status, "succeeded")
  expect_equal(
    nrow(environment$mi_worker_records(worker, "Assessment")),
    1L
  )
  expect_equal(
    nrow(environment$mi_worker_records(worker, "Observation")),
    3L
  )
  expect_equal(
    nrow(environment$mi_worker_records(worker, "IntelligenceAction")),
    1L
  )
  expect_equal(
    nrow(environment$mi_worker_records(worker, "MonitorRun")),
    1L
  )
})

test_that("later market scan changes with accepted Graft history", {
  if (!market_intelligence_runtime_available()) {
    testthat::skip("The current market-intelligence runtime is unavailable.")
  }
  environment <- local_market_intelligence_environment()
  worker <- local_market_intelligence_worker(environment)
  environment$mi_worker_prepare(worker)
  environment$mi_worker_resolve(worker, "approved")

  second <- environment$mi_worker_prepare(worker)

  expect_identical(second$status, "awaiting_approval")
  expect_identical(second$briefing$memory_used, TRUE)
  expect_match(second$briefing$continuity, "accepted Graft assessments")

  rejected <- environment$mi_worker_resolve(
    worker,
    "rejected",
    note = "Needs a tighter competitor comparison."
  )

  expect_identical(rejected$status, "failed")
  expect_equal(
    nrow(environment$mi_worker_records(worker, "Assessment")),
    1L
  )
  expect_equal(environment$mi_worker_progress(worker)$remaining, 0L)
})

test_that("market intelligence preserves Tempest model configuration", {
  if (!market_intelligence_runtime_available()) {
    testthat::skip("The current market-intelligence runtime is unavailable.")
  }
  environment <- local_market_intelligence_environment()
  withr::local_options(
    tempest.chat = "anthropic/claude-sonnet-4-20250514"
  )
  ambient <- environment$mi_app_config()
  explicit <- tempest::tempest_config(models = "openai/gpt-5-mini")
  calls <- new.env(parent = emptyenv())
  withr::local_envvar(OPENAI_API_KEY = "not-a-real-key")
  template <- ellmer::chat_openai(
    system_prompt = "Preserve my internal provider policy.",
    model = "gpt-4o-mini"
  )
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
  client <- environment$mi_chat_client(factory_config)

  expect_s3_class(ambient$tempest, "tempest::TempestConfig")
  expect_identical(
    environment$mi_chat_model(ambient$tempest),
    "anthropic/claude-sonnet-4-20250514"
  )
  expect_identical(
    environment$mi_chat_model(explicit),
    "openai/gpt-5-mini"
  )
  expect_s3_class(client, "Chat")
  expect_identical(calls$role, "writer")
  expect_match(calls$system_prompt, "materials-market intelligence")
  expect_identical(calls$echo, "none")
})

test_that("market intelligence accepts extensible read-only tools", {
  if (!market_intelligence_runtime_available()) {
    testthat::skip("The current market-intelligence runtime is unavailable.")
  }
  environment <- local_market_intelligence_environment()
  custom_tool <- ellmer::tool(
    function() "ready",
    "Report whether the market source is ready.",
    name = "market_source_ready"
  )
  context <- list(worker = NULL, session = NULL)
  provider <- function(received) {
    expect_setequal(names(received), names(context))
    list(custom_tool)
  }
  config <- environment$mi_app_config(
    tools = provider,
    btw = FALSE
  )
  tools <- environment$mi_configured_tools(config, context)

  expect_length(tools, 1L)
  expect_identical(tools[[1L]]@name, "market_source_ready")
})

test_that("market intelligence schema artifact is current", {
  output <- withr::local_tempfile(fileext = ".json")
  kg_compile_schema(
    market_intelligence_example_path(
      "schema",
      "market-intelligence.linkml.yaml"
    ),
    output
  )

  expect_identical(
    readLines(output, warn = FALSE),
    readLines(
      market_intelligence_example_path(
        "schema",
        "market-intelligence.graft.json"
      ),
      warn = FALSE
    )
  )
})

test_that("market intelligence UI exposes the complete decision loop", {
  if (!market_intelligence_runtime_available()) {
    testthat::skip("The current market-intelligence runtime is unavailable.")
  }
  environment <- local_market_intelligence_environment(include_app = TRUE)
  ui <- as.character(environment$mi_app_ui())
  baseline <- environment$mi_read_json(
    market_intelligence_example_path("corpus", "baseline.json")
  )
  portfolio <- as.character(
    environment$mi_app_portfolio_view(baseline)
  )

  expect_match(ui, "Materials Market Radar")
  expect_match(ui, "Briefing")
  expect_match(ui, "Portfolio map")
  expect_match(ui, "Review")
  expect_match(ui, "Knowledge")
  expect_match(ui, "Audit")
  expect_match(ui, "mi-focus")
  expect_match(portfolio, "LyondellBasell")
  expect_match(portfolio, "Downstream lenses")
  expect_identical(
    gregexpr("fluidPage", ui, fixed = TRUE)[[1L]][[1L]],
    -1L
  )
})
