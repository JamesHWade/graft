ci_app_server <- function(example_dir, scenario_factory = ci_scenario_new) {
  force(example_dir)
  force(scenario_factory)
  function(input, output, session) {
    scenario <- shiny::reactiveVal(scenario_factory(example_dir))
    revision <- shiny::reactiveVal(0L)

    current <- shiny::reactive({
      revision()
      scenario()
    })
    current_stage <- shiny::reactive(ci_scenario_stage(current()))

    session$onSessionEnded(function() {
      ci_scenario_close(shiny::isolate(scenario()))
    })

    output$stage_phase <- shiny::renderText(current_stage()$phase)
    output$stage_title <- shiny::renderText(current_stage()$title)
    output$stage_summary <- shiny::renderUI(
      ci_app_stage_summary(current_stage())
    )
    output$action_controls <- shiny::renderUI(
      ci_app_action_controls(current(), current_stage())
    )

    output$briefing_count <- shiny::renderText(
      paste0(length(current()$state$monitor_runs), " / 3")
    )
    output$handoff_count <- shiny::renderText(
      length(current()$state$ingests)
    )
    output$pending_count <- shiny::renderText({
      as.integer(
        current()$stage %in%
          c(
            "supplier-knowledge",
            "independent-knowledge",
            "workflow-promotion",
            "decision-approval"
          )
      )
    })
    output$active_position <- shiny::renderText(
      ci_app_active_position(current())
    )

    output$briefing_header <- shiny::renderUI({
      content <- ci_app_latest_monitor_content(current())
      if (is.null(content)) {
        return(shiny::tagList(
          shiny::span("Executive morning brief"),
          shiny::span(class = "status-badge is-waiting", "not run")
        ))
      }
      shiny::tagList(
        shiny::span(content$title),
        shiny::span(
          class = paste("status-badge", paste0("is-", content$status)),
          gsub("_", " ", content$status, fixed = TRUE)
        )
      )
    })
    output$briefing_body <- shiny::renderUI({
      briefing <- ci_app_latest_briefing(current())
      if (is.null(briefing)) {
        return(shiny::div(
          class = "empty-state briefing-empty",
          shiny::div(class = "sunrise-mark", `aria-hidden` = "true"),
          shiny::h3("The room is quiet before the first scan"),
          shiny::p(
            paste(
              "Run morning one to reconcile the frozen signal bundle",
              "against accepted Graft context."
            )
          )
        ))
      }
      shiny::div(
        class = "briefing-markdown",
        shiny::markdown(ci_app_escape_markdown(briefing))
      )
    })
    output$scenario_timeline <- shiny::renderUI(
      ci_app_timeline_tags(current())
    )
    output$decision_packet <- shiny::renderUI(
      ci_app_decision_packet(current())
    )
    output$memory_comparison <- shiny::renderUI(
      ci_app_memory_comparison(current())
    )
    output$decision_records <- shiny::renderTable(
      ci_app_decision_records(current()),
      striped = TRUE,
      hover = TRUE,
      spacing = "s"
    )
    output$decision_evidence <- shiny::renderTable(
      ci_app_decision_evidence(current()),
      striped = TRUE,
      hover = TRUE,
      spacing = "s"
    )
    output$batch_history <- shiny::renderTable(
      ci_app_batch_history(current()),
      striped = TRUE,
      hover = TRUE,
      spacing = "s"
    )
    output$workflow_runs <- shiny::renderTable(
      ci_app_workflow_runs(current()),
      striped = TRUE,
      hover = TRUE,
      spacing = "s"
    )

    active_stages <- c(
      "welcome",
      "supplier-briefing",
      "supplier-knowledge",
      "independent-briefing",
      "independent-knowledge",
      "workflow-promotion",
      "decision-approval",
      "no-change-briefing"
    )
    advance_observers <- lapply(active_stages, function(expected_stage) {
      shiny::observeEvent(
        input[[ci_app_stage_input_id("advance", expected_stage)]],
        {
          if (!identical(current()$stage, expected_stage)) {
            return()
          }
          stage <- current_stage()
          succeeded <- tryCatch(
            {
              shiny::withProgress(
                message = stage$action_label,
                value = 0.5,
                ci_scenario_advance(shiny::isolate(scenario()))
              )
              TRUE
            },
            error = function(error) {
              shiny::showNotification(
                conditionMessage(error),
                type = "error",
                duration = NULL
              )
              FALSE
            }
          )
          revision(revision() + 1L)
          session$sendCustomMessage("ci-scroll-stage", list())
          if (succeeded) {
            shiny::showNotification(
              "The scenario advanced through its governed boundary.",
              type = "message",
              duration = 3
            )
          }
        },
        ignoreInit = TRUE
      )
    })
    stop_observers <- lapply(active_stages, function(expected_stage) {
      shiny::observeEvent(
        input[[ci_app_stage_input_id("stop", expected_stage)]],
        {
          if (!identical(current()$stage, expected_stage)) {
            return()
          }
          ci_scenario_stop(shiny::isolate(scenario()))
          revision(revision() + 1L)
          session$sendCustomMessage("ci-scroll-stage", list())
          shiny::showNotification(
            paste(
              "Stopped before the pending action.",
              "No later boundary was crossed."
            ),
            type = "warning",
            duration = 5
          )
        },
        ignoreInit = TRUE
      )
    })

    shiny::observeEvent(
      input$reset_scenario,
      {
        if (identical(current()$status, "active")) {
          return()
        }
        replacement <- tryCatch(
          scenario_factory(example_dir),
          error = function(error) {
            shiny::showNotification(
              conditionMessage(error),
              type = "error",
              duration = NULL
            )
            NULL
          }
        )
        if (!is.null(replacement)) {
          previous <- shiny::isolate(scenario())
          scenario(replacement)
          revision(revision() + 1L)
          session$sendCustomMessage("ci-scroll-stage", list())
          ci_scenario_close(previous)
        }
      },
      ignoreInit = TRUE
    )
    invisible(list(advance_observers, stop_observers))
  }
}
