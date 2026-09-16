# Public transport mocking leaves Commons, ellmer and their tools real. The
# scripted model follows the pinned model-facing schema; this is not a host API.
model_run <- function(
  agent,
  calls,
  final_text = "Fixture calculation complete.",
  async = FALSE
) {
  i <- 0L
  mock <- function(req) {
    i <<- i + 1L
    if (i <= length(calls)) {
      call <- calls[[i]]
      available <- names(agent$get_tools())
      stopifnot(call$name %in% available)
      message <- list(
        role = "assistant",
        content = NULL,
        tool_calls = list(list(
          id = paste0("fixture-", i),
          type = "function",
          `function` = list(
            name = call$name,
            arguments = jsonlite::toJSON(call$args, auto_unbox = TRUE)
          )
        ))
      )
    } else {
      message <- list(
        role = "assistant",
        content = final_text
      )
    }
    payload <- list(
      id = "offline-fixture",
      object = "chat.completion",
      model = "fixture",
      choices = list(list(
        index = 0L,
        message = message,
        finish_reason = if (i <= length(calls)) "tool_calls" else "stop"
      )),
      usage = list(
        prompt_tokens = 0L,
        completion_tokens = 0L,
        total_tokens = 0L
      )
    )
    httr2::response(
      headers = list("content-type" = "application/json"),
      body = charToRaw(jsonlite::toJSON(
        payload,
        auto_unbox = TRUE,
        null = "null"
      ))
    )
  }
  httr2::with_mocked_responses(
    mock,
    {
      if (async) {
        complete <- FALSE
        failure <- NULL
        promises::then(
          agent$chat_async("Run the conformance fixture."),
          function(value) {
            complete <<- TRUE
          },
          function(error) {
            failure <<- error
            complete <<- TRUE
          }
        )
        deadline <- Sys.time() + 60
        while (!complete && Sys.time() < deadline) {
          later::run_now(0.1)
        }
        if (!complete) {
          stop("Offline model fixture timed out.")
        }
        if (!is.null(failure)) stop(failure)
      } else {
        agent$chat("Run the conformance fixture.", echo = "none")
      }
    }
  )
  results <- list()
  for (turn in agent$get_turns()) {
    for (content in turn@contents) {
      if (S7::S7_inherits(content, ellmer::ContentToolResult)) {
        results[[length(results) + 1L]] <- list(
          name = content@request@name,
          value = content@value,
          error = content@error,
          extra = content@extra
        )
      }
    }
  }
  results
}
