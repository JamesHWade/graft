mi_app_theme <- function() {
  bslib::bs_theme(
    version = 5,
    bg = "#f6f7f9",
    fg = "#17202a",
    primary = "#235b4e",
    secondary = "#5f6b76",
    success = "#18794e",
    warning = "#a15c00",
    danger = "#b42318",
    base_font = bslib::font_collection(
      "-apple-system",
      "BlinkMacSystemFont",
      "Segoe UI",
      "sans-serif"
    ),
    heading_font = bslib::font_collection(
      "-apple-system",
      "BlinkMacSystemFont",
      "Segoe UI",
      "sans-serif"
    )
  )
}

mi_app_brand <- function() {
  shiny::tags$span(
    class = "mi-brand",
    shiny::tags$span(class = "mi-brand-mark", "M"),
    shiny::tags$span(
      class = "mi-brand-copy",
      shiny::tags$strong("Materials Market Radar"),
      shiny::tags$small("Graft intelligence room")
    )
  )
}

mi_app_status_badge <- function(status, label = NULL) {
  label <- mi_or(
    label,
    switch(
      status,
      ready = "Ready",
      awaiting_approval = "Review needed",
      succeeded = "Accepted",
      failed = "Rejected",
      status
    )
  )
  shiny::tags$span(
    class = paste("mi-status", paste0("is-", status)),
    shiny::tags$span(class = "mi-status-dot", `aria-hidden` = "true"),
    label
  )
}

mi_app_escape_markdown <- function(text) {
  text <- gsub("&", "&amp;", text, fixed = TRUE)
  text <- gsub("<", "&lt;", text, fixed = TRUE)
  gsub(">", "&gt;", text, fixed = TRUE)
}

mi_app_scope_markdown_headings <- function(text, offset = 2L) {
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  lines <- vapply(
    lines,
    function(line) {
      match <- regexec("^(#{1,4})([[:space:]]+.*)$", line)
      pieces <- regmatches(line, match)[[1L]]
      if (length(pieces) == 0L) {
        return(line)
      }
      level <- min(nchar(pieces[[2L]]) + offset, 6L)
      paste0(strrep("#", level), pieces[[3L]])
    },
    character(1)
  )
  paste(lines, collapse = "\n")
}

