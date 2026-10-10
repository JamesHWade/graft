# Producer fixture helpers ---------------------------------------------------

handoff_fixture_png <- function() {
  jsonlite::base64_dec(
    paste0(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk",
      "+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )
  )
}

handoff_large_inline_bytes <- function() {
  as.raw(rep(0:255, length.out = 600L))
}

handoff_commons_measure <- function(
  mode = "complete",
  report = "The observed report is 6.",
  table = '{"rows":[{"term":"Headache","count":6}]}',
  figure = handoff_fixture_png()
) {
  if (!is.character(mode) || length(mode) != 1L || is.na(mode)) {
    stop("`mode` must be one string.")
  }
  ellmer::tool(
    function() {
      if (identical(mode, "native-error")) {
        return(ellmer::ContentToolResult(error = "fixture producer failed"))
      }
      if (identical(mode, "unsupported")) {
        return(ellmer::ContentToolResult(value = data.frame(x = 1L)))
      }
      ellmer::ContentToolResult(
        value = list(
          ellmer::ContentText(report),
          ellmer::ContentText(table),
          ellmer::ContentImageInline(
            "image/png",
            jsonlite::base64_enc(figure)
          )
        ),
        # This tag is explicitly authored by the fixture producer. It is not
        # a runtime-issued Commons or Graft classification.
        extra = list(
          commons_tag = "A",
          display = structure(
            list(html = "ignored display object"),
            class = "fixture_display"
          )
        )
      )
    },
    name = "completed_output",
    description = "Produce the fixture's completed report, table, and figure.",
    arguments = list(),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE,
      destructive_hint = FALSE
    )
  )
}

handoff_commons_value <- function(mode = "complete") {
  measure <- commons::measure(
    "completed_output",
    "Produce the fixture's completed report, table, and figure.",
    function() {
      if (identical(mode, "native-error")) {
        return(ellmer::ContentToolResult(error = "fixture producer failed"))
      }
      if (identical(mode, "unsupported")) {
        return(ellmer::ContentToolResult(value = data.frame(x = 1L)))
      }
      ellmer::ContentToolResult(
        value = list(
          ellmer::ContentText("The observed report is 6."),
          ellmer::ContentText('{"rows":[{"term":"Headache","count":6}]}'),
          ellmer::ContentImageInline(
            "image/png",
            jsonlite::base64_enc(handoff_fixture_png())
          )
        ),
        extra = list(
          commons_tag = "A",
          display = structure(
            list(html = "ignored display object"),
            class = "fixture_display"
          )
        )
      )
    },
    arguments = list()
  )
  semantic <- commons::semantic_layer(measure)
  trusted <- commons::trusted(
    data_sources = commons::data_source(observations = data.frame(x = 1L)),
    semantic_layer = semantic
  )
  trusted$measure("completed_output")
}

handoff_deputy_measure_tool <- function(mode = "complete", async = FALSE) {
  source_tool <- handoff_commons_measure(mode)
  if (!isTRUE(async)) {
    return(source_tool)
  }
  ellmer::tool(
    function() {
      promises::promise(function(resolve, reject) {
        later::later(
          function() {
            tryCatch(
              resolve(source_tool()),
              error = reject
            )
          },
          delay = 0.01
        )
      })
    },
    name = source_tool@name,
    description = source_tool@description,
    arguments = list(),
    annotations = source_tool@annotations
  )
}

handoff_graft_readonly_tool <- function() {
  path <- tempfile("graft-handoff-readonly-")
  dir.create(path)
  store <- graft::graft_store(path, create = TRUE)
  ref <- graft::graft_save(
    store,
    "Fixture-approved memory",
    id = "fixture-memory",
    media_type = "text/plain"
  )
  graft::graft_accept(
    store,
    x = ref,
    stream = "fixture-memory",
    expected = NULL,
    key = "fixture-review",
    actor = "fixture",
    reason = "Credential-free fixture",
    purpose = "handoff-test"
  )
  list(
    tool = graft::graft_tool(
      store,
      stream = "fixture-memory",
      purpose = "handoff-test",
      eligible = \() TRUE
    ),
    close = \() unlink(path, recursive = TRUE),
    path = path
  )
}

