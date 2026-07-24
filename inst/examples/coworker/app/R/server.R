cw_app_tool_response <- function(snapshot) {
  status <- gsub("_", " ", snapshot$status, fixed = TRUE)
  paste(
    paste0("### ", snapshot$plan$title),
    paste0("**Status:** ", status),
    snapshot$plan$summary,
    if (length(snapshot$pending) > 0L) {
      paste(
        "**Next:** Review the deliverable, then approve or reject",
        "its local publication in the Inbox."
      )
    } else {
      "**Next:** No approval is pending."
    },
    sep = "\n\n"
  )
}

cw_app_tools <- function(
  worker,
  input,
  revision,
  client_factory
) {
  prepare <- ellmer::tool(
    function(outcome, `_intent` = "") {
      use_model <- shiny::isolate(isTRUE(input$use_model_planner))
      planner <- if (use_model) {
        cw_model_planner(client_factory("planner"))
      } else {
        cw_reference_planner(worker$bundle)
      }
      snapshot <- cw_worker_prepare(worker, outcome, planner)
      revision(revision() + 1L)
      cw_app_tool_response(snapshot)
    },
    paste(
      "Prepare a concrete work product from the bounded workspace sources",
      "and accepted Graft memory. Use this for briefs, reports, summaries,",
      "and decision packets. The result may require local publication approval."
    ),
    arguments = list(
      outcome = ellmer::type_string(
        "The finished outcome the user wants, including audience and purpose."
      ),
      `_intent` = ellmer::type_string(
        "A short explanation of why this tool is needed."
      )
    ),
    name = "prepare_outcome",
    annotations = list(
      title = "Prepare outcome",
      description = "Build a governed deliverable with Tempest and dsprrr."
    )
  )
  recall <- ellmer::tool(
    function(query, `_intent` = "") {
      matches <- cw_worker_recall(worker, query)
      if (nrow(matches) == 0L) {
        return("No accepted Graft memory matched the query.")
      }
      jsonlite::toJSON(
        unclass(matches),
        auto_unbox = TRUE,
        pretty = TRUE
      )
    },
    paste(
      "Search accepted workspace memory in Graft.",
      "Use this before relying on an earlier decision or deliverable."
    ),
    arguments = list(
      query = ellmer::type_string("Words to search in accepted memory."),
      `_intent` = ellmer::type_string(
        "A short explanation of why memory could affect the answer."
      )
    ),
    name = "recall_memory",
    annotations = list(
      title = "Recall accepted memory",
      description = "Search durable reviewed workspace memory."
    )
  )
  list(prepare, recall)
}

