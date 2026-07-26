mi_or <- function(x, y) {
  if (is.null(x) || length(x) == 0L) y else x
}

mi_text <- function(value, field) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(trimws(value))
  ) {
    stop(paste0("`", field, "` must be one nonempty string."))
  }
  trimws(value)
}

mi_read_json <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

mi_character <- function(value) {
  if (is.null(value)) {
    return(character())
  }
  unname(unlist(value, use.names = FALSE))
}

mi_evidence_text <- function(bundle) {
  source_titles <- stats::setNames(
    vapply(bundle$sources, `[[`, character(1), "title"),
    vapply(bundle$sources, `[[`, character(1), "id")
  )
  paste(
    vapply(
      bundle$signals,
      function(signal) {
        paste(
          paste0("Source: ", source_titles[[signal$source]]),
          paste0("Observation: ", signal$statement),
          paste0(
            "Affected businesses: ",
            paste(mi_character(signal$businesses), collapse = ", ")
          ),
          paste0(
            "Downstream markets: ",
            paste(mi_character(signal$downstream_markets), collapse = ", ")
          ),
          paste0("Direction: ", signal$direction),
          sep = "\n"
        )
      },
      character(1)
    ),
    collapse = "\n\n"
  )
}

mi_planner_signature <- function() {
  paste(
    "request, evidence, memory ->",
    paste(
      "headline, summary, implication, materiality, confidence,",
      "action_title, action_owner, due_date, continuity,",
      "briefing_markdown, memory_used"
    )
  )
}

mi_memory_available <- function(memory) {
  !identical(
    mi_text(memory, "memory"),
    "No accepted market assessments yet."
  )
}

mi_reference_planner <- function(bundle) {
  force(bundle)
  dsprrr::module_fn(
    mi_planner_signature(),
    function(request, evidence, memory, ...) {
      request <- mi_text(request, "request")
      proposal <- bundle$proposal
      memory_used <- mi_memory_available(memory)
      continuity <- if (memory_used) {
        paste(
          "This scan was reconciled against accepted Graft assessments.",
          "It reinforces or qualifies an existing downstream-market thesis",
          "instead of presenting the competitor move as an isolated alert."
        )
      } else {
        paste(
          "No accepted market assessment was available.",
          "Approval would establish the first durable thesis for later scans."
        )
      }
      source_lines <- vapply(
        bundle$sources,
        \(source) paste0("- [", source$title, "](", source$uri, ")"),
        character(1)
      )
      observation_lines <- vapply(
        bundle$signals,
        \(signal) paste0("- ", signal$statement),
        character(1)
      )
      briefing <- paste(
        paste0("# ", proposal$headline),
        paste0("**Requested decision:** ", request),
        "## Executive readout",
        proposal$summary,
        "## What changed",
        paste(observation_lines, collapse = "\n"),
        "## Why it matters",
        proposal$implication,
        "## Continuity",
        continuity,
        "## Proposed action",
        paste0(
          proposal$action_title,
          " — **",
          proposal$owner,
          "** by ",
          proposal$due_date,
          "."
        ),
        "## Sources",
        paste(source_lines, collapse = "\n"),
        "## Governance",
        paste(
          "The evidence and interpretation remain outside durable memory",
          "until this assessment package is approved."
        ),
        sep = "\n\n"
      )
      list(
        headline = proposal$headline,
        summary = proposal$summary,
        implication = proposal$implication,
        materiality = proposal$materiality,
        confidence = as.character(proposal$confidence),
        action_title = proposal$action_title,
        action_owner = proposal$owner,
        due_date = proposal$due_date,
        continuity = continuity,
        briefing_markdown = briefing,
        memory_used = if (memory_used) "yes" else "no"
      )
    },
    name = "graft-market-intelligence-reference-planner",
    config = list(engine = "dsprrr-reference")
  )
}

