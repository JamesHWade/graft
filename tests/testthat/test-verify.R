test_that("graft_verify validates chats and returns a stable empty result", {
  chat <- ellmer::chat_openai(model = "gpt-4o-mini")
  broken <- new.env(parent = emptyenv())
  broken$get_turns <- \() stop("turn failure")
  class(broken) <- c("Chat", "R6")

  condition <- rlang::catch_cnd(graft_verify(1))
  turns_condition <- rlang::catch_cnd(graft_verify(broken))
  empty <- graft_verify(chat)

  expect_s3_class(condition, "graft_validation_error")
  expect_snapshot(conditionMessage(condition))
  expect_s3_class(turns_condition, "graft_validation_error")
  expect_snapshot(conditionMessage(turns_condition))
  expect_identical(
    names(empty),
    c(
      "answer_index",
      "turn_index",
      "answer_text",
      "label",
      "reason_codes",
      "receipts",
      "citations",
      "tool_calls",
      "diagnostics"
    )
  )
  expect_identical(class(empty), c("graft_verification", "data.frame"))
  expect_identical(nrow(empty), 0L)
  expect_type(empty$answer_index, "integer")
  expect_type(empty$turn_index, "integer")
  expect_type(empty$answer_text, "character")
  expect_type(empty$label, "character")
  expect_type(empty$reason_codes, "list")
  expect_type(empty$receipts, "list")
  expect_type(empty$citations, "list")
  expect_type(empty$tool_calls, "list")
  expect_type(empty$diagnostics, "list")
})

test_that("graft_verify classifies completed text answers in windows", {
  partial_turn <- tryCatch(
    getExportedValue("ellmer", "AssistantPartialTurn"),
    error = \(error) NULL
  )
  skip_if(is.null(partial_turn), "ellmer does not export partial turns")
  request <- ellmer::ContentToolRequest(
    id = "call-weather",
    name = "weather",
    arguments = list()
  )
  result <- ellmer::ContentToolResult(
    value = list(temperature = 70),
    request = request
  )
  chat <- ellmer::chat_openai(model = "gpt-4o-mini")
  chat$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("Question"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("First answer"))),
    ellmer::AssistantTurn(list(request)),
    ellmer::UserTurn(list(result)),
    partial_turn(list(ellmer::ContentText("Interrupted answer"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Second answer")))
  ))

  verification <- graft_verify(chat)

  expect_identical(verification$answer_index, c(1L, 2L))
  expect_identical(verification$turn_index, c(2L, 6L))
  expect_identical(
    verification$answer_text,
    c("First answer", "Second answer")
  )
  expect_identical(verification$label, c("untrusted", "untrusted"))
  expect_identical(
    verification$reason_codes,
    list("no_evidence", "non_graft_tool")
  )
  expect_identical(lengths(verification$tool_calls), c(0L, 1L))
  expect_identical(
    verification$tool_calls[[2L]][[1L]],
    list(request = request, result = result)
  )
})

test_that("graft_verify verifies governed measure-only evidence", {
  digest <- paste0("sha256:", strrep("a", 64L))
  receipt <- list(
    store = list(id = "store-1"),
    boundary = list(
      kind = "live",
      batch_id = "batch-1",
      commit_order = 1
    ),
    schema = list(
      structural_digest = digest,
      build_digest = digest
    ),
    definition = list(
      id = "measure:entity-count",
      revision_id = "revision-1"
    )
  )
  request <- ellmer::ContentToolRequest(
    id = "call-measure",
    name = "graft_measure",
    arguments = list(name = "entity-count")
  )
  result <- ellmer::ContentToolResult(
    value = list(
      result = data.frame(value = 2),
      truncated = FALSE,
      limit = 1000L,
      receipt = receipt
    ),
    request = request
  )
  chat <- ellmer::chat_openai(model = "gpt-4o-mini")
  chat$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("Count the entities"))),
    ellmer::AssistantTurn(list(request)),
    ellmer::UserTurn(list(result)),
    ellmer::AssistantTurn(list(ellmer::ContentText("There are two.")))
  ))

  verification <- graft_verify(chat)

  expect_identical(verification$label, "verified")
  expect_identical(
    verification$reason_codes,
    list("governed_measure_only")
  )
  expect_identical(verification$receipts, list(list(receipt)))
  expect_identical(verification$citations, list(list()))
  expect_identical(
    verification$tool_calls[[1L]][[1L]],
    list(request = request, result = result)
  )
})