mi_app_ui <- function() {
  bslib::page_navbar(
    title = mi_app_brand(),
    id = "active_view",
    fillable = FALSE,
    theme = mi_app_theme(),
    window_title = "Materials Market Radar",
    header = shiny::tagList(
      shiny::tags$head(
        shiny::tags$meta(
          name = "description",
          content = paste(
            "A governed market and competitive intelligence example built",
            "with Graft, Tempest, and dsprrr."
          )
        ),
        shiny::tags$link(
          rel = "stylesheet",
          href = "market-intelligence.css"
        )
      ),
      shiny::tags$div(
        class = "mi-global-status",
        shiny::uiOutput("global_status")
      )
    ),
    bslib::nav_panel(
      "Briefing",
      value = "briefing",
      icon = bsicons::bs_icon("sunrise"),
      shiny::tags$main(
        class = "mi-page",
        `aria-labelledby` = "mi-page-title",
        shiny::uiOutput("briefing_view")
      )
    ),
    bslib::nav_panel(
      "Portfolio map",
      value = "portfolio",
      icon = bsicons::bs_icon("diagram-3"),
      shiny::tags$main(
        class = "mi-page",
        `aria-labelledby` = "mi-portfolio-title",
        shiny::uiOutput("portfolio_view")
      )
    ),
    bslib::nav_panel(
      "Review",
      value = "review",
      icon = bsicons::bs_icon("inbox"),
      shiny::tags$main(
        class = "mi-page",
        `aria-labelledby` = "mi-review-title",
        shiny::uiOutput("review_view")
      )
    ),
    bslib::nav_panel(
      "Knowledge",
      value = "knowledge",
      icon = bsicons::bs_icon("layers"),
      shiny::tags$main(
        class = "mi-page",
        `aria-labelledby` = "mi-knowledge-title",
        shiny::uiOutput("knowledge_view")
      )
    ),
    bslib::nav_panel(
      "Audit",
      value = "audit",
      icon = bsicons::bs_icon("activity"),
      shiny::tags$main(
        class = "mi-page",
        `aria-labelledby` = "mi-audit-title",
        shiny::uiOutput("audit_view")
      )
    ),
    bslib::nav_spacer(),
    bslib::nav_item(
      shiny::tags$span(
        class = "mi-local-badge",
        bsicons::bs_icon("shield-check", `aria-hidden` = "true"),
        "Local demo"
      )
    ),
    bslib::nav_item(
      bslib::input_dark_mode(
        id = "color_mode",
        title = "Switch color mode"
      )
    ),
    footer = shiny::tagList(
      shiny::tags$script(shiny::HTML(
        "
        Shiny.addCustomMessageHandler('mi-focus', function(id) {
          function focusTarget() {
            var target = document.getElementById(id);
            if (target) {
              target.setAttribute('tabindex', '-1');
              target.focus();
            }
          }
          window.setTimeout(focusTarget, 80);
          window.setTimeout(focusTarget, 240);
        });
        function collapseMobileNavigation() {
          window.setTimeout(function() {
            var collapse = document.querySelector('.navbar-collapse.show');
            var expanded = document.querySelector(
              '.navbar-toggler[aria-expanded=\"true\"]'
            );
            if (collapse && window.bootstrap) {
              window.bootstrap.Collapse.getOrCreateInstance(collapse).hide();
            } else if (expanded) {
              expanded.click();
            }
          }, 420);
        }
        function observeMarketNavigation() {
          var marketNavigation = document.getElementById('active_view');
          if (!marketNavigation) {
            window.setTimeout(observeMarketNavigation, 50);
            return;
          }
          if (marketNavigation.dataset.marketNavigationObserved) {
            return;
          }
          marketNavigation.dataset.marketNavigationObserved = 'true';
          new MutationObserver(function(mutations) {
            var selected = mutations.some(function(mutation) {
              return (
                mutation.target.classList.contains('nav-link') &&
                (
                  mutation.target.classList.contains('active') ||
                  mutation.target.getAttribute('aria-selected') === 'true'
                )
              );
            });
            if (selected) {
              collapseMobileNavigation();
            }
          }).observe(marketNavigation, {
            attributes: true,
            attributeFilter: ['aria-selected', 'class'],
            subtree: true
          });
        }
        window.setTimeout(observeMarketNavigation, 0);
        "
      ))
    )
  )
}

mi_app_metric <- function(label, value, detail, icon) {
  bslib::value_box(
    title = label,
    value = value,
    showcase = bsicons::bs_icon(icon, `aria-hidden` = "true"),
    showcase_layout = "left center",
    theme = "light",
    class = "mi-metric",
    shiny::tags$p(class = "mi-metric-detail", detail)
  )
}

mi_app_scan_controls <- function(progress, tool_count, can_run = TRUE) {
  next_bundle <- progress$next_bundle
  available <- !is.null(next_bundle)
  enabled <- available && isTRUE(can_run)
  shiny::tags$section(
    class = "mi-scan-controls",
    `aria-label` = "Scan controls",
    shiny::tags$div(
      class = "mi-scan-copy",
      shiny::tags$span(class = "mi-eyebrow", "Scheduled monitor"),
      shiny::tags$strong(
        if (!can_run) {
          "Resolve the assessment in Review"
        } else if (available) {
          next_bundle$title
        } else {
          "All demo scans are resolved"
        }
      ),
      shiny::tags$small(
        if (!can_run) {
          "A second scan cannot start while interpretation is pending."
        } else if (available) {
          paste("Signal date", next_bundle$scan_date)
        } else {
          "Restart the demo from Audit to run the sequence again."
        }
      )
    ),
    shiny::tags$div(
      class = "mi-scan-actions",
      bslib::input_switch(
        "use_model",
        "Use configured model",
        value = FALSE
      ),
      shiny::tags$span(
        class = "mi-tool-count",
        paste(tool_count, if (tool_count == 1L) "tool" else "tools")
      ),
      bslib::input_task_button(
        "run_scan",
        if (!can_run) {
          "Review pending"
        } else if (available) {
          "Run next scan"
        } else {
          "Sequence complete"
        },
        icon = bsicons::bs_icon("radar", `aria-hidden` = "true"),
        disabled = if (enabled) NULL else NA
      )
    )
  )
}

