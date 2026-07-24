cw_app_escape_markdown <- function(text) {
  text <- gsub("&", "&amp;", text, fixed = TRUE)
  text <- gsub("<", "&lt;", text, fixed = TRUE)
  gsub(">", "&gt;", text, fixed = TRUE)
}

cw_app_demote_markdown_headings <- function(text) {
  text <- gsub("(?m)^(#{1,4})(?=\\s)", "##\\1", text, perl = TRUE)
  gsub("(?m)^#####(?=\\s)", "######", text, perl = TRUE)
}

cw_app_theme <- function() {
  bslib::bs_theme(
    version = 5,
    brand = FALSE,
    bg = "#f5f6f2",
    fg = "#1d2927",
    primary = "#315c50",
    secondary = "#b76b3f",
    success = "#2f7658",
    danger = "#a43f3a",
    base_font = bslib::font_collection(
      "Avenir Next",
      "Segoe UI",
      "Helvetica Neue",
      "sans-serif"
    ),
    heading_font = bslib::font_collection(
      "Avenir Next",
      "Segoe UI",
      "Helvetica Neue",
      "sans-serif"
    )
  )
}

cw_app_title <- function() {
  shiny::div(
    class = "coworker-brand",
    shiny::span(
      class = "coworker-mark",
      bsicons::bs_icon("diagram-3")
    ),
    shiny::span(
      shiny::strong("Graft Coworker"),
      shiny::tags$small("local work, reviewed memory")
    )
  )
}

cw_app_status_badge <- function(status) {
  label <- gsub("_", " ", status, fixed = TRUE)
  shiny::span(
    class = paste("coworker-status", paste0("is-", status)),
    label
  )
}

cw_app_project_records <- function(records, columns, labels) {
  missing_columns <- setdiff(columns, names(records))
  for (column in missing_columns) {
    records[[column]] <- rep(NA_character_, nrow(records))
  }
  projected <- records[, columns, drop = FALSE]
  names(projected) <- labels
  projected
}

cw_app_format_timestamp <- function(value) {
  if (length(value) == 0L) {
    return(character())
  }
  timestamp <- suppressWarnings(as.numeric(value))
  formatted <- format(
    as.POSIXct(timestamp, origin = "1970-01-01", tz = "UTC"),
    "%b %d, %Y %H:%M UTC"
  )
  formatted[is.na(timestamp)] <- ""
  formatted
}

cw_app_memory_rows <- function(records) {
  rows <- cw_app_project_records(
    records,
    c("content", "accepted_at"),
    c("Accepted outcome", "Accepted")
  )
  rows[["Accepted"]] <- cw_app_format_timestamp(rows[["Accepted"]])
  rows
}

cw_app_deliverable_rows <- function(records) {
  rows <- cw_app_project_records(
    records,
    c("title", "completed_at"),
    c("Title", "Completed")
  )
  rows[["Completed"]] <- cw_app_format_timestamp(rows[["Completed"]])
  rows
}

cw_app_approval_rows <- function(records) {
  rows <- cw_app_project_records(
    records,
    c("decision", "reviewer", "decided_at"),
    c("Decision", "Reviewer", "Decided")
  )
  rows[["Decided"]] <- cw_app_format_timestamp(rows[["Decided"]])
  rows
}

cw_app_activity_rows <- function(events) {
  rows <- cw_app_project_records(
    events,
    c("sequence", "event", "status", "step"),
    c("#", "Event", "Status", "Workflow step")
  )
  rows[["Status"]] <- gsub("_", " ", rows[["Status"]], fixed = TRUE)
  rows[["Workflow step"]][
    is.na(rows[["Workflow step"]]) | rows[["Workflow step"]] == ""
  ] <- "\u2014"
  rows
}

cw_app_empty_ledger <- function(title, copy) {
  shiny::div(
    class = "ledger-empty",
    shiny::strong(title),
    shiny::p(copy)
  )
}

cw_app_card_heading <- function(text, id = NULL) {
  shiny::tags$h2(
    id = id,
    class = "card-heading",
    tabindex = if (is.null(id)) NULL else "-1",
    text
  )
}

cw_app_work_header <- function(snapshot) {
  title <- if (is.null(snapshot$plan)) {
    "Outcome workspace"
  } else {
    snapshot$plan$title
  }
  shiny::div(
    class = "card-title-row",
    cw_app_card_heading(title, "work-session-heading"),
    shiny::span(class = "live-dot", "local")
  )
}