test_that("graft_verify uses a result's linked request without a request turn", {
  digest <- paste0("sha256:", strrep("f", 64L))
  request <- ellmer::ContentToolRequest(
    id = "call-result-only",
    name = "graft_measure",
    arguments = list(name = "entity-count")
  )
  receipt <- list(
    store = list(id = "store-1"),
    boundary = list(
      kind = "live",
      batch_id = "batch-1",
      commit_order = 1
    ),
    schema = list(
      structural_digest = digest,
      build_digest = digest
    ),
    definition = list(
      id = "measure:entity-count",
      revision_id = "revision-1"
    )
  )
  result <- ellmer::ContentToolResult(
    value = list(
      result = data.frame(value = 2),
      truncated = FALSE,
      limit = 1000L,
      receipt = receipt
    ),
    request = request
  )
  chat <- ellmer::chat_openai(model = "gpt-4o-mini")
  chat$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("Count the entities"))),
    ellmer::UserTurn(list(result)),
    ellmer::AssistantTurn(list(ellmer::ContentText("There are two.")))
  ))

  verification <- graft_verify(chat)

  expect_identical(verification$label, "verified")
  expect_identical(
    verification$reason_codes,
    list("governed_measure_only")
  )
  expect_identical(
    verification$tool_calls,
    list(list(list(request = request, result = result)))
  )
  expect_identical(verification$receipts, list(list(receipt)))
})

test_that("graft_verify fails closed for unsupported evidence paths", {
  digest <- paste0("sha256:", strrep("b", 64L))
  receipt <- function(kind = "live", definition = FALSE) {
    boundary <- list(kind = kind, batch_id = "batch-1", commit_order = 1)
    if (identical(kind, "snapshot")) {
      boundary$snapshot_id <- digest
    }
    value <- list(
      store = list(id = "store-1"),
      boundary = boundary,
      schema = list(
        structural_digest = digest,
        build_digest = digest
      )
    )
    if (definition) {
      value$definition <- list(id = "measure:count", revision_id = "rev-1")
    }
    value
  }
  envelope <- function(receipt) {
    list(
      result = data.frame(value = 1),
      truncated = FALSE,
      limit = 100L,
      receipt = receipt
    )
  }
  verify_call <- function(request, result) {
    chat <- ellmer::chat_openai(model = "gpt-4o-mini")
    chat$set_turns(list(
      ellmer::UserTurn(list(ellmer::ContentText("Question"))),
      ellmer::AssistantTurn(list(request)),
      ellmer::UserTurn(list(result)),
      ellmer::AssistantTurn(list(ellmer::ContentText("Answer")))
    ))
    graft_verify(chat)
  }
  call_result <- function(name, value, error = NULL, id = name) {
    request <- ellmer::ContentToolRequest(
      id = paste0("call-", id),
      name = name,
      arguments = list()
    )
    result <- ellmer::ContentToolResult(
      value = value,
      error = error,
      request = request
    )
    verify_call(request, result)
  }

  generic <- call_result("graft_find", envelope(receipt()))
  historical <- call_result(
    "graft_history",
    envelope(receipt("history")),
    id = "history"
  )
  external <- call_result("weather", list(value = 70))
  external_error <- call_result(
    "weather",
    NULL,
    error = "weather failed",
    id = "weather-error"
  )
  errored <- call_result(
    "graft_measure",
    NULL,
    error = "measure failed",
    id = "error"
  )

  expect_identical(generic$reason_codes, list("unmatched_citation"))
  expect_identical(historical$reason_codes, list("unmatched_citation"))
  expect_identical(external$reason_codes, list("non_graft_tool"))
  expect_identical(
    external_error$reason_codes,
    list(c("non_graft_tool", "tool_error"))
  )
  expect_identical(errored$reason_codes, list("tool_error"))
  expect_identical(
    c(generic$label, historical$label, external$label, errored$label),
    rep("untrusted", 4L)
  )

  invalid_values <- list()
  invalid_values$missing_receipt <- envelope(receipt())[1:3]
  invalid_values$bad_truncated <- envelope(receipt())
  invalid_values$bad_truncated$truncated <- NA
  invalid_values$bad_store <- envelope(receipt())
  invalid_values$bad_store$receipt$store$id <- ""
  invalid_values$bad_schema <- envelope(receipt())
  invalid_values$bad_schema$receipt$schema$build_digest <- toupper(digest)
  invalid_values$bad_order <- envelope(receipt())
  invalid_values$bad_order$receipt$boundary$commit_order <- 2^53
  invalid_values$bad_batch <- envelope(receipt())
  invalid_values$bad_batch$receipt$boundary$batch_id <- NULL
  invalid_values$bad_snapshot <- envelope(receipt("snapshot"))
  invalid_values$bad_snapshot$receipt$boundary$snapshot_id <- "not-a-digest"
  invalid_values$history_for_find <- envelope(receipt("history"))
  invalid_values$definition_for_find <- envelope(receipt())
  invalid_values$definition_for_find$receipt$definition <- list(
    id = "measure:count",
    revision_id = "rev-1"
  )
  invalid_values$measure_without_definition <- envelope(receipt())
  invalid_values$measure_history <- envelope(receipt("history", TRUE))

  invalid <- lapply(names(invalid_values), function(id) {
    name <- if (startsWith(id, "measure_")) {
      "graft_measure"
    } else {
      "graft_find"
    }
    call_result(name, invalid_values[[id]], id = id)
  })
  expect_identical(
    lapply(invalid, \(value) value$reason_codes[[1L]]),
    rep(list("invalid_receipt"), length(invalid))
  )
})