mi_app_empty_state <- function(icon, title, detail, id = NULL) {
  shiny::tags$section(
    id = id,
    class = "mi-empty",
    bsicons::bs_icon(icon, size = "2rem", `aria-hidden` = "true"),
    shiny::tags$h3(title),
    shiny::tags$p(detail)
  )
}

mi_app_source_list <- function(sources) {
  shiny::tags$ul(
    class = "mi-source-list",
    lapply(
      sources,
      function(source) {
        shiny::tags$li(
          shiny::tags$a(
            source$title,
            href = source$uri,
            target = "_blank",
            rel = "noreferrer"
          ),
          shiny::tags$span(
            paste(source$source_type, source$published_at, sep = " · ")
          )
        )
      }
    )
  )
}

mi_app_briefing_card <- function(snapshot) {
  if (is.null(snapshot$briefing)) {
    return(mi_app_empty_state(
      "newspaper",
      "No briefing yet",
      paste(
        "Run the next scheduled scan to reconcile public signals with",
        "accepted Graft knowledge."
      ),
      id = "mi-briefing-state"
    ))
  }
  content <- snapshot$change_set
  bslib::card(
    class = "mi-brief-card",
    full_screen = TRUE,
    bslib::card_header(
      shiny::tags$div(
        shiny::tags$span(class = "mi-eyebrow", "Executive briefing"),
        shiny::tags$h2(id = "mi-briefing-state", content$headline)
      ),
      mi_app_status_badge(snapshot$status)
    ),
    bslib::card_body(
      class = "mi-brief-body",
      shiny::tags$p(class = "mi-lede", content$summary),
      shiny::tags$div(
        class = "mi-insight-grid",
        shiny::tags$section(
          shiny::tags$h3("Why it matters"),
          shiny::tags$p(content$implication)
        ),
        shiny::tags$section(
          shiny::tags$h3("Continuity"),
          shiny::tags$p(content$continuity)
        )
      ),
      shiny::tags$details(
        class = "mi-full-brief",
        shiny::tags$summary("Read the complete source-linked briefing"),
        shiny::markdown(mi_app_escape_markdown(
          mi_app_scope_markdown_headings(snapshot$briefing$markdown)
        ))
      )
    )
  )
}

mi_app_evidence_card <- function(snapshot) {
  if (is.null(snapshot$change_set)) {
    return(bslib::card(
      class = "mi-evidence-card",
      bslib::card_header("Evidence packet"),
      mi_app_empty_state(
        "file-earmark-text",
        "Awaiting the first scan",
        "Source documents and extracted observations will appear here."
      )
    ))
  }
  content <- snapshot$change_set
  bslib::card(
    class = "mi-evidence-card",
    full_screen = TRUE,
    bslib::card_header(
      "Evidence packet",
      shiny::tags$span(
        class = "mi-evidence-count",
        paste(length(content$observations), "observations")
      )
    ),
    bslib::card_body(
      shiny::tags$ol(
        class = "mi-observation-list",
        lapply(
          content$observations,
          \(observation) {
            shiny::tags$li(
              shiny::tags$span(
                class = paste0(
                  "mi-direction is-",
                  observation$direction
                ),
                observation$direction
              ),
              shiny::tags$p(observation$statement)
            )
          }
        )
      ),
      shiny::tags$h3("Sources"),
      mi_app_source_list(content$sources)
    )
  )
}