mi_model_planner <- function(chat) {
  if (!inherits(chat, "Chat")) {
    stop("`chat` must be an ellmer Chat.")
  }
  dsprrr::module(
    dsprrr::signature(
      mi_planner_signature(),
      instructions = paste(
        "Act as a materials market and competitive-intelligence analyst.",
        "Use only the supplied evidence and accepted memory.",
        "Separate source-faithful observations from interpretation.",
        "Do not invent market share, customer activity, or connector results.",
        "Return one bounded owner-assigned action.",
        "Use materiality values monitor, material, or urgent.",
        "Return confidence as a number between zero and one.",
        "Return memory_used as yes only when accepted memory changed the readout.",
        "The Markdown briefing must include sources and the approval boundary."
      )
    ),
    chat = chat,
    temperature = 0.2,
    config = list(engine = "dsprrr-model")
  )
}

mi_run_planner <- function(planner, request, bundle, memory) {
  if (!inherits(planner, "Module")) {
    stop("`planner` must be a dsprrr module.")
  }
  result <- dsprrr::run(
    planner,
    request = mi_text(request, "request"),
    evidence = mi_evidence_text(bundle),
    memory = mi_text(memory, "memory")
  )
  required <- c(
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
    "memory_used"
  )
  if (
    !is.list(result) ||
      !identical(sort(names(result)), sort(required))
  ) {
    stop("The planner did not return the market-intelligence contract.")
  }
  text_fields <- setdiff(required, "confidence")
  for (field in text_fields) {
    result[[field]] <- mi_text(
      result[[field]],
      paste0("planner$", field)
    )
  }
  result$materiality <- match.arg(
    tolower(result$materiality),
    c("monitor", "material", "urgent")
  )
  result$confidence <- as.numeric(result$confidence)
  if (
    length(result$confidence) != 1L ||
      is.na(result$confidence) ||
      result$confidence < 0 ||
      result$confidence > 1
  ) {
    stop("`planner$confidence` must be between zero and one.")
  }
  result$memory_used <- identical(tolower(result$memory_used), "yes")
  result$businesses <- mi_character(bundle$proposal$businesses)
  result$competitors <- mi_character(bundle$proposal$competitors)
  result$downstream_markets <- mi_character(
    bundle$proposal$downstream_markets
  )
  result$sources <- bundle$sources
  result$observations <- bundle$signals
  result
}

mi_chat_system_prompt <- function() {
  paste(
    "You prepare governed materials-market intelligence from supplied",
    "evidence and accepted organizational memory.",
    "Keep observations separate from assessments.",
    "Do not claim that a pending assessment entered durable memory."
  )
}

mi_tempest_config <- function(config = NULL) {
  configured <- mi_or(
    config,
    getOption("graft.market.tempest_config")
  )
  configured <- mi_or(configured, tempest::tempest_config())
  if (!inherits(configured, "tempest::TempestConfig")) {
    stop(
      paste(
        "`graft.market.tempest_config` must be created by",
        "`tempest::tempest_config()`."
      )
    )
  }
  configured
}

mi_app_config <- function(
  tempest_config = NULL,
  tools = getOption("graft.market.tools"),
  btw = getOption("graft.market.btw", FALSE)
) {
  structure(
    list(
      tempest = mi_tempest_config(tempest_config),
      tools = tools,
      btw = btw
    ),
    class = "graft_market_intelligence_config"
  )
}

mi_chat_model <- function(config) {
  config <- mi_tempest_config(config)
  mi_or(
    config@models[["writer"]],
    config@models[["coordinator"]]
  )
}

mi_chat_client <- function(
  config = mi_tempest_config(),
  tools = list()
) {
  config <- mi_tempest_config(config)
  model <- mi_chat_model(config)
  prompt <- mi_chat_system_prompt()
  client <- if (!is.null(config@chat_fn)) {
    config@chat_fn(
      role = "writer",
      model = model,
      system_prompt = prompt,
      echo = "none"
    )
  } else if (!is.null(config@chat)) {
    client_prompt <- config@chat$get_system_prompt()
    client <- config@chat$clone(deep = TRUE)
    combined_prompt <- c(
      prompt,
      if (!is.null(client_prompt)) c("---", client_prompt)
    ) |>
      paste(collapse = "\n\n")
    client$set_system_prompt(combined_prompt)
    client
  } else {
    ellmer::chat(
      name = model,
      system_prompt = prompt,
      params = config@params,
      echo = "none"
    )
  }
  if (!inherits(client, "Chat")) {
    stop(
      paste(
        "The configured Tempest chat factory must return an",
        "ellmer Chat object."
      )
    )
  }
  tools <- mi_normalize_tools(tools, "market-intelligence tool registry")
  if (length(tools) > 0L) {
    client$register_tools(tools)
  }
  client
}