test_that("graft_verify contains malformed traces to their answer", {
  verify_middle <- function(middle) {
    chat <- ellmer::chat_openai(model = "gpt-4o-mini")
    chat$set_turns(c(
      list(ellmer::UserTurn(list(ellmer::ContentText("Question")))),
      middle,
      list(ellmer::AssistantTurn(list(ellmer::ContentText("Answer"))))
    ))
    graft_verify(chat)
  }
  request <- function(id = "call-1", name = "graft_measure") {
    ellmer::ContentToolRequest(id = id, name = name, arguments = list())
  }
  result <- function(request) {
    digest <- paste0("sha256:", strrep("c", 64L))
    ellmer::ContentToolResult(
      value = list(
        result = data.frame(value = 1),
        truncated = FALSE,
        limit = 100L,
        receipt = list(
          store = list(id = "store-1"),
          boundary = list(
            kind = "live",
            batch_id = "batch-1",
            commit_order = 1
          ),
          schema = list(
            structural_digest = digest,
            build_digest = digest
          ),
          definition = list(
            id = "measure:count",
            revision_id = "rev-1"
          )
        )
      ),
      request = request
    )
  }
  recorded <- request()
  mismatched_request <- request("call-mismatched")
  dangling <- verify_middle(list(ellmer::AssistantTurn(list(recorded))))
  orphan <- verify_middle(list(
    ellmer::UserTurn(list(ellmer::ContentToolResult(value = list())))
  ))
  duplicate_request <- verify_middle(list(
    ellmer::AssistantTurn(list(recorded, recorded)),
    ellmer::UserTurn(list(result(recorded)))
  ))
  duplicate_result <- verify_middle(list(
    ellmer::AssistantTurn(list(recorded)),
    ellmer::UserTurn(list(result(recorded), result(recorded)))
  ))
  duplicate_id_request <- request("call-1", "weather")
  duplicate_id <- verify_middle(list(
    ellmer::AssistantTurn(list(recorded, duplicate_id_request)),
    ellmer::UserTurn(list(
      result(recorded),
      result(duplicate_id_request)
    ))
  ))
  mismatched <- verify_middle(list(
    ellmer::AssistantTurn(list(recorded)),
    ellmer::UserTurn(list(result(mismatched_request)))
  ))
  request_in_user_turn <- verify_middle(list(
    ellmer::UserTurn(list(recorded)),
    ellmer::UserTurn(list(result(recorded)))
  ))
  result_in_assistant_turn <- verify_middle(list(
    ellmer::AssistantTurn(list(recorded)),
    ellmer::AssistantTurn(list(result(recorded)))
  ))
  unsupported_content <- verify_middle(list(
    ellmer::UserTurn(list(
      ellmer::ContentImageRemote("https://example.com/image.png")
    ))
  ))

  observed <- list(
    dangling,
    orphan,
    duplicate_request,
    duplicate_result,
    duplicate_id,
    mismatched,
    request_in_user_turn,
    result_in_assistant_turn,
    unsupported_content
  )
  expect_identical(
    lapply(observed, \(value) value$reason_codes[[1L]]),
    list(
      "unsupported_trace",
      "unsupported_trace",
      "unsupported_trace",
      "unsupported_trace",
      c("non_graft_tool", "unsupported_trace"),
      "unsupported_trace",
      "unsupported_trace",
      "unsupported_trace",
      "unsupported_trace"
    )
  )
  expect_identical(
    lapply(observed, \(value) value$label),
    rep(list("untrusted"), length(observed))
  )
})

