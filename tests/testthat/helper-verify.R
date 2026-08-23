verification_test_receipt <- function(tool_name = "graft_find") {
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
    )
  )
  if (identical(tool_name, "graft_calculate")) {
    receipt$definitions <- list(list(
      id = "definition:count",
      revision_id = "revision-1",
      kind = "metric"
    ))
  }
  receipt
}

verification_test_call <- function(
  tool_name,
  data,
  id = tool_name,
  truncated = FALSE,
  receipt = verification_test_receipt(tool_name)
) {
  request <- ellmer::ContentToolRequest(
    id = paste0("call-", id),
    name = tool_name,
    arguments = list()
  )
  result <- ellmer::ContentToolResult(
    value = list(
      result = data,
      truncated = truncated,
      limit = 100L,
      receipt = receipt
    ),
    request = request
  )
  list(request = request, result = result)
}

verification_test_chat <- function(calls, answer) {
  chat <- ellmer::chat_openai(model = "gpt-4o-mini")
  chat$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("Question"))),
    ellmer::AssistantTurn(lapply(calls, `[[`, "request")),
    ellmer::UserTurn(lapply(calls, `[[`, "result")),
    ellmer::AssistantTurn(list(ellmer::ContentText(answer)))
  ))
  chat
}
