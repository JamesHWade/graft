test_that("commons_completion preserves authored content and bounded evidence", {
  value <- handoff_commons_value()
  packet <- commons_completion(
    value,
    operation_id = "commons-operation-1",
    producer = list(system = "commons", measure = "completed_output")
  )

  expect_identical(packet$schema, "graft-output-handoff/0.1")
  expect_identical(packet$operation_id, "commons-operation-1")
  expect_identical(packet$state, "complete")
  expect_identical(packet$errors, list())
  expect_identical(packet$producer$commons_tag, "A")
  expect_identical("display" %in% names(packet$producer), FALSE)

  outputs <- setNames(
    packet$outputs,
    vapply(packet$outputs, `[[`, character(1), "key")
  )
  expect_identical(
    outputs$report$media_type,
    "text/plain"
  )
  expect_identical(
    rawToChar(handoff_descriptor_bytes(outputs$report)),
    "The observed report is 6."
  )
  expect_identical(
    rawToChar(handoff_descriptor_bytes(outputs$table)),
    '{"rows":[{"term":"Headache","count":6}]}'
  )
  expect_identical(
    handoff_descriptor_bytes(outputs$figure),
    handoff_fixture_png()
  )
  expect_identical(outputs$figure$media_type, "image/png")
})

test_that("commons_completion uses host slots without parsing prose", {
  scalar <- commons_completion(
    "{\"rows\":[{\"count\":6}]}",
    operation_id = "commons-operation-2",
    producer = list(system = "commons"),
    keys = "table",
    media_types = "application/json"
  )
  expect_identical(scalar$outputs[[1L]]$key, "table")
  expect_identical(scalar$outputs[[1L]]$media_type, "application/json")
  expect_identical(
    rawToChar(handoff_descriptor_bytes(scalar$outputs[[1L]])),
    "{\"rows\":[{\"count\":6}]}"
  )

  named <- ellmer::ContentToolResult(
    value = list(
      report = ellmer::ContentText("authored report"),
      table = ellmer::ContentText("authored table"),
      figure = ellmer::ContentImageInline("image/png", "YWJj")
    )
  )
  packet <- commons_completion(
    named,
    operation_id = "commons-operation-3",
    producer = list(system = "commons")
  )
  expect_identical(
    vapply(packet$outputs, `[[`, character(1), "key"),
    c("report", "table", "figure")
  )
  expect_identical(
    rawToChar(handoff_descriptor_bytes(packet$outputs[[2L]])),
    "authored table"
  )
})

test_that("commons_completion accepts wrapped and unwrapped bounded base64", {
  bytes <- handoff_large_inline_bytes()
  wrapped <- jsonlite::base64_enc(bytes)
  unwrapped <- gsub("[[:space:]]+", "", wrapped)

  for (data in list(wrapped, unwrapped)) {
    packet <- commons_completion(
      ellmer::ContentToolResult(
        value = list(
          ellmer::ContentImageInline("image/png", data)
        )
      ),
      operation_id = "commons-large-inline",
      producer = list(system = "commons"),
      keys = "figure",
      media_types = "image/png",
      max_bytes = 600L
    )
    expect_identical(
      handoff_descriptor_bytes(packet$outputs[[1L]]),
      bytes
    )
  }
})

test_that("commons_completion rejects errors and unsupported native content", {
  expect_error(
    commons_completion(
      ellmer::ContentToolResult(error = "fixture error"),
      operation_id = "commons-error",
      producer = list(system = "commons"),
      keys = "report",
      media_types = "text/plain"
    ),
    class = "handoff_error"
  )
  expect_error(
    commons_completion(
      ellmer::ContentToolResult(value = data.frame(x = 1L)),
      operation_id = "commons-unsupported",
      producer = list(system = "commons"),
      keys = "report",
      media_types = "text/plain"
    ),
    class = "handoff_error"
  )
  expect_error(
    commons_completion(
      ellmer::ContentToolResult(
        value = list(ellmer::ContentImageInline(
          "image/jpeg",
          "YWJj"
        ))
      ),
      operation_id = "commons-media-mismatch",
      producer = list(system = "commons"),
      keys = "figure",
      media_types = "image/png"
    ),
    class = "handoff_error"
  )
  expect_error(
    commons_completion(
      ellmer::ContentToolResult(
        value = "report",
        extra = list(commons_tag = list("A"))
      ),
      operation_id = "commons-bad-tag",
      producer = list(system = "commons"),
      keys = "report",
      media_types = "text/plain"
    ),
    class = "handoff_error"
  )
  expect_error(
    commons_completion(
      ellmer::ContentToolResult(value = strrep("x", 32L)),
      operation_id = "commons-oversized-text",
      producer = list(system = "commons"),
      keys = "report",
      media_types = "text/plain",
      max_bytes = 8L
    ),
    class = "handoff_error"
  )
  expect_error(
    commons_completion(
      ellmer::ContentToolResult(
        value = list(
          ellmer::ContentImageInline(
            "image/png",
            jsonlite::base64_enc(handoff_fixture_png())
          )
        )
      ),
      operation_id = "commons-oversized-image",
      producer = list(system = "commons"),
      keys = "figure",
      media_types = "image/png",
      max_bytes = 8L
    ),
    class = "handoff_error"
  )
})