mi_app_briefing_view <- function(
  worker,
  snapshot,
  progress,
  tool_count
) {
  business_count <- nrow(mi_worker_records(worker, "Business"))
  assessment_count <- nrow(mi_worker_records(worker, "Assessment"))
  action_count <- nrow(mi_worker_records(worker, "IntelligenceAction"))
  pending_count <- length(snapshot$pending)
  shiny::tagList(
    shiny::tags$header(
      class = "mi-hero",
      shiny::tags$div(
        shiny::tags$span(class = "mi-eyebrow", "Morning intelligence"),
        shiny::tags$h1(
          id = "mi-page-title",
          "See the market as a connected system."
        ),
        shiny::tags$p(
          paste(
            "Signals become useful only when they connect to a business,",
            "competitor, downstream market, accountable action, and outcome."
          )
        )
      ),
      shiny::tags$div(
        class = "mi-hero-date",
        shiny::tags$span("Demo horizon"),
        shiny::tags$strong("July 2026")
      )
    ),
    mi_app_scan_controls(
      progress,
      tool_count,
      can_run = length(snapshot$pending) == 0L
    ),
    bslib::layout_column_wrap(
      width = "220px",
      fill = FALSE,
      mi_app_metric(
        "Portfolio coverage",
        business_count,
        "Global businesses in the graph",
        "boxes"
      ),
      mi_app_metric(
        "Accepted theses",
        assessment_count,
        "Reviewed assessments in Graft",
        "check2-circle"
      ),
      mi_app_metric(
        "Open actions",
        action_count,
        "Owner-assigned follow-ups",
        "arrow-up-right-circle"
      ),
      mi_app_metric(
        "Review inbox",
        pending_count,
        if (pending_count == 1L) {
          "Assessment needs a decision"
        } else {
          "Nothing waiting for approval"
        },
        "inbox"
      )
    ),
    bslib::layout_columns(
      col_widths = c(8, 4),
      mi_app_briefing_card(snapshot),
      mi_app_evidence_card(snapshot)
    )
  )
}

mi_app_portfolio_view <- function(baseline) {
  watchlist <- baseline$enterprise_watchlist
  businesses <- baseline$business_watchlist
  shiny::tagList(
    shiny::tags$header(
      class = "mi-section-header",
      shiny::tags$span(class = "mi-eyebrow", "Business × market graph"),
      shiny::tags$h2(
        id = "mi-portfolio-title",
        "One portfolio, overlapping competitive systems"
      ),
      shiny::tags$p(
        paste(
          "Enterprise competitors deserve cross-business monitoring;",
          "specialists remain attached to the businesses where they matter."
        )
      )
    ),
    bslib::layout_columns(
      col_widths = c(5, 7),
      bslib::card(
        class = "mi-watchlist-card",
        bslib::card_header("Enterprise watchlist"),
        bslib::card_body(
          shiny::tags$ol(
            class = "mi-watchlist",
            lapply(
              watchlist,
              \(item) {
                shiny::tags$li(
                  shiny::tags$div(
                    shiny::tags$strong(item$competitor),
                    shiny::tags$span(item$tier)
                  ),
                  shiny::tags$span(
                    class = "mi-overlap",
                    paste(
                      item$business_count,
                      if (item$business_count == 1L) {
                        "business"
                      } else {
                        "businesses"
                      }
                    )
                  )
                )
              }
            )
          )
        )
      ),
      bslib::card(
        class = "mi-business-card",
        full_screen = TRUE,
        bslib::card_header("Direct competitors disclosed by business"),
        bslib::card_body(
          shiny::tags$div(
            class = "mi-business-list",
            lapply(
              businesses,
              \(item) {
                shiny::tags$section(
                  shiny::tags$h3(item$business),
                  shiny::tags$p(item$competitors)
                )
              }
            )
          )
        )
      )
    ),
    bslib::card(
      class = "mi-market-strip",
      bslib::card_header("Downstream lenses"),
      bslib::card_body(
        shiny::tags$div(
          class = "mi-market-grid",
          lapply(
            baseline$downstream_markets,
            \(market) {
              shiny::tags$article(
                bsicons::bs_icon("crosshair", `aria-hidden` = "true"),
                shiny::tags$h3(market$name),
                shiny::tags$p(market$description)
              )
            }
          )
        )
      )
    )
  )
}

