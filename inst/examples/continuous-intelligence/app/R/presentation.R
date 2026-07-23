ci_app_escape_markdown <- function(text) {
  text <- gsub("&", "&amp;", text, fixed = TRUE)
  text <- gsub("<", "&lt;", text, fixed = TRUE)
  gsub(">", "&gt;", text, fixed = TRUE)
}

ci_app_theme <- function() {
  bslib::bs_theme(
    version = 5,
    bg = "#f5f1e8",
    fg = "#163033",
    primary = "#006e73",
    secondary = "#c88b35",
    success = "#287a55",
    danger = "#ad3d38",
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

ci_app_title <- function() {
  shiny::h1(
    class = "app-title",
    shiny::span(class = "app-kicker", "BLUE-SKY"),
    shiny::span("Briefing Room")
  )
}

ci_app_card_title <- function(...) {
  shiny::h2(class = "card-heading", ...)
}

ci_app_scope_markdown_headings <- function(text) {
  gsub(
    "(?m)^(#{1,4})([[:space:]])",
    "##\\1\\2",
    text,
    perl = TRUE
  )
}

ci_app_ui <- function() {
  bslib::page_sidebar(
    title = ci_app_title(),
    window_title = "Blue-Sky Briefing Room",
    lang = "en",
    theme = ci_app_theme(),
    sidebar = bslib::sidebar(
      width = 330,
      open = "desktop",
      shiny::div(
        class = "stage-panel",
        shiny::div(
          class = "stage-phase",
          shiny::textOutput("stage_phase", inline = TRUE)
        ),
        shiny::h2(shiny::textOutput("stage_title", inline = TRUE)),
        shiny::uiOutput("stage_summary"),
        shiny::uiOutput("action_controls")
      ),
      shiny::hr(),
      shiny::div(
        class = "guardrail-note",
        shiny::strong("Operating boundary"),
        shiny::p(
          paste(
            "Briefings can propose. Only explicit review actions change",
            "accepted Graft knowledge or open another Tempest workflow."
          )
        )
      )
    ),
    bslib::layout_column_wrap(
      width = "150px",
      fill = FALSE,
      class = "metric-grid",
      bslib::value_box(
        title = "Scheduled briefings",
        value = shiny::textOutput("briefing_count", inline = TRUE),
        theme = "primary",
        class = "metric-box"
      ),
      bslib::value_box(
        title = "Approved handoffs",
        value = shiny::textOutput("handoff_count", inline = TRUE),
        theme = "success",
        class = "metric-box"
      ),
      bslib::value_box(
        title = "Action queue",
        value = shiny::textOutput("pending_count", inline = TRUE),
        theme = "warning",
        class = "metric-box"
      ),
      bslib::value_box(
        title = "Active position",
        value = shiny::textOutput("active_position", inline = TRUE),
        theme = "secondary",
        class = "metric-box"
      )
    ),
    bslib::navset_underline(
      id = "workspace",
      bslib::nav_panel(
        "Morning brief",
        bslib::layout_columns(
          col_widths = c(8, 4),
          bslib::card(
            full_screen = TRUE,
            class = "briefing-card",
            bslib::card_header(shiny::uiOutput("briefing_header")),
            bslib::card_body(shiny::uiOutput("briefing_body"))
          ),
          bslib::card(
            full_screen = TRUE,
            bslib::card_header(
              ci_app_card_title("Three-morning timeline")
            ),
            bslib::card_body(shiny::uiOutput("scenario_timeline"))
          )
        )
      ),
      bslib::nav_panel(
        "Decision room",
        bslib::layout_columns(
          col_widths = c(7, 5),
          bslib::card(
            full_screen = TRUE,
            bslib::card_header(
              ci_app_card_title("Current decision packet")
            ),
            bslib::card_body(shiny::uiOutput("decision_packet"))
          ),
          bslib::card(
            full_screen = TRUE,
            bslib::card_header(
              ci_app_card_title("Why governed memory matters")
            ),
            bslib::card_body(shiny::uiOutput("memory_comparison"))
          )
        )
      ),
      bslib::nav_panel(
        "Knowledge ledger",
        bslib::layout_columns(
          col_widths = c(7, 5),
          bslib::card(
            full_screen = TRUE,
            bslib::card_header(
              ci_app_card_title("Review decisions in Graft")
            ),
            bslib::card_body(shiny::div(
              class = "table-responsive",
              shiny::tableOutput("decision_records")
            ))
          ),
          bslib::card(
            full_screen = TRUE,
            bslib::card_header(
              ci_app_card_title(
                "Evidence bound to the active position"
              )
            ),
            bslib::card_body(shiny::div(
              class = "table-responsive",
              shiny::tableOutput("decision_evidence")
            ))
          )
        )
      ),
      bslib::nav_panel(
        "Audit trail",
        bslib::layout_columns(
          col_widths = c(6, 6),
          bslib::card(
            full_screen = TRUE,
            bslib::card_header(
              ci_app_card_title("Committed Graft batches")
            ),
            bslib::card_body(shiny::div(
              class = "table-responsive",
              shiny::tableOutput("batch_history")
            ))
          ),
          bslib::card(
            full_screen = TRUE,
            bslib::card_header(
              ci_app_card_title("Tempest workflow runs")
            ),
            bslib::card_body(shiny::div(
              class = "table-responsive",
              shiny::tableOutput("workflow_runs")
            ))
          )
        )
      )
    ),
    shiny::includeCSS("www/briefing-room.css"),
    shiny::tags$script(shiny::HTML(
      paste(
        paste0(
          "Shiny.addCustomMessageHandler('ci-scroll-stage', ",
          "function(message) {"
        ),
        "const sidebar = document.querySelector('aside.sidebar');",
        "if (sidebar) sidebar.scrollTop = 0;",
        "});"
      )
    ))
  )
}

ci_app_timeline_tags <- function(scenario) {
  timeline <- ci_scenario_timeline(scenario)
  items <- lapply(seq_len(nrow(timeline)), function(index) {
    row <- timeline[index, , drop = FALSE]
    shiny::tags$li(
      class = paste("timeline-item", paste0("is-", row$status)),
      shiny::span(class = "timeline-marker", `aria-hidden` = "true"),
      shiny::span(class = "timeline-label", row$label),
      shiny::span(class = "timeline-status", row$status)
    )
  })
  shiny::tags$ol(class = "scenario-timeline", items)
}

ci_app_stage_summary <- function(stage) {
  if (identical(stage$format, "markdown")) {
    return(shiny::p(
      paste(
        "The scheduled monitor has completed. Read the briefing, then",
        "continue to the next governed boundary."
      )
    ))
  }
  shiny::p(stage$detail)
}

ci_app_stage_input_id <- function(action, stage_id) {
  paste(action, gsub("-", "_", stage_id, fixed = TRUE), sep = "_")
}

ci_app_action_controls <- function(scenario, stage) {
  if (!identical(scenario$status, "active")) {
    return(shiny::actionButton(
      "reset_scenario",
      "Start over",
      class = "btn-primary w-100"
    ))
  }
  shiny::tagList(
    shiny::actionButton(
      ci_app_stage_input_id("advance", stage$id),
      stage$action_label,
      class = "btn-primary w-100"
    ),
    shiny::actionButton(
      ci_app_stage_input_id("stop", stage$id),
      "Stop here",
      class = "btn-outline-secondary w-100 mt-2"
    )
  )
}

ci_app_decision_packet <- function(scenario) {
  content <- ci_app_decision_content(scenario)
  if (is.null(content)) {
    return(shiny::div(
      class = "empty-state",
      shiny::h3("No promoted decision yet"),
      shiny::p(
        paste(
          "A material briefing must first produce a referral, and an",
          "operator must explicitly promote it."
        )
      )
    ))
  }
  option_items <- lapply(content$options, function(option) {
    shiny::tags$li(
      shiny::strong(option$option),
      shiny::span(option$consequence)
    )
  })
  shiny::div(
    class = "decision-packet",
    shiny::div(class = "packet-label", "Prior accepted position"),
    shiny::p(content$prior_position),
    shiny::div(class = "packet-label", "Why now"),
    shiny::p(content$why_now),
    shiny::div(class = "packet-label", "Options considered"),
    shiny::tags$ul(class = "decision-options", option_items),
    shiny::div(class = "packet-label", "Recommendation"),
    shiny::p(class = "recommendation", content$recommendation),
    shiny::div(class = "packet-label", "Remaining uncertainty"),
    shiny::p(content$uncertainty),
    shiny::div(
      class = "decision-owner",
      shiny::strong("Owner: "),
      content$owner,
      shiny::br(),
      shiny::strong("Next: "),
      content$next_step
    )
  )
}

ci_app_memory_comparison <- function(scenario) {
  content <- ci_app_decision_content(scenario)
  governed <- if (is.null(content)) {
    paste(
      "Accepted history is available, but no promoted workflow has yet",
      "bound the new evidence to a reviewable decision."
    )
  } else {
    paste(
      "The workflow can name the prior position, cite",
      length(content$evidence_record_ids),
      "accepted evidence records, and propose an explicit supersession."
    )
  }
  shiny::div(
    class = "comparison-stack",
    shiny::div(
      class = "comparison-card without-memory",
      shiny::div(class = "comparison-label", "Briefing alone"),
      shiny::h3("A useful summary, but no controlled continuity"),
      shiny::p(
        paste(
          "A fresh report can repeat the 105 Nm result and thermal limit.",
          "It cannot establish which prior decision was accepted, whether",
          "the evidence passed review, or what the new decision supersedes."
        )
      )
    ),
    shiny::div(
      class = "comparison-card with-memory",
      shiny::div(class = "comparison-label", "Tempest + Graft"),
      shiny::h3("A decision with provenance and a future"),
      shiny::p(governed)
    )
  )
}