mi_normalize_tools <- function(tools, source) {
  if (is.null(tools)) {
    return(list())
  }
  if (inherits(tools, "ellmer::ToolDef")) {
    tools <- list(tools)
  }
  if (!is.list(tools)) {
    stop(paste0("`", source, "` must return ellmer tools in a list."))
  }
  valid <- vapply(
    tools,
    inherits,
    logical(1),
    what = "ellmer::ToolDef"
  )
  if (!all(valid)) {
    stop(paste0("Every `", source, "` entry must be an ellmer tool."))
  }
  unname(tools)
}

mi_extension_tools <- function(provider, context) {
  if (is.null(provider)) {
    return(list())
  }
  tools <- if (is.function(provider)) provider(context) else provider
  mi_normalize_tools(tools, "graft.market.tools")
}

mi_btw_read_only <- function(tools) {
  tool_names <- vapply(tools, \(tool) tool@name, character(1))
  allowed <- grepl(
    paste0(
      "^btw_tool_(",
      "cran_|docs_|env_describe_|",
      "files_(code_search|list_files|read_text_file|list|read|search)$|",
      "git_(status|diff|log|branch_list)$|",
      "ide_read_current_editor$|search_|session_|sessioninfo_|",
      "skill$|web_read_url$",
      ")"
    ),
    tool_names
  )
  unname(tools[allowed])
}

mi_btw_tools <- function(profile = FALSE) {
  if (is.null(profile) || identical(profile, FALSE)) {
    return(list())
  }
  if (!requireNamespace("btw", quietly = TRUE)) {
    stop(
      paste(
        "Install `btw` to use `graft.market.btw`.",
        "For example: `install.packages(\"btw\")`."
      )
    )
  }
  if (identical(profile, TRUE)) {
    profile <- "read_only"
  }
  if (
    !is.character(profile) ||
      length(profile) == 0L ||
      anyNA(profile) ||
      !all(nzchar(profile))
  ) {
    stop(
      paste(
        "`graft.market.btw` must be `FALSE`, `TRUE`,",
        "`\"read_only\"`, `\"all\"`, or btw tool/group names."
      )
    )
  }
  if (identical(profile, "all")) {
    return(mi_normalize_tools(btw::btw_tools(), "btw::btw_tools()"))
  }
  if (identical(profile, "read_only")) {
    return(mi_btw_read_only(mi_normalize_tools(
      suppressWarnings(btw::btw_tools()),
      "btw::btw_tools()"
    )))
  }
  mi_normalize_tools(
    do.call(btw::btw_tools, as.list(profile)),
    "btw::btw_tools()"
  )
}

mi_toolset <- function(...) {
  tools <- unlist(list(...), recursive = FALSE)
  tools <- mi_normalize_tools(tools, "market-intelligence tool registry")
  names <- vapply(tools, \(tool) tool@name, character(1))
  duplicates <- unique(names[duplicated(names)])
  if (length(duplicates) > 0L) {
    stop(
      paste(
        "Market-intelligence tool names must be unique:",
        paste(duplicates, collapse = ", ")
      )
    )
  }
  tools
}

mi_configured_tools <- function(config, context = list()) {
  if (!inherits(config, "graft_market_intelligence_config")) {
    stop("`config` must be created by `mi_app_config()`.")
  }
  mi_toolset(
    mi_btw_tools(config$btw),
    mi_extension_tools(config$tools, context)
  )
}