mi_app_review_view <- function(snapshot) {
  shiny::tagList(
    shiny::tags$header(
      class = "mi-section-header",
      shiny::tags$span(class = "mi-eyebrow", "Approval boundary"),
      shiny::tags$h2(id = "mi-review-title", "Review before interpretation"),
      shiny::tags$p(
        paste(
          "The public evidence is inspectable now. The assessment, action,",
          "and durable organizational memory remain pending."
        )
      )
    ),
    if (length(snapshot$pending) == 0L) {
      mi_app_empty_state(
        "inbox",
        "No assessment is waiting",
        "Run a scan from Briefing to create a reviewable change set.",
        id = "mi-review-state"
      )
    } else {
      content <- snapshot$change_set
      bslib::card(
        class = "mi-review-card",
        bslib::card_header(
          shiny::tags$div(
            shiny::tags$span(class = "mi-eyebrow", "Proposed assessment"),
            shiny::tags$h3(id = "mi-review-state", content$headline)
          ),
          mi_app_status_badge("awaiting_approval")
        ),
        bslib::card_body(
          shiny::tags$div(
            class = "mi-review-grid",
            shiny::tags$section(
              shiny::tags$h4("Assessment"),
              shiny::tags$p(content$summary),
              shiny::tags$h4("Implication"),
              shiny::tags$p(content$implication)
            ),
            shiny::tags$aside(
              shiny::tags$dl(
                shiny::tags$div(
                  shiny::tags$dt("Materiality"),
                  shiny::tags$dd(content$materiality)
                ),
                shiny::tags$div(
                  shiny::tags$dt("Confidence"),
                  shiny::tags$dd(
                    paste0(round(content$confidence * 100), "%")
                  )
                ),
                shiny::tags$div(
                  shiny::tags$dt("Owner"),
                  shiny::tags$dd(content$action$owner)
                ),
                shiny::tags$div(
                  shiny::tags$dt("Due"),
                  shiny::tags$dd(content$action$due_date)
                )
              )
            )
          ),
          shiny::tags$section(
            class = "mi-proposed-action",
            bsicons::bs_icon("arrow-right-circle", `aria-hidden` = "true"),
            shiny::tags$div(
              shiny::tags$span("Proposed action"),
              shiny::tags$strong(content$action$title)
            )
          ),
          shiny::tags$label(
            `for` = "review_note",
            class = "form-label",
            "Review note"
          ),
          shiny::textAreaInput(
            "review_note",
            label = NULL,
            value = "",
            placeholder = "Optional rationale for the audit record",
            width = "100%",
            rows = 3
          )
        ),
        bslib::card_footer(
          class = "mi-review-actions",
          shiny::actionButton(
            "reject_assessment",
            "Reject",
            icon = bsicons::bs_icon("x-lg", `aria-hidden` = "true"),
            class = "btn-outline-danger"
          ),
          shiny::actionButton(
            "approve_assessment",
            "Approve into Graft",
            icon = bsicons::bs_icon("check2", `aria-hidden` = "true"),
            class = "btn-success"
          )
        )
      )
    }
  )
}

mi_app_knowledge_view <- function(worker) {
  assessments <- mi_worker_records(worker, "Assessment") |>
    dplyr::arrange(dplyr::desc(.data$accepted_at))
  actions <- mi_worker_records(worker, "IntelligenceAction")
  shiny::tagList(
    shiny::tags$header(
      class = "mi-section-header",
      shiny::tags$span(class = "mi-eyebrow", "Accepted organizational memory"),
      shiny::tags$h2(id = "mi-knowledge-title", "Knowledge ledger"),
      shiny::tags$p(
        paste(
          "Only reviewed assessments appear here. Later scans receive this",
          "accepted history as explicit planner context."
        )
      )
    ),
    if (nrow(assessments) == 0L) {
      mi_app_empty_state(
        "layers",
        "No accepted assessments",
        "Approve a pending assessment to establish durable continuity.",
        id = "mi-knowledge-state"
      )
    } else {
      shiny::tags$div(
        id = "mi-knowledge-state",
        class = "mi-ledger",
        lapply(
          seq_len(nrow(assessments)),
          function(index) {
            assessment <- assessments[index, , drop = FALSE]
            action <- actions[
              actions$assessment == assessment$id,
              ,
              drop = FALSE
            ]
            shiny::tags$article(
              class = "mi-ledger-entry",
              shiny::tags$div(
                class = "mi-ledger-rail",
                shiny::tags$span()
              ),
              shiny::tags$div(
                class = "mi-ledger-content",
                shiny::tags$div(
                  class = "mi-ledger-meta",
                  mi_app_status_badge("succeeded", "Accepted"),
                  shiny::tags$time(
                    datetime = assessment$accepted_at,
                    assessment$accepted_at
                  )
                ),
                shiny::tags$h3(assessment$headline),
                shiny::tags$p(assessment$implication),
                if (nrow(action) > 0L) {
                  shiny::tags$div(
                    class = "mi-ledger-action",
                    shiny::tags$span("Open action"),
                    shiny::tags$strong(action$action_title),
                    shiny::tags$small(
                      paste(action$owner, "· due", action$due_date)
                    )
                  )
                }
              )
            )
          }
        )
      )
    }
  )
}