test_that("graft_verify diagnoses truncation and mixed accepted boundaries", {
  digest <- paste0("sha256:", strrep("d", 64L))
  request <- function(id) {
    ellmer::ContentToolRequest(
      id = id,
      name = "graft_measure",
      arguments = list(name = "count")
    )
  }
  result <- function(request, kind, batch_id, commit_order, truncated) {
    boundary <- list(
      kind = kind,
      batch_id = batch_id,
      commit_order = commit_order
    )
    if (identical(kind, "snapshot")) {
      boundary$snapshot_id <- digest
    }
    ellmer::ContentToolResult(
      value = list(
        result = data.frame(value = 1),
        truncated = truncated,
        limit = 100L,
        receipt = list(
          store = list(id = "store-1"),
          boundary = boundary,
          schema = list(
            structural_digest = digest,
            build_digest = digest
          ),
          definition = list(
            id = "measure:count",
            revision_id = "revision-1"
          )
        )
      ),
      request = request
    )
  }
  first <- request("call-first")
  same_boundary <- request("call-same-boundary")
  later <- request("call-later")
  chat <- ellmer::chat_openai(model = "gpt-4o-mini")
  chat$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("Compare counts"))),
    ellmer::AssistantTurn(list(first, same_boundary, later)),
    ellmer::UserTurn(list(
      result(first, "live", "batch-1", 1, TRUE),
      result(same_boundary, "snapshot", "batch-1", 1, FALSE),
      result(later, "live", "batch-2", 2, FALSE)
    )),
    ellmer::AssistantTurn(list(ellmer::ContentText("Comparison complete")))
  ))

  verification <- graft_verify(chat)

  expect_identical(verification$label, "verified")
  expect_identical(
    verification$reason_codes,
    list("governed_measure_only")
  )
  expect_identical(
    verification$diagnostics,
    list(c("truncated_result", "mixed_boundaries"))
  )
})

test_that("graft_verify pairs each answer with its recorded tool window", {
  digest <- paste0("sha256:", strrep("e", 64L))
  request <- function(id, name) {
    ellmer::ContentToolRequest(
      id = id,
      name = "graft_measure",
      arguments = list(name = name)
    )
  }
  result <- function(request, definition_id) {
    ellmer::ContentToolResult(
      value = list(
        result = data.frame(value = 1),
        truncated = FALSE,
        limit = 100L,
        receipt = list(
          store = list(id = "store-1"),
          boundary = list(
            kind = "live",
            batch_id = "batch-1",
            commit_order = 1
          ),
          schema = list(
            structural_digest = digest,
            build_digest = digest
          ),
          definition = list(id = definition_id, revision_id = "revision-1")
        )
      ),
      request = request
    )
  }
  first <- request("call-1", "first")
  second <- request("call-2", "second")
  reused_id <- request("call-1", "third")
  first_result <- result(first, "measure:first")
  second_result <- result(second, "measure:second")
  reused_result <- result(reused_id, "measure:third")
  chat <- ellmer::chat_openai(model = "gpt-4o-mini")
  chat$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("First question"))),
    ellmer::AssistantTurn(list(first, second)),
    ellmer::UserTurn(list(second_result, first_result)),
    ellmer::AssistantTurn(list(ellmer::ContentText("First answer"))),
    ellmer::UserTurn(list(ellmer::ContentText("Second question"))),
    ellmer::AssistantTurn(list(reused_id)),
    ellmer::UserTurn(list(reused_result)),
    ellmer::AssistantTurn(list(ellmer::ContentText("Second answer")))
  ))

  verification <- graft_verify(chat)

  expect_identical(verification$label, c("verified", "verified"))
  expect_identical(lengths(verification$tool_calls), c(2L, 1L))
  expect_identical(
    verification$tool_calls[[1L]],
    list(
      list(request = first, result = first_result),
      list(request = second, result = second_result)
    )
  )
  expect_identical(
    verification$tool_calls[[2L]],
    list(list(request = reused_id, result = reused_result))
  )
  expect_identical(
    lapply(verification$receipts, function(receipts) {
      vapply(receipts, \(receipt) receipt$definition$id, character(1))
    }),
    list(c("measure:first", "measure:second"), "measure:third")
  )
})