cw_app_context_chip <- function(icon, label) {
  shiny::span(
    class = "context-chip",
    bsicons::bs_icon(icon),
    label
  )
}

cw_app_runtime_status <- function(model, tool_count) {
  shiny::div(
    class = "runtime-status",
    shiny::div(
      class = "runtime-status-row",
      bsicons::bs_icon("cpu"),
      shiny::span(
        shiny::tags$small("Model"),
        shiny::strong(model)
      )
    ),
    shiny::div(
      class = "runtime-status-row",
      bsicons::bs_icon("tools"),
      shiny::span(
        shiny::tags$small("Tool belt"),
        shiny::strong(
          paste(
            tool_count,
            if (tool_count == 1L) "tool loaded" else "tools loaded"
          )
        )
      )
    )
  )
}

cw_app_work_context <- function(snapshot, bundle, memory_count) {
  source_kinds <- vapply(
    bundle$sources,
    `[[`,
    character(1),
    "source_kind"
  )
  source_names <- c(
    github = "GitHub",
    jira = "Jira",
    slack = "Slack"
  )
  source_labels <- unname(source_names[source_kinds])
  unknown_sources <- is.na(source_labels)
  source_labels[unknown_sources] <- tools::toTitleCase(
    source_kinds[unknown_sources]
  )
  source_label <- paste(
    source_labels,
    collapse = ", "
  )
  memory_label <- if (memory_count == 0L) {
    "No accepted memory"
  } else {
    paste(
      memory_count,
      "accepted",
      if (memory_count == 1L) "memory" else "memories"
    )
  }
  task_label <- if (is.null(snapshot$request)) {
    bundle$workspace$description
  } else {
    snapshot$request
  }
  shiny::div(
    class = "work-context",
    role = "region",
    `aria-label` = "Current task context",
    shiny::div(
      class = "context-identity",
      shiny::span(
        class = "context-icon",
        bsicons::bs_icon("folder2-open")
      ),
      shiny::span(
        shiny::strong(bundle$workspace$name),
        shiny::tags$small(task_label)
      )
    ),
    shiny::div(
      class = "context-chips",
      cw_app_context_chip(
        "link-45deg",
        paste(length(bundle$sources), "sources:", source_label)
      ),
      cw_app_context_chip("database-check", memory_label)
    )
  )
}

