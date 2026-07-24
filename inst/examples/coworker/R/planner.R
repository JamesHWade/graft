cw_or <- function(x, y) {
  if (is.null(x) || length(x) == 0L) y else x
}

cw_text <- function(value, field) {
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

cw_read_json <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

cw_source_ids <- function(bundle) {
  vapply(bundle$sources, `[[`, character(1), "id")
}

cw_evidence_text <- function(bundle) {
  paste(
    vapply(
      bundle$sources,
      function(source) {
        paste0(
          "[",
          source$source_kind,
          "] ",
          source$title,
          "\n",
          source$content,
          "\nObserved: ",
          source$observed_at,
          "\nURI: ",
          source$uri
        )
      },
      character(1)
    ),
    collapse = "\n\n"
  )
}

cw_planner_signature <- function() {
  paste(
    "request, evidence, memory ->",
    "title, plan_markdown, summary, deliverable_markdown, action_summary"
  )
}

cw_reference_planner <- function(bundle) {
  force(bundle)
  dsprrr::module_fn(
    cw_planner_signature(),
    function(request, evidence, memory, ...) {
      request <- cw_text(request, "request")
      sources <- bundle$sources
      source_lines <- vapply(
        sources,
        function(source) {
          paste0(
            "- **",
            source$title,
            "** (",
            source$source_kind,
            "): ",
            source$content
          )
        },
        character(1)
      )
      title <- paste(bundle$workspace$name, "release-readiness brief")
      summary <- paste(
        "The release checks are green, but the API timeout and onboarding",
        "review remain launch blockers. The July 29 beta should stay",
        "provisional until both owners report a cleared completion signal."
      )
      previous_memory <- if (
        identical(memory, "No accepted workspace memory yet.")
      ) {
        "No earlier accepted memory was available for this first run."
      } else {
        paste(
          "Earlier accepted workspace memory was supplied to the planner",
          "and should be checked for superseded assumptions."
        )
      }
      markdown <- paste(
        paste0("# ", title),
        paste0("**Requested outcome:** ", request),
        "## Executive summary",
        summary,
        "## What I checked",
        paste(source_lines, collapse = "\n"),
        "## Recommended next action",
        bundle$recommended_action,
        "## Continuity",
        previous_memory,
        sep = "\n\n"
      )
      list(
        title = title,
        plan_markdown = paste(
          "1. Read the approved workspace source snapshots.",
          "2. Reconcile blockers, owners, and timing across systems.",
          "3. Draft the requested briefing and team update.",
          "4. Ask before publishing the deliverable to the local workspace.",
          sep = "\n"
        ),
        summary = summary,
        deliverable_markdown = markdown,
        action_summary = paste0(
          "Publish `",
          title,
          "` to the local deliverables folder."
        )
      )
    },
    name = "graft-coworker-reference-planner",
    config = list(engine = "dsprrr-reference")
  )
}

cw_model_planner <- function(chat) {
  if (!inherits(chat, "Chat")) {
    stop("`chat` must be an ellmer Chat.")
  }
  dsprrr::module(
    dsprrr::signature(
      cw_planner_signature(),
      instructions = paste(
        "Act as an outcome-oriented local coworker.",
        "Use only the supplied evidence and accepted memory.",
        "Return a concrete Markdown deliverable, not a to-do list.",
        "Call out conflicts and uncertainty.",
        "The action summary must describe publishing one local file;",
        "do not claim that a message was sent or an external system changed."
      )
    ),
    chat = chat,
    temperature = 0.2,
    config = list(engine = "dsprrr-model")
  )
}

cw_run_planner <- function(planner, request, bundle, memory) {
  if (!inherits(planner, "Module")) {
    stop("`planner` must be a dsprrr module.")
  }
  result <- dsprrr::run(
    planner,
    request = cw_text(request, "request"),
    evidence = cw_evidence_text(bundle),
    memory = cw_text(memory, "memory")
  )
  required <- c(
    "title",
    "plan_markdown",
    "summary",
    "deliverable_markdown",
    "action_summary"
  )
  if (
    !is.list(result) ||
      !identical(sort(names(result)), sort(required))
  ) {
    stop("The planner did not return the coworker planning contract.")
  }
  for (field in required) {
    result[[field]] <- cw_text(result[[field]], paste0("planner$", field))
  }
  result
}

cw_chat_system_prompt <- function(role = c("assistant", "planner")) {
  role <- match.arg(role)
  if (identical(role, "planner")) {
    return(paste(
      "You prepare grounded work products from supplied evidence and memory.",
      "Do not invent connector results or claim an external action occurred."
    ))
  }
  paste(
    "You are Graft Coworker, an outcome-oriented local work assistant.",
    "For requests that should produce a deliverable, call prepare_outcome.",
    "Use recall_memory when prior accepted work could change the answer.",
    "A prepared deliverable may remain awaiting approval.",
    "Never claim a pending file was published or an external action occurred.",
    "Finish by telling the user what is ready and what still needs approval."
  )
}

cw_chat_client <- function(role = c("assistant", "planner")) {
  role <- match.arg(role)
  configured <- getOption("tempest.chat")
  prompt <- cw_chat_system_prompt(role)
  if (inherits(configured, "Chat")) {
    client <- configured$clone(deep = TRUE)
    client$set_system_prompt(prompt)
    return(client)
  }
  model <- cw_or(
    configured,
    Sys.getenv("GRAFT_COWORKER_MODEL", unset = "openai/gpt-5-mini")
  )
  if (
    !is.character(model) ||
      length(model) != 1L ||
      is.na(model) ||
      !nzchar(model)
  ) {
    stop(
      paste(
        "`options(tempest.chat = )` must contain an ellmer Chat or",
        "provider/model string."
      )
    )
  }
  ellmer::chat(model, system_prompt = prompt)
}