test_that("graft_verify cites an explicit quotation from a generic result", {
  evidence <- "Lois Lane is an investigative reporter at the Daily Planet."
  call <- verification_test_call(
    "graft_find",
    data.frame(summary = evidence)
  )
  chat <- verification_test_chat(
    list(call),
    paste0("The record says \"", evidence, "\"")
  )

  verification <- graft_verify(chat)

  expect_identical(verification$label, "cited")
  expect_identical(verification$reason_codes, list("matched_citations"))
  expect_identical(
    verification$citations,
    list(list(list(
      tool_call_index = 1L,
      candidate_type = "quotation",
      text = evidence,
      result_path = "result$summary",
      result_text = evidence
    )))
  )
})

test_that("graft_verify normalizes candidates without weakening fixed matching", {
  evidence <- "Lois Lane - investigative reporter"
  verify <- function(answer) {
    call <- verification_test_call(
      "graft_get",
      data.frame(summary = evidence)
    )
    graft_verify(verification_test_chat(list(call), answer))
  }

  normalized <- verify(
    "According to Graft, “**Lois   Lane** — investigative reporter”."
  )
  wrong_case <- verify(
    "According to Graft, \"lois Lane - investigative reporter\"."
  )
  too_short <- verify("The record names \"Lois Lane\".")
  unquoted <- verify(paste("The record says", evidence))

  expect_identical(normalized$label, "cited")
  expect_identical(
    normalized$citations[[1L]][[1L]]$text,
    "**Lois   Lane** — investigative reporter"
  )
  expect_identical(
    c(wrong_case$label, too_short$label, unquoted$label),
    rep("untrusted", 3L)
  )
  expect_identical(
    lapply(
      list(wrong_case, too_short, unquoted),
      \(value) value$reason_codes[[1L]]
    ),
    rep(list("unmatched_citation"), 3L)
  )
})

test_that("graft_verify cites consecutive Markdown blockquote lines", {
  evidence <- "Lois Lane is an investigative reporter at the Daily Planet."
  quoted <- paste(
    "Lois Lane is an investigative reporter",
    "at the Daily Planet.",
    sep = "\n"
  )
  call <- verification_test_call(
    "graft_query",
    data.frame(summary = evidence)
  )
  chat <- verification_test_chat(
    list(call),
    paste(
      "The accepted record says:",
      "> Lois Lane is an investigative reporter",
      "> at the Daily Planet.",
      sep = "\n"
    )
  )

  verification <- graft_verify(chat)

  expect_identical(verification$label, "cited")
  expect_identical(
    verification$citations,
    list(list(list(
      tool_call_index = 1L,
      candidate_type = "blockquote",
      text = quoted,
      result_path = "result$summary",
      result_text = evidence
    )))
  )
})

test_that("graft_verify requires matched evidence from every generic result", {
  employment <- "Lois Lane works at the Daily Planet."
  title <- "Lois Lane is an investigative reporter."
  first <- verification_test_call(
    "graft_find",
    data.frame(summary = employment),
    id = "employment"
  )
  title_data <- data.frame(id = "person:lois-lane")
  title_data$details <- list(list(summary = title))
  second <- verification_test_call(
    "graft_get",
    title_data,
    id = "title"
  )
  calls <- list(first, second)

  complete <- graft_verify(verification_test_chat(
    calls,
    paste0("The records say \"", employment, "\" and \"", title, "\"")
  ))
  partial <- graft_verify(verification_test_chat(
    calls,
    paste0("The record says \"", employment, "\"")
  ))

  expect_identical(complete$label, "cited")
  expect_identical(
    vapply(
      complete$citations[[1L]],
      `[[`,
      integer(1),
      "tool_call_index"
    ),
    c(1L, 2L)
  )
  expect_identical(
    complete$citations[[1L]][[2L]]$result_path,
    "result$details[[1]]$summary"
  )
  expect_identical(partial$label, "untrusted")
  expect_identical(partial$reason_codes, list("unmatched_citation"))
  expect_identical(lengths(partial$citations), 1L)
})