cw_app_ui <- function(app_dir) {
  bslib::page_sidebar(
    title = cw_app_title(),
    window_title = "Graft Coworker",
    lang = "en",
    theme = cw_app_theme(),
    sidebar = bslib::sidebar(
      width = 320,
      open = "desktop",
      shiny::div(
        class = "sidebar-eyebrow",
        "Current local session"
      ),
      shiny::div(
        class = "session-live",
        role = "status",
        `aria-live` = "polite",
        `aria-atomic` = "true",
        shiny::uiOutput("session_status")
      ),
      shiny::p(
        class = "sidebar-copy",
        paste(
          "Requests become typed Tempest runs. Finished files and durable",
          "memory enter Graft only after approval."
        )
      ),
      shiny::hr(),
      bslib::input_switch(
        "use_model_planner",
        "Use dsprrr model planner",
        value = TRUE
      ),
      shiny::p(
        class = "form-text",
        paste(
          "Chat uses your configured ellmer model.",
          "Turn this off to make tool runs use the provider-free planner."
        )
      ),
      shiny::uiOutput("runtime_status"),
      shiny::hr(),
      shiny::div(
        class = "local-first-note",
        shiny::strong("Local-first"),
        shiny::p(
          "Source snapshots, approved memory, and deliverables stay on this machine."
        )
      )
    ),
    shiny::tags$head(
      shiny::includeCSS(file.path(app_dir, "www", "coworker.css")),
      shiny::tags$script(shiny::HTML(
        paste(
          "Shiny.addCustomMessageHandler('coworker-focus', function(id) {",
          "  window.requestAnimationFrame(function() {",
          "    var target = document.getElementById(id);",
          "    if (target) target.focus();",
          "  });",
          "});",
          sep = "\n"
        )
      ))
    ),
    bslib::navset_card_underline(
      id = "coworker_workspace",
      bslib::nav_panel(
        "Work",
        shiny::h1(
          id = "work-heading",
          class = "visually-hidden",
          tabindex = "-1",
          "Work"
        ),
        shiny::uiOutput("work_context"),
        bslib::layout_columns(
          bslib::card(
            class = "chat-card",
            bslib::card_header(shiny::uiOutput("work_header")),
            shinychat::chat_ui(
              "coworker_chat",
              greeting = shinychat::chat_greeting(
                shiny::div(
                  class = "coworker-greeting",
                  shiny::h2("What should we finish?"),
                  shiny::p(
                    paste(
                      "Ask for a brief, report, or decision packet.",
                      "I will work from the bounded source bundle, show",
                      "the plan, and ask before publishing a file."
                    )
                  ),
                  shiny::actionButton(
                    "run_reference",
                    "Run example",
                    class = "btn-primary coworker-example-button"
                  ),
                  shiny::span(
                    class = "greeting-hint",
                    "Provider-free. No model key required."
                  )
                ),
                persistent = FALSE
              ),
              placeholder = "Describe the outcome you want...",
              height = "100%",
              footer = shiny::span(
                "Consequential output is approval-gated."
              )
            )
          ),
          shiny::div(
            class = "work-rail",
            bslib::card(
              class = "plan-card",
              bslib::card_header(cw_app_card_heading("Plan and progress")),
              bslib::card_body(shiny::uiOutput("plan_body"))
            ),
            bslib::card(
              class = "deliverable-card",
              full_screen = TRUE,
              bslib::card_header(cw_app_card_heading(
                "Deliverable preview",
                "deliverable-heading"
              )),
              bslib::card_body(shiny::uiOutput("deliverable_preview")),
              bslib::card_footer(shiny::uiOutput("deliverable_actions"))
            )
          ),
          col_widths = c(7, 5)
        )
      ),
      bslib::nav_panel(
        "Inbox",
        shiny::div(
          class = "section-intro",
          shiny::h1(
            id = "approval-heading",
            tabindex = "-1",
            "Approval inbox"
          ),
          shiny::p(
            paste(
              "A pending card is a hard boundary.",
              "Rejecting it leaves the file unpublished and Graft unchanged."
            )
          )
        ),
        shiny::uiOutput("approval_inbox")
      ),
      bslib::nav_panel(
        "Memory",
        shiny::div(
          class = "section-intro",
          shiny::h1(
            id = "memory-heading",
            tabindex = "-1",
            "Accepted workspace memory"
          ),
          shiny::p(
            paste(
              "These are approved outcomes, deliverables, and decisions.",
              "Draft chat and rejected work do not enter this ledger."
            )
          )
        ),
        bslib::layout_columns(
          bslib::card(
            bslib::card_header(cw_app_card_heading("Durable memories")),
            bslib::card_body(shiny::uiOutput("memory_body"))
          ),
          bslib::card(
            bslib::card_header(cw_app_card_heading("Published deliverables")),
            bslib::card_body(shiny::uiOutput("deliverable_body"))
          ),
          col_widths = c(6, 6)
        ),
        bslib::card(
          bslib::card_header(cw_app_card_heading("Approval decisions")),
          bslib::card_body(shiny::uiOutput("approval_body"))
        )
      ),
      bslib::nav_panel(
        "Activity",
        shiny::div(
          class = "section-intro",
          shiny::h1(
            id = "activity-heading",
            tabindex = "-1",
            "Workflow activity"
          ),
          shiny::p(
            "The current Tempest run exposes ordered lifecycle events."
          )
        ),
        bslib::card(
          full_screen = TRUE,
          bslib::card_header(cw_app_card_heading("Current run events")),
          bslib::card_body(shiny::uiOutput("activity_body"))
        )
      )
    )
  )
}

cw_app_progress_row <- function(icon, title, status, kind) {
  shiny::div(
    class = paste("progress-row", paste0("is-", kind)),
    role = "listitem",
    shiny::span(class = "progress-icon", bsicons::bs_icon(icon)),
    shiny::span(
      class = "progress-copy",
      shiny::strong(title),
      shiny::tags$small(status)
    )
  )
}

