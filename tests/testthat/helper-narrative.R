narrative_fixture <- function() {
  env <- new.env(parent = environment())
  sys.source(
    system.file("examples/narrative-knowledge.R", package = "graft"),
    env
  )
  env
}

local_narrative_store <- function(
  path = ":memory:",
  .local_envir = parent.frame()
) {
  store <- graft_open(
    graft_schema(system.file(
      "extdata/narrative-knowledge.data-dict.json",
      package = "graft"
    )),
    path,
    okf = "disabled"
  )
  withr::defer(graft_close(store), envir = .local_envir)
  graft_ingest(
    store,
    narrative_fixture()$narrative_records(),
    graft_provenance("synthetic-host", idempotency_key = "seed")
  )
  store
}

local_host_responses <- function(calls, answer, .local_envir = parent.frame()) {
  directory <- withr::local_tempdir(.local_envir = .local_envir)
  process <- callr::r_bg(
    function(directory, calls, answer) {
      port <- httpuv::randomPort()
      count <- 0L
      server <- httpuv::startServer(
        "127.0.0.1",
        port,
        list(call = function(req) {
          count <<- count + 1L
          request <- jsonlite::fromJSON(
            rawToChar(req$rook.input$read()),
            simplifyVector = FALSE
          )
          saveRDS(request, file.path(directory, paste0(count, ".rds")))
          message <- list(
            role = "assistant",
            content = if (count == 2L) {
              answer
            } else {
              as.character(jsonlite::toJSON(
                list(answer = answer),
                auto_unbox = TRUE
              ))
            }
          )
          finish <- "stop"
          if (count == 1L) {
            message$content <- NULL
            message$tool_calls <- lapply(seq_along(calls), function(i) {
              list(
                index = i - 1L,
                id = paste0("call-", i),
                type = "function",
                `function` = list(
                  name = calls[[i]]$name,
                  arguments = as.character(jsonlite::toJSON(
                    calls[[i]]$arguments,
                    auto_unbox = TRUE
                  ))
                )
              )
            })
            finish <- "tool_calls"
          }
          usage <- list(
            prompt_tokens = 1L,
            completion_tokens = 1L,
            total_tokens = 2L
          )
          encode <- function(x) {
            as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
          }
          stream <- isTRUE(request$stream)
          body <- if (stream) {
            paste0(
              "data: ",
              encode(list(
                id = "fixture",
                model = "gpt-4o-mini",
                choices = list(list(index = 0L, delta = message))
              )),
              "\n\n",
              "data: ",
              encode(list(
                id = "fixture",
                model = "gpt-4o-mini",
                choices = list(list(
                  index = 0L,
                  delta = list(),
                  finish_reason = finish
                )),
                usage = usage
              )),
              "\n\ndata: [DONE]\n\n"
            )
          } else {
            encode(list(
              id = "fixture",
              model = "gpt-4o-mini",
              choices = list(list(
                index = 0L,
                message = message,
                finish_reason = finish
              )),
              usage = usage
            ))
          }
          list(
            status = 200L,
            headers = list(
              `Content-Type` = if (stream) {
                "text/event-stream"
              } else {
                "application/json"
              }
            ),
            body = body
          )
        })
      )
      on.exit(server$stop())
      saveRDS(port, file.path(directory, "port"))
      repeat {
        httpuv::service(50)
      }
    },
    args = list(directory = directory, calls = calls, answer = answer)
  )
  withr::defer(process$kill(), envir = .local_envir)
  deadline <- Sys.time() + 15
  while (!file.exists(file.path(directory, "port"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      stop("Offline host fixture failed to start")
    }
    Sys.sleep(0.02)
  }
  list(
    url = paste0(
      "http://127.0.0.1:",
      readRDS(file.path(directory, "port")),
      "/v1"
    ),
    requests = function() {
      lapply(
        list.files(directory, pattern = "[.]rds$", full.names = TRUE),
        readRDS
      )
    }
  )
}

host_chat <- function(server) {
  ellmer::chat_openai_compatible(
    model = "gpt-4o-mini",
    base_url = server$url,
    credentials = function() "offline-test",
    echo = "none"
  )
}

host_result_values <- function(chat) {
  contents <- unlist(
    lapply(chat$get_turns(), \(turn) turn@contents),
    recursive = FALSE
  )
  results <- Filter(
    \(content) inherits(content, "ellmer::ContentToolResult"),
    contents
  )
  lapply(results, \(result) result@value)
}

run_graft_host <- function(host, chat, tools) {
  switch(
    host,
    ellmer = {
      chat$set_tools(tools)
      chat$chat("Read the accepted knowledge.", echo = "none")
    },
    deputy = {
      agent <- deputy::Agent$new(
        chat = chat,
        tools = tools,
        context_policy = deputy::ContextPolicy(
          max_tokens = NULL,
          max_tool_result_bytes = NULL
        )
      )
      agent$run_sync("Read the accepted knowledge.")
    },
    dsprrr = {
      module <- dsprrr::react(
        dsprrr::signature("question -> answer"),
        tools = tools,
        chat = chat
      )
      dsprrr::run(module, question = "Read the accepted knowledge.")
    }
  )
  invisible(chat)
}

narrative_dictionary_yaml <- function() {
  document <- yaml::read_yaml(system.file(
    "extdata/narrative-knowledge.data-dict.yaml",
    package = "graft"
  ))
  document$tables <- lapply(document$tables, function(table) {
    table$columns <- lapply(table$columns, function(column) {
      for (key in intersect(
        c("constraints", "examples", "values"),
        names(column)
      )) {
        column[[key]] <- as.list(column[[key]])
      }
      column
    })
    table
  })
  document
}