cw_app_server <- function(
  example_dir,
  worker_factory = cw_worker_new,
  client_factory = cw_chat_client
) {
  force(example_dir)
  force(worker_factory)
  force(client_factory)
  function(input, output, session) {
    worker <- worker_factory(example_dir)
    revision <- shiny::reactiveVal(0L)
    current <- shiny::reactive({
      revision()
      cw_worker_snapshot(worker)
    })

    session$onSessionEnded(function() {
      cw_worker_close(worker)
    })

    client <- client_factory("assistant")
    client$register_tools(cw_app_tools(
      worker,
      input,
      revision,
      client_factory
    ))
    chat <- shinychat::chat_server("coworker_chat", client)

    memory_rows <- shiny::reactive({
      revision()
      cw_worker_records(worker, "Memory") |>
        cw_app_memory_rows()
    })
    deliverable_rows <- shiny::reactive({
      revision()
      cw_worker_records(worker, "Deliverable") |>
        cw_app_deliverable_rows()
    })
    approval_rows <- shiny::reactive({
      revision()
      cw_worker_records(worker, "ApprovalDecision") |>
        cw_app_approval_rows()
    })
    activity_rows <- shiny::reactive({
      revision()
      cw_worker_events(worker) |>
        cw_app_activity_rows()
    })

    output$work_header <- shiny::renderUI(cw_app_work_header(current()))
    output$work_context <- shiny::renderUI(cw_app_work_context(
      current(),
      worker$bundle,
      nrow(memory_rows())
    ))
    output$session_status <- shiny::renderUI({
      snapshot <- current()
      shiny::div(
        class = "session-status-panel",
        cw_app_status_badge(snapshot$status),
        shiny::span(
          class = "session-id",
          cw_or(snapshot$run_id, "No run yet")
        )
      )
    })
    output$plan_body <- shiny::renderUI(cw_app_plan_body(current()))
    output$deliverable_preview <- shiny::renderUI(
      cw_app_deliverable_preview(current())
    )
    output$deliverable_actions <- shiny::renderUI({
      snapshot <- current()
      if (
        !identical(snapshot$status, "succeeded") ||
          is.null(snapshot$exported_path)
      ) {
        return(shiny::span(
          class = "footer-hint",
          "Approval publishes the reviewed Markdown file."
        ))
      }
      shiny::tagList(
        shiny::span(
          class = "published-path",
          snapshot$exported_path
        ),
        shiny::downloadButton(
          "download_deliverable",
          "Download",
          class = "btn-sm btn-outline-primary"
        )
      )
    })
    output$download_deliverable <- shiny::downloadHandler(
      filename = function() {
        basename(current()$exported_path)
      },
      content = function(file) {
        file.copy(current()$exported_path, file, overwrite = TRUE)
      }
    )
    output$approval_inbox <- shiny::renderUI(
      cw_app_approval_card(current(), worker$output_dir)
    )
    output$memory_body <- shiny::renderUI({
      if (nrow(memory_rows()) == 0L) {
        return(cw_app_empty_ledger(
          "No accepted memory yet",
          "Approved outcomes will appear here after publication."
        ))
      }
      shiny::tableOutput("memory_table")
    })
    output$deliverable_body <- shiny::renderUI({
      if (nrow(deliverable_rows()) == 0L) {
        return(cw_app_empty_ledger(
          "No published deliverables yet",
          "Reviewed files appear here only after approval."
        ))
      }
      shiny::tableOutput("deliverable_table")
    })
    output$approval_body <- shiny::renderUI({
      if (nrow(approval_rows()) == 0L) {
        return(cw_app_empty_ledger(
          "No approval decisions yet",
          "Approve or reject a pending publication to create a decision."
        ))
      }
      shiny::tableOutput("approval_table")
    })
    output$activity_body <- shiny::renderUI({
      if (nrow(activity_rows()) == 0L) {
        return(cw_app_empty_ledger(
          "No workflow activity yet",
          "Run a request to see its ordered Tempest lifecycle."
        ))
      }
      shiny::tableOutput("activity_table")
    })
    output$memory_table <- shiny::renderTable(
      memory_rows(),
      striped = TRUE,
      hover = TRUE,
      spacing = "s"
    )
    output$deliverable_table <- shiny::renderTable(
      deliverable_rows(),
      striped = TRUE,
      hover = TRUE,
      spacing = "s"
    )
    output$approval_table <- shiny::renderTable(
      approval_rows(),
      striped = TRUE,
      hover = TRUE,
      spacing = "s"
    )
    output$activity_table <- shiny::renderTable(
      activity_rows(),
      striped = TRUE,
      hover = TRUE,
      spacing = "s"
    )

    shiny::observeEvent(
      input$run_reference,
      {
        succeeded <- tryCatch(
          {
            if (length(current()$pending) > 0L) {
              stop("Resolve the current approval before starting another run.")
            }
            snapshot <- cw_worker_prepare(
              worker,
              worker$bundle$suggested_request,
              cw_reference_planner(worker$bundle)
            )
            revision(revision() + 1L)
            chat$append(
              worker$bundle$suggested_request,
              role = "user"
            )
            chat$append(
              cw_app_tool_response(snapshot),
              role = "assistant"
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
        if (succeeded) {
          bslib::nav_select(
            "coworker_workspace",
            "Work",
            session = session
          )
          session$onFlushed(
            function() {
              session$sendCustomMessage(
                "coworker-focus",
                "approval-check-in-heading"
              )
            },
            once = TRUE
          )
        }
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$open_approval,
      {
        bslib::nav_select(
          "coworker_workspace",
          "Inbox",
          session = session
        )
        session$onFlushed(
          function() {
            session$sendCustomMessage(
              "coworker-focus",
              "approval-heading"
            )
          },
          once = TRUE
        )
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$review_current,
      {
        bslib::nav_select(
          "coworker_workspace",
          "Work",
          session = session
        )
        session$onFlushed(
          function() {
            session$sendCustomMessage(
              "coworker-focus",
              "deliverable-heading"
            )
          },
          once = TRUE
        )
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$approve_current,
      {
        tryCatch(
          {
            snapshot <- cw_worker_resolve(
              worker,
              "approved",
              note = "Approved in the Graft Coworker approval inbox."
            )
            revision(revision() + 1L)
            chat$append(
              paste(
                "### Published and remembered",
                paste(
                  "The reviewed file was published locally. Its outcome,",
                  "approval, and memory are now committed to Graft."
                ),
                paste0("**File:** `", snapshot$exported_path, "`"),
                sep = "\n\n"
              ),
              role = "assistant"
            )
            shiny::showNotification(
              "Published locally and committed to Graft.",
              type = "message",
              duration = 4
            )
            session$onFlushed(
              function() {
                session$sendCustomMessage(
                  "coworker-focus",
                  "approval-heading"
                )
              },
              once = TRUE
            )
          },
          error = function(error) {
            shiny::showNotification(
              conditionMessage(error),
              type = "error",
              duration = NULL
            )
          }
        )
      },
      ignoreInit = TRUE
    )

    shiny::observeEvent(
      input$reject_current,
      {
        tryCatch(
          {
            cw_worker_resolve(
              worker,
              "rejected",
              note = "Rejected in the Graft Coworker approval inbox."
            )
            revision(revision() + 1L)
            chat$append(
              paste(
                "### Publication rejected",
                paste(
                  "The file was not published, and no draft memory",
                  "entered Graft."
                ),
                sep = "\n\n"
              ),
              role = "assistant"
            )
            shiny::showNotification(
              "Rejected without publishing or committing memory.",
              type = "warning",
              duration = 4
            )
            session$onFlushed(
              function() {
                session$sendCustomMessage(
                  "coworker-focus",
                  "approval-heading"
                )
              },
              once = TRUE
            )
          },
          error = function(error) {
            shiny::showNotification(
              conditionMessage(error),
              type = "error",
              duration = NULL
            )
          }
        )
      },
      ignoreInit = TRUE
    )
    invisible(list(worker = worker, chat = chat, revision = revision))
  }
}
