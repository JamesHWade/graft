mi_app_server <- function(
  example_dir,
  worker_factory = mi_worker_new,
  config = mi_app_config()
) {
  force(example_dir)
  force(worker_factory)
  if (!inherits(config, "graft_market_intelligence_config")) {
    stop("`config` must be created by `mi_app_config()`.")
  }

  function(input, output, session) {
    worker <- shiny::reactiveVal(worker_factory(example_dir))
    revision <- shiny::reactiveVal(0L)
    baseline <- mi_read_json(
      file.path(example_dir, "corpus", "baseline.json")
    )
    extension_context <- list(
      worker = worker,
      input = input,
      session = session,
      example_dir = example_dir
    )
    configured_tools <- mi_configured_tools(config, extension_context)

    session$onSessionEnded(function() {
      current <- shiny::isolate(worker())
      if (!is.null(current)) {
        mi_worker_close(current)
      }
    })

    current_snapshot <- shiny::reactive({
      revision()
      mi_worker_snapshot(worker())
    })

    current_progress <- shiny::reactive({
      revision()
      mi_worker_progress(worker())
    })

    bump_revision <- function() {
      revision(revision() + 1L)
    }

    focus_after_flush <- function(id) {
      session$onFlushed(
        function() session$sendCustomMessage("mi-focus", id),
        once = TRUE
      )
    }

    output$global_status <- shiny::renderUI({
      snapshot <- current_snapshot()
      progress <- current_progress()
      shiny::tagList(
        mi_app_status_badge(snapshot$status),
        shiny::tags$span(
          class = "mi-global-progress",
          paste(
            progress$resolved,
            "of",
            progress$total,
            "demo scans resolved"
          )
        )
      )
    })

    output$briefing_view <- shiny::renderUI({
      mi_app_briefing_view(
        worker(),
        current_snapshot(),
        current_progress(),
        length(configured_tools)
      )
    })

    output$portfolio_view <- shiny::renderUI({
      mi_app_portfolio_view(baseline)
    })

    output$review_view <- shiny::renderUI({
      mi_app_review_view(current_snapshot())
    })

    output$knowledge_view <- shiny::renderUI({
      revision()
      mi_app_knowledge_view(worker())
    })

    output$audit_view <- shiny::renderUI({
      revision()
      mi_app_audit_view(worker(), current_snapshot())
    })

    shiny::observeEvent(
      input$run_scan,
      {
        progress <- current_progress()
        bundle <- progress$next_bundle
        if (is.null(bundle)) {
          shiny::showNotification(
            "All demo scans are resolved. Restart from Audit to run them again.",
            type = "message"
          )
          return()
        }
        if (length(current_snapshot()$pending) > 0L) {
          shiny::showNotification(
            "Resolve the current assessment before starting another scan.",
            type = "warning"
          )
          bslib::nav_select("active_view", "review", session = session)
          return()
        }
        planner <- tryCatch(
          {
            if (isTRUE(input$use_model)) {
              mi_model_planner(mi_chat_client(
                config = config$tempest,
                tools = configured_tools
              ))
            } else {
              mi_reference_planner(bundle)
            }
          },
          error = function(error) {
            shiny::showNotification(
              conditionMessage(error),
              type = "error",
              duration = NULL
            )
            NULL
          }
        )
        if (is.null(planner)) {
          return()
        }
        result <- tryCatch(
          mi_worker_prepare(
            worker(),
            bundle = bundle,
            request = bundle$suggested_request,
            planner = planner
          ),
          error = function(error) {
            shiny::showNotification(
              conditionMessage(error),
              type = "error",
              duration = NULL
            )
            NULL
          }
        )
        if (is.null(result)) {
          return()
        }
        bump_revision()
        bslib::nav_select("active_view", "briefing", session = session)
        focus_after_flush("mi-briefing-state")
        shiny::showNotification(
          paste(
            "Briefing prepared.",
            "The assessment is waiting in Review."
          ),
          type = "message"
        )
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$approve_assessment,
      {
        note <- shiny::isolate(input$review_note)
        if (is.null(note) || !nzchar(trimws(note))) {
          note <- NULL
        }
        result <- tryCatch(
          mi_worker_resolve(
            worker(),
            "approved",
            note = note
          ),
          error = function(error) {
            shiny::showNotification(
              conditionMessage(error),
              type = "error",
              duration = NULL
            )
            NULL
          }
        )
        if (is.null(result)) {
          return()
        }
        bump_revision()
        bslib::nav_select("active_view", "knowledge", session = session)
        focus_after_flush("mi-knowledge-state")
        shiny::showNotification(
          "Assessment accepted into Graft with its evidence and action.",
          type = "message"
        )
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$reject_assessment,
      {
        note <- shiny::isolate(input$review_note)
        if (is.null(note) || !nzchar(trimws(note))) {
          note <- "Rejected by the local operator."
        }
        result <- tryCatch(
          mi_worker_resolve(
            worker(),
            "rejected",
            note = note
          ),
          error = function(error) {
            shiny::showNotification(
              conditionMessage(error),
              type = "error",
              duration = NULL
            )
            NULL
          }
        )
        if (is.null(result)) {
          return()
        }
        bump_revision()
        bslib::nav_select("active_view", "review", session = session)
        focus_after_flush("mi-review-state")
        shiny::showNotification(
          "Assessment rejected. No proposed interpretation entered Graft.",
          type = "warning"
        )
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$restart_demo,
      {
        old_worker <- worker()
        mi_worker_close(old_worker)
        worker(worker_factory(example_dir))
        bump_revision()
        bslib::nav_select("active_view", "briefing", session = session)
        focus_after_flush("mi-page-title")
        shiny::showNotification(
          "The local demo store was reset.",
          type = "message"
        )
      },
      ignoreInit = TRUE
    )
  }
}