cw_app_plan_body <- function(snapshot) {
  if (is.null(snapshot$plan)) {
    return(shiny::div(
      class = "empty-rail",
      shiny::strong("Ready for an outcome"),
      shiny::p("The active plan will appear here as the coworker works.")
    ))
  }
  publication <- switch(
    snapshot$status,
    succeeded = list(
      icon = "check2",
      title = "Publish reviewed artifact",
      status = "Published and remembered",
      kind = "complete"
    ),
    failed = list(
      icon = "x-lg",
      title = "Publish reviewed artifact",
      status = "Stopped without publication",
      kind = "stopped"
    ),
    list(
      icon = "shield-check",
      title = "Publish reviewed artifact",
      status = "Needs your approval",
      kind = "attention"
    )
  )
  shiny::tagList(
    shiny::div(
      class = "plan-summary",
      cw_app_status_badge(snapshot$status),
      shiny::h3(snapshot$plan$title),
      shiny::p(snapshot$plan$summary)
    ),
    shiny::div(
      class = "progress-list",
      role = "list",
      `aria-label` = "Task progress",
      cw_app_progress_row(
        "check2",
        "Review bounded sources",
        "Complete",
        "complete"
      ),
      cw_app_progress_row(
        "file-earmark-text",
        "Prepare the deliverable",
        "Draft ready",
        "complete"
      ),
      cw_app_progress_row(
        publication$icon,
        publication$title,
        publication$status,
        publication$kind
      )
    ),
    if (length(snapshot$pending) > 0L) {
      shiny::div(
        class = "approval-check-in",
        shiny::span(
          class = "check-in-icon",
          bsicons::bs_icon("shield-exclamation")
        ),
        shiny::div(
          shiny::h4(
            id = "approval-check-in-heading",
            tabindex = "-1",
            "Approval needed"
          ),
          shiny::p(
            paste(
              "Review the exact file and target before anything is",
              "published or remembered."
            )
          )
        ),
        shiny::actionButton(
          "open_approval",
          "Review approval",
          class = "btn-sm btn-outline-primary"
        )
      )
    },
    shiny::tags$details(
      class = "plan-details",
      shiny::tags$summary("View task plan"),
      shiny::div(
        class = "plan-markdown",
        shiny::markdown(cw_app_escape_markdown(
          snapshot$plan$plan_markdown
        ))
      )
    )
  )
}

cw_app_deliverable_preview <- function(snapshot) {
  if (is.null(snapshot$deliverable)) {
    return(shiny::div(
      class = "empty-deliverable",
      shiny::div(
        class = "document-glyph",
        bsicons::bs_icon("file-earmark-text")
      ),
      shiny::h3("No deliverable yet"),
      shiny::p("The finished work product will be reviewable here.")
    ))
  }
  shiny::div(
    class = "deliverable-markdown",
    shiny::markdown(cw_app_escape_markdown(
      cw_app_demote_markdown_headings(snapshot$deliverable)
    ))
  )
}

cw_app_approval_card <- function(snapshot) {
  if (length(snapshot$pending) == 0L) {
    empty_state <- switch(
      snapshot$status,
      succeeded = list(
        kind = "succeeded",
        icon = "check2",
        title = "Inbox clear",
        message = paste(
          "The current deliverable was approved, published locally,",
          "and committed to Graft."
        )
      ),
      failed = list(
        kind = "rejected",
        icon = "x-lg",
        title = "Publication rejected",
        message = paste(
          "The file was not published, and no draft memory entered",
          "Graft."
        )
      ),
      list(
        kind = "ready",
        icon = "inbox",
        title = "Inbox clear",
        message = "Nothing needs your attention."
      )
    )
    return(shiny::div(
      class = paste("inbox-empty", paste0("is-", empty_state$kind)),
      shiny::div(
        class = "inbox-check",
        bsicons::bs_icon(empty_state$icon)
      ),
      shiny::h2(empty_state$title),
      shiny::p(empty_state$message)
    ))
  }
  approval <- snapshot$pending[[1L]]
  shiny::div(
    class = "approval-card",
    shiny::div(
      class = "approval-header",
      shiny::div(
        shiny::span(class = "approval-kicker", "File publication"),
        shiny::h2(snapshot$plan$title)
      ),
      cw_app_status_badge("awaiting_approval")
    ),
    shiny::p(class = "approval-reason", approval$reason),
    shiny::div(
      class = "approval-detail",
      shiny::strong("Proposed action"),
      shiny::p(snapshot$plan$action_summary),
      shiny::strong("Target"),
      shiny::code(snapshot$expected_export_path)
    ),
    shiny::div(
      class = "approval-buttons",
      shiny::actionButton(
        "review_current",
        "Review deliverable",
        class = "btn-outline-secondary"
      ),
      shiny::actionButton(
        "approve_current",
        "Approve and publish",
        class = "btn-primary"
      ),
      shiny::actionButton(
        "reject_current",
        "Reject",
        class = "btn-outline-danger"
      )
    )
  )
}