mi_app_audit_table <- function(events) {
  if (nrow(events) == 0L) {
    return(mi_app_empty_state(
      "activity",
      "No workflow events",
      "Run a scan to inspect the Tempest event trail."
    ))
  }
  shiny::tags$div(
    class = "mi-table-wrap",
    shiny::tags$table(
      class = "table mi-audit-table",
      shiny::tags$caption(
        class = "visually-hidden",
        "Tempest workflow events for the current scan"
      ),
      shiny::tags$thead(
        shiny::tags$tr(
          shiny::tags$th(scope = "col", "Sequence"),
          shiny::tags$th(scope = "col", "Event"),
          shiny::tags$th(scope = "col", "Step"),
          shiny::tags$th(scope = "col", "Status")
        )
      ),
      shiny::tags$tbody(
        lapply(
          seq_len(nrow(events)),
          \(index) {
            shiny::tags$tr(
              shiny::tags$td(events$sequence[[index]]),
              shiny::tags$td(events$event[[index]]),
              shiny::tags$td(events$step[[index]]),
              shiny::tags$td(events$status[[index]])
            )
          }
        )
      )
    )
  )
}

mi_app_audit_view <- function(worker, snapshot) {
  runs <- mi_worker_records(worker, "MonitorRun") |>
    dplyr::arrange(dplyr::desc(.data$scan_date))
  shiny::tagList(
    shiny::tags$header(
      class = "mi-section-header",
      shiny::tags$span(class = "mi-eyebrow", "Provenance and control"),
      shiny::tags$h2(id = "mi-audit-title", "Workflow audit"),
      shiny::tags$p(
        paste(
          "Tempest owns run and approval state. Graft records the approved",
          "run, source lineage, model path, reviewer, and durable result."
        )
      )
    ),
    bslib::layout_columns(
      col_widths = c(7, 5),
      bslib::card(
        bslib::card_header("Current Tempest events"),
        bslib::card_body(mi_app_audit_table(mi_worker_events(worker)))
      ),
      bslib::card(
        bslib::card_header("Accepted Graft runs"),
        bslib::card_body(
          if (nrow(runs) == 0L) {
            mi_app_empty_state(
              "database",
              "No committed runs",
              "Approvals will create an auditable Graft run record."
            )
          } else {
            shiny::tags$ul(
              class = "mi-run-list",
              lapply(
                seq_len(nrow(runs)),
                \(index) {
                  shiny::tags$li(
                    shiny::tags$strong(runs$title[[index]]),
                    shiny::tags$span(
                      paste(
                        runs$scan_date[[index]],
                        runs$planning_engine[[index]],
                        if (isTRUE(runs$memory_used[[index]])) {
                          "memory used"
                        } else {
                          "first read"
                        },
                        sep = " · "
                      )
                    )
                  )
                }
              )
            )
          }
        )
      )
    ),
    shiny::tags$section(
      class = "mi-reset",
      shiny::tags$div(
        shiny::tags$h3("Reset this local session"),
        shiny::tags$p(
          paste(
            "Deletes this session's temporary DuckDB store and restarts",
            "the two-scan provider-free walkthrough."
          )
        )
      ),
      shiny::actionButton(
        "restart_demo",
        "Restart demo",
        icon = bsicons::bs_icon(
          "arrow-counterclockwise",
          `aria-hidden` = "true"
        ),
        class = "btn-outline-secondary"
      )
    )
  )
}
