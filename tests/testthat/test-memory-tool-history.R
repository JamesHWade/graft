test_that("restored tool cards show the consultation recorded before withdrawal", {
  skip_if_not_installed("ellmer")
  skip_if_not_installed("shinychat")

  store <- graft_store(withr::local_tempdir(), create = TRUE)
  ref <- graft_save(store, "Use the reviewed blue reference.", id = "reference")
  decision <- graft_accept(
    store,
    ref,
    stream = "reference",
    expected = NULL,
    key = "review-1",
    actor = "reviewer",
    reason = "Reviewed",
    purpose = "consult"
  )
  consultations <- 0L
  tool <- graft_tool(store, "reference", "consult", function() {
    consultations <<- consultations + 1L
    TRUE
  })
  request <- ellmer::ContentToolRequest(id = "call-1", name = tool@name)
  result <- tool()
  result@request <- request
  turns <- list(
    ellmer::Turn("user", list(ellmer::ContentText("Which reference?"))),
    ellmer::Turn("assistant", list(request)),
    ellmer::Turn("user", list(result)),
    ellmer::Turn("assistant", list(ellmer::ContentText("Use blue.")))
  )
  chat <- ellmer::chat_openai_compatible("http://localhost", model = "offline")
  chat$register_tool(tool)
  actions <- list()
  server <- function(input, output, session) {
    session$sendCustomMessage <- function(type, message) {
      if (identical(type, "shinyChatMessage")) {
        actions[[length(actions) + 1L]] <<- message$action
      }
    }
    shinychat::chat_enable_history(
      "chat",
      chat,
      options = shinychat::history_options(
        restore_mode = "none",
        store = "memory",
        scope = "test",
        title = NULL
      )
    )
  }
  shiny::testServer(server, {
    session$flushReact()
    chat$set_turns(turns)
    shinychat::chat_append("chat", "Use blue.")
    for (i in seq_len(50L)) {
      session$flushReact()
      updates <- Filter(\(x) identical(x$type, "history_update"), actions)
      active_id <- utils::tail(updates, 1L)[[1L]]$active_id
      if (!is.null(active_id)) break
    }
    expect_type(active_id, "character")
    session$setInputs(chat_history_new = list(nonce = 1L))
    expect_length(chat$get_turns(), 0L)
    graft_withdraw(
      store,
      stream = "reference",
      expected = decision,
      key = "withdraw-1",
      actor = "reviewer",
      reason = "Recalled reference withdrawn"
    )
    before_restore <- length(actions)
    session$setInputs(chat_history_select = list(id = active_id))
    expect_length(chat$get_turns(), length(turns))
    restored <- utils::tail(actions, length(actions) - before_restore)
    messages <- Filter(\(x) identical(x$type, "message"), restored)
    segments <- unlist(
      lapply(messages, \(x) x$message$segments),
      recursive = FALSE
    )
    cards <- Filter(\(x) identical(x$type, "tool_result"), segments)
    expect_length(cards, 1L)
    card <- cards[[1L]]
    expect_identical(card$request_id, "call-1")
    expect_identical(card$label, "Project memory consulted")
    expect_match(card$value_preview, "consulted", fixed = TRUE)
    expect_match(card$value, "Use the reviewed blue reference.", fixed = TRUE)
    expect_identical(consultations, 1L)
    expect_identical(jsonlite::fromJSON(tool()@value)$status, "withdrawn")
  })
})