test_that("deputy_completion uses the trusted event instead of model prose", {
  fixture <- handoff_fixture_agent()
  on.exit(fixture$close(), add = TRUE)
  result <- fixture$agent$run_sync("Call completed_output once.")

  expect_s7_class(result, deputy::AgentResult)
  expect_identical(result$stop_reason, "complete")
  expect_match(result$response, "999", fixed = TRUE)
  events <- deputy::result_trusted_results(result, type = "completed")
  expect_length(events, 1L)

  packet <- deputy_completion(
    result,
    result_type = "completed",
    operation_id = "deputy-operation-1",
    producer = list(system = "deputy")
  )
  outputs <- setNames(
    packet$outputs,
    vapply(packet$outputs, `[[`, character(1), "key")
  )
  expect_identical(
    rawToChar(handoff_descriptor_bytes(outputs$report)),
    "The observed report is 6."
  )
  expect_identical(
    grepl(
      "999",
      rawToChar(handoff_descriptor_bytes(outputs$report)),
      fixed = TRUE
    ),
    FALSE
  )
  expect_identical(packet$producer$trusted_result$result_type, "completed")
  expect_identical(packet$producer$commons_tag, "A")
  expect_identical("display" %in% names(packet$producer), FALSE)
  expect_identical(
    packet$producer$trusted_result$tool_name,
    "completed_output"
  )
  expect_identical(nzchar(packet$producer$trusted_result$result_id), TRUE)
  expect_identical(
    nzchar(packet$producer$trusted_result$tool_fingerprint),
    TRUE
  )
  expect_identical(nzchar(packet$producer$trusted_result$tool_call_id), TRUE)
  expect_identical(packet$producer$trusted_result$arguments, list())
})

test_that("deputy_completion handles a real promise-returning producer", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  fixture <- handoff_fixture_agent(async_tool = TRUE)
  on.exit(fixture$close(), add = TRUE)
  promise <- fixture$agent$run_async("Call completed_output once.")
  expect_identical(promises::is.promising(promise), TRUE)
  result <- handoff_resolve_promise(promise)
  expect_s7_class(result, deputy::AgentResult)
  expect_identical(result$stop_reason, "complete")
  packet <- deputy_completion(
    result,
    result_type = "completed",
    operation_id = "deputy-operation-async",
    producer = list(system = "deputy", async = TRUE)
  )
  expect_identical(packet$state, "complete")
  expect_identical(
    rawToChar(handoff_descriptor_bytes(packet$outputs[[1L]])),
    "The observed report is 6."
  )
})

test_that("deputy_completion rejects an interrupted asynchronous run", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  fixture <- handoff_fixture_agent(async_tool = TRUE, model_delay = 1)
  on.exit(fixture$close(), add = TRUE)
  promise <- fixture$agent$run_async("Call completed_output once.")
  later::later(
    \() fixture$agent$interrupt("interrupted"),
    delay = 0.05
  )
  result <- handoff_resolve_promise(promise)
  expect_identical(result$stop_reason, "interrupted")
  expect_error(
    deputy_completion(
      result,
      result_type = "completed",
      operation_id = "deputy-interrupted",
      producer = list(system = "deputy", interrupted = TRUE)
    ),
    class = "handoff_error"
  )
})

test_that("deputy_completion rejects no event and native producer errors", {
  no_event <- handoff_fixture_agent(mode = "noevent")
  on.exit(no_event$close(), add = TRUE)
  no_event_result <- no_event$agent$run_sync("Do not call a tool.")
  expect_identical(no_event_result$stop_reason, "complete")
  expect_length(
    deputy::result_trusted_results(no_event_result, type = "completed"),
    0L
  )
  expect_error(
    deputy_completion(
      no_event_result,
      result_type = "completed",
      operation_id = "deputy-no-event",
      producer = list(system = "deputy")
    ),
    class = "handoff_error"
  )

  native_error <- handoff_fixture_agent(mode = "native-error")
  on.exit(native_error$close(), add = TRUE)
  native_result <- suppressWarnings(
    native_error$agent$run_sync("Call completed_output once.")
  )
  expect_length(
    deputy::result_trusted_results(native_result, type = "completed"),
    0L
  )
  expect_error(
    deputy_completion(
      native_result,
      result_type = "completed",
      operation_id = "deputy-native-error",
      producer = list(system = "deputy")
    ),
    class = "handoff_error"
  )
})

test_that("deputy_completion rejects a trusted-result delivery failure", {
  fixture <- handoff_fixture_agent(
    on_result = \(event) stop("fixture delivery failure")
  )
  on.exit(fixture$close(), add = TRUE)
  result <- suppressWarnings(
    fixture$agent$run_sync("Call completed_output once.")
  )
  events <- deputy::result_trusted_results(result, type = "completed")
  expect_length(events, 1L)
  expect_error(
    deputy_completion(
      result,
      result_type = "completed",
      operation_id = "deputy-delivery-failure",
      producer = list(system = "deputy")
    ),
    class = "handoff_error"
  )
})

test_that("deputy_completion rejects permission denial", {
  fixture <- handoff_fixture_agent(deny = TRUE)
  on.exit(fixture$close(), add = TRUE)
  result <- fixture$agent$run_sync("Call completed_output once.")
  expect_identical(result$stop_reason, "permission_denied")
  expect_length(
    deputy::result_trusted_results(result, type = "completed"),
    0L
  )
  expect_error(
    deputy_completion(
      result,
      result_type = "completed",
      operation_id = "deputy-permission-denied",
      producer = list(system = "deputy")
    ),
    class = "handoff_error"
  )
})

test_that("worker teardown leaves owned PNG bytes available to the host", {
  result <- handoff_async_worker_png()
  expect_identical(file.exists(result$path), FALSE)
  expect_identical(
    result$bytes,
    handoff_fixture_png()
  )
  output <- handoff_output("figure", result$bytes, "image/png")
  expect_identical(handoff_descriptor_bytes(output), result$bytes)
})