handoff_sse_reply <- function(
  text = NULL,
  tool = NULL,
  arguments = list(),
  id
) {
  delta <- list(role = "assistant", content = text)
  finish_reason <- "stop"
  if (!is.null(tool)) {
    delta$content <- NULL
    delta$tool_calls <- list(list(
      index = 0L,
      id = paste0("handoff-call-", id),
      type = "function",
      `function` = list(
        name = tool,
        arguments = as.character(jsonlite::toJSON(
          arguments,
          auto_unbox = TRUE,
          null = "null"
        ))
      )
    ))
    finish_reason <- "tool_calls"
  }
  chunks <- list(
    list(
      id = "graft-handoff-fixture",
      model = "graft-handoff-fixture",
      choices = list(list(index = 0L, delta = delta))
    ),
    list(
      id = "graft-handoff-fixture",
      model = "graft-handoff-fixture",
      choices = list(list(
        index = 0L,
        delta = list(),
        finish_reason = finish_reason
      )),
      usage = list(
        prompt_tokens = 10L,
        completion_tokens = 5L,
        total_tokens = 15L
      )
    )
  )
  paste0(
    paste(
      vapply(
        chunks,
        function(chunk) {
          paste0(
            "data: ",
            jsonlite::toJSON(chunk, auto_unbox = TRUE, null = "null"),
            "\n\n"
          )
        },
        character(1)
      ),
      collapse = ""
    ),
    "data: [DONE]\n\n"
  )
}

handoff_local_model_fixture <- function(
  mode = "complete",
  tool_name = "completed_output",
  delay = 0
) {
  directory <- tempfile("graft-handoff-model-")
  dir.create(directory)
  process <- callr::r_bg(
    function(directory, mode, tool_name, delay) {
      sse_reply <- function(
        text = NULL,
        tool = NULL,
        arguments = list(),
        id
      ) {
        delta <- list(role = "assistant", content = text)
        finish_reason <- "stop"
        if (!is.null(tool)) {
          delta$content <- NULL
          delta$tool_calls <- list(list(
            index = 0L,
            id = paste0("handoff-call-", id),
            type = "function",
            `function` = list(
              name = tool,
              arguments = as.character(jsonlite::toJSON(
                arguments,
                auto_unbox = TRUE,
                null = "null"
              ))
            )
          ))
          finish_reason <- "tool_calls"
        }
        chunks <- list(
          list(
            id = "graft-handoff-fixture",
            model = "graft-handoff-fixture",
            choices = list(list(index = 0L, delta = delta))
          ),
          list(
            id = "graft-handoff-fixture",
            model = "graft-handoff-fixture",
            choices = list(list(
              index = 0L,
              delta = list(),
              finish_reason = finish_reason
            )),
            usage = list(
              prompt_tokens = 10L,
              completion_tokens = 5L,
              total_tokens = 15L
            )
          )
        )
        paste0(
          paste(
            vapply(
              chunks,
              function(chunk) {
                paste0(
                  "data: ",
                  jsonlite::toJSON(chunk, auto_unbox = TRUE, null = "null"),
                  "\n\n"
                )
              },
              character(1)
            ),
            collapse = ""
          ),
          "data: [DONE]\n\n"
        )
      }
      count <- 0L
      port <- httpuv::randomPort()
      server <- httpuv::startServer(
        "127.0.0.1",
        port,
        list(call = function(req) {
          count <<- count + 1L
          saveRDS(count, file.path(directory, "count.rds"))
          if (delay > 0) {
            Sys.sleep(delay)
          }
          body <- jsonlite::fromJSON(
            rawToChar(req$rook.input$read()),
            simplifyVector = FALSE
          )
          messages <- if (is.null(body$messages)) list() else body$messages
          has_tool_result <- any(vapply(
            messages,
            \(message) identical(message$role, "tool"),
            logical(1)
          ))
          response <- if (identical(mode, "noevent")) {
            sse_reply(
              text = "No producer was called; this prose is deliberately wrong.",
              id = count
            )
          } else if (has_tool_result) {
            sse_reply(
              text = paste(
                "Model prose is deliberately wrong: the report says 999.",
                "The retained output must use the producer event instead."
              ),
              id = count
            )
          } else {
            sse_reply(
              tool = tool_name,
              arguments = list(),
              id = count
            )
          }
          list(
            status = 200L,
            headers = list("Content-Type" = "text/event-stream"),
            body = response
          )
        })
      )
      on.exit(server$stop(), add = TRUE)
      saveRDS(port, file.path(directory, "port.rds"))
      file.create(file.path(directory, "ready"))
      repeat {
        httpuv::service(50)
      }
    },
    args = list(
      directory = directory,
      mode = mode,
      tool_name = tool_name,
      delay = delay
    )
  )
  deadline <- Sys.time() + 10
  while (!file.exists(file.path(directory, "ready"))) {
    alive <- tryCatch(process$is_alive(), error = \(error) FALSE)
    if (!alive || Sys.time() > deadline) {
      tryCatch(process$kill(), error = \(error) NULL)
      unlink(directory, recursive = TRUE)
      stop("The local output-handoff HTTP fixture did not start.")
    }
    Sys.sleep(0.02)
  }
  list(
    chat = function() {
      ellmer::chat_openai_compatible(
        base_url = paste0(
          "http://127.0.0.1:",
          readRDS(file.path(directory, "port.rds")),
          "/v1"
        ),
        model = "graft-handoff-fixture",
        credentials = \() "local-fixture",
        echo = "none"
      )
    },
    requests = function() {
      path <- file.path(directory, "count.rds")
      if (file.exists(path)) readRDS(path) else 0L
    },
    path = directory,
    close = function() {
      tryCatch(process$kill(), error = \(error) NULL)
      unlink(directory, recursive = TRUE)
    }
  )
}