test_that("graft_verify caps mixed measure and generic evidence at cited", {
  evidence <- "Lois Lane works at the Daily Planet."
  measure <- verification_test_call(
    "graft_measure",
    data.frame(value = 1),
    id = "count"
  )
  generic <- verification_test_call(
    "graft_history",
    data.frame(summary = evidence),
    id = "history"
  )
  calls <- list(measure, generic)

  matched <- graft_verify(verification_test_chat(
    calls,
    paste0("The accepted record says \"", evidence, "\"")
  ))
  unmatched <- graft_verify(verification_test_chat(
    calls,
    "The accepted record supports the answer."
  ))

  expect_identical(matched$label, "cited")
  expect_identical(matched$reason_codes, list("matched_citations"))
  expect_identical(
    matched$citations[[1L]][[1L]]$tool_call_index,
    2L
  )
  expect_identical(unmatched$label, "untrusted")
  expect_identical(unmatched$reason_codes, list("unmatched_citation"))
})

test_that("citation normalization removes emphasis without altering identifiers", {
  observed <- vapply(
    c(
      "**Lois** _Lane_",
      "__Daily Planet__",
      "record_identifier_name",
      "a*b*c"
    ),
    graft_verification_normalize_text,
    character(1)
  )

  expect_identical(
    unname(observed),
    c(
      "Lois Lane",
      "Daily Planet",
      "record_identifier_name",
      "a*b*c"
    )
  )
})

test_that("graft_verify searches only explicit answer citations and result values", {
  evidence <- "Lois Lane works at the Daily Planet."
  receipt <- verification_test_receipt("graft_find")
  receipt$store$id <- "store-identifier-only-in-receipt"
  call <- verification_test_call(
    "graft_find",
    data.frame(summary = evidence),
    receipt = receipt
  )
  receipt_only <- graft_verify(verification_test_chat(
    list(call),
    "The receipt says \"store-identifier-only-in-receipt\"."
  ))
  chat <- ellmer::chat_openai(model = "gpt-4o-mini")
  chat$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText(
      paste0("Does the record say \"", evidence, "\"?")
    ))),
    ellmer::AssistantTurn(list(call$request)),
    ellmer::UserTurn(list(call$result)),
    ellmer::AssistantTurn(list(ellmer::ContentText(
      "The accepted record supports that statement."
    )))
  ))

  question_only <- graft_verify(chat)

  expect_identical(receipt_only$label, "untrusted")
  expect_identical(question_only$label, "untrusted")
  expect_identical(
    list(receipt_only$reason_codes, question_only$reason_codes),
    list(list("unmatched_citation"), list("unmatched_citation"))
  )
})

test_that("graft_verify preserves diagnostics for cited evidence", {
  first_text <- "Lois Lane works at the Daily Planet."
  second_text <- "Lois Lane is an investigative reporter."
  first <- verification_test_call(
    "graft_find",
    data.frame(summary = first_text),
    id = "first",
    truncated = TRUE
  )
  later_receipt <- verification_test_receipt("graft_get")
  later_receipt$boundary$batch_id <- "batch-2"
  later_receipt$boundary$commit_order <- 2
  second <- verification_test_call(
    "graft_get",
    data.frame(summary = second_text),
    id = "second",
    receipt = later_receipt
  )
  chat <- verification_test_chat(
    list(first, second),
    paste0("The records say \"", first_text, "\" and \"", second_text, "\"")
  )

  verification <- graft_verify(chat)

  expect_identical(verification$label, "cited")
  expect_identical(
    verification$diagnostics,
    list(c("truncated_result", "mixed_boundaries"))
  )
})