handoff_fixture_permissions <- function(deny = FALSE) {
  deputy::Permissions(
    mode = "standard",
    file_read = FALSE,
    file_write = FALSE,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE,
    can_use_tool = if (isTRUE(deny)) {
      function(tool_name, tool_input, context) {
        deputy::PermissionResultDeny(
          "The fixture denies the producer call.",
          interrupt = TRUE
        )
      }
    } else {
      \(tool_name, tool_input, context) deputy::PermissionResultAllow()
    }
  )
}

handoff_fixture_agent <- function(
  mode = "complete",
  async_tool = FALSE,
  deny = FALSE,
  on_result = NULL,
  model_delay = 0
) {
  model <- handoff_local_model_fixture(mode = mode, delay = model_delay)
  readonly <- handoff_graft_readonly_tool()
  producer <- handoff_deputy_measure_tool(mode = mode, async = async_tool)
  agent <- deputy::Agent$new(
    chat = model$chat(),
    tools = list(producer, readonly$tool),
    system_prompt = paste(
      "Call completed_output once. The model prose is not the result.",
      "After the tool returns, finish the task without changing its bytes."
    ),
    permissions = handoff_fixture_permissions(deny = deny),
    usage_limits = deputy::UsageLimits(max_requests = 4L, max_tool_calls = 2L),
    working_dir = getwd(),
    trusted_results = deputy::TrustedResults(
      completed = producer,
      on_result = on_result,
      model_receipt = TRUE
    )
  )
  list(
    agent = agent,
    producer = producer,
    model = model,
    readonly = readonly,
    close = function() {
      model$close()
      readonly$close()
    }
  )
}

handoff_resolve_promise <- function(promise, timeout = 20) {
  value <- new.env(parent = emptyenv())
  value$done <- FALSE
  value$result <- NULL
  value$error <- NULL
  promises::then(
    promise,
    onFulfilled = function(result) {
      value$result <- result
      value$done <- TRUE
      invisible(result)
    },
    onRejected = function(error) {
      value$error <- error
      value$done <- TRUE
      NULL
    }
  )
  deadline <- Sys.time() + timeout
  while (!isTRUE(value$done) && Sys.time() < deadline) {
    later::run_now(0.05)
    Sys.sleep(0.01)
  }
  if (!isTRUE(value$done)) {
    stop("The asynchronous fixture did not resolve before the timeout.")
  }
  if (!is.null(value$error)) {
    stop(value$error)
  }
  value$result
}

handoff_descriptor_bytes <- function(descriptor) {
  jsonlite::base64_dec(descriptor$data)
}

handoff_async_worker_png <- function() {
  path <- tempfile("graft-handoff-worker-")
  process <- callr::r(
    function(path) {
      bytes <- jsonlite::base64_dec(
        paste0(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk",
          "+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
      )
      writeBin(bytes, path)
      list(bytes = bytes, path = path)
    },
    args = list(path = path)
  )
  bytes <- process$bytes
  unlink(path)
  list(bytes = bytes, path = path)
}
