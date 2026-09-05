test_that("real hosts preserve pinned narrative results and canonical receipts", {
  skip_if_not_installed("deputy")
  skip_if_not_installed("dsprrr")
  withr::local_options(lifecycle_verbosity = "quiet")
  store <- local_narrative_store()
  view <- graft_at(store, graft_snapshot(store))
  tools <- graft_tools(view)
  expected <- tools$graft_get(id = "knowledge:interpretation")
  corrected <- narrative_fixture()$narrative_records()$knowledge[
    2L,
    ,
    drop = FALSE
  ]
  corrected$body <- "Later accepted correction."
  graft_ingest(
    store,
    list(knowledge = corrected),
    graft_provenance("host", idempotency_key = "correction")
  )
  for (host in c("ellmer", "deputy", "dsprrr")) {
    local({
      responses <- local_host_responses(
        list(list(
          name = "graft_get",
          arguments = list(id = "knowledge:interpretation")
        )),
        "> The café report suggests a local effect, not a universal result."
      )
      chat <- host_chat(responses)
      run_graft_host(host, chat, tools)
      values <- host_result_values(chat)
      expect_length(values, 1L)
      expect_identical(
        jsonlite::fromJSON(values[[1]], simplifyVector = FALSE),
        jsonlite::fromJSON(
          jsonlite::toJSON(expected, auto_unbox = TRUE, null = "null"),
          simplifyVector = FALSE
        ),
        info = host
      )
      expect_identical(
        grepl("synthetic-reader-private", canonical_json(values)),
        FALSE
      )
      expect_identical(graft_verify(chat)$label[[1]], "cited", info = host)
      expect_gte(length(responses$requests()), 2L)
    })
  }
})

test_that("real hosts retain row bounds and fail closed on errors and mixed tools", {
  skip_if_not_installed("deputy")
  skip_if_not_installed("dsprrr")
  withr::local_options(lifecycle_verbosity = "quiet")
  store <- local_narrative_store()
  tools <- graft_tools(graft_at(store, graft_snapshot(store)))
  extra <- ellmer::tool(
    function() "Unreviewed host evidence",
    name = "host_note",
    description = "Read a synthetic host note.",
    arguments = list(),
    annotations = list(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  cases <- list(
    list(
      calls = list(list(
        name = "graft_find",
        arguments = list(
          query = "reading",
          class = "knowledge",
          limit = 1L
        )
      )),
      expected = tools$graft_find("reading", "knowledge", 1L)
    ),
    list(
      calls = list(list(name = "graft_get", arguments = list(id = "missing")))
    ),
    list(
      calls = list(
        list(name = "graft_get", arguments = list(id = "knowledge:preference")),
        list(name = "host_note", arguments = list())
      )
    )
  )
  for (host in c("ellmer", "deputy", "dsprrr")) {
    for (case in cases) {
      local({
        responses <- local_host_responses(
          case$calls,
          "An uncited answer from the available results."
        )
        chat <- host_chat(responses)
        if (identical(case$calls[[1]]$arguments$id, "missing")) {
          expect_warning(
            run_graft_host(host, chat, c(tools, list(host_note = extra))),
            class = "ellmer_tool_failure"
          )
        } else {
          run_graft_host(host, chat, c(tools, list(host_note = extra)))
        }
        expect_identical(
          graft_verify(chat)$label[[1]],
          "untrusted",
          info = host
        )
        if (!is.null(case$expected)) {
          expect_identical(
            jsonlite::fromJSON(
              host_result_values(chat)[[1]],
              simplifyVector = FALSE
            ),
            jsonlite::fromJSON(
              jsonlite::toJSON(case$expected, auto_unbox = TRUE, null = "null"),
              simplifyVector = FALSE
            ),
            info = host
          )
          expect_identical(case$expected$truncated, TRUE)
        }
      })
    }
  }
})

test_that("host collisions are explicit and must be checked before tool composition", {
  skip_if_not_installed("deputy")
  skip_if_not_installed("dsprrr")
  store <- local_narrative_store()
  tools <- graft_tools(store)
  collision <- ellmer::tool(
    function(id) "replacement",
    name = "graft_get",
    description = "Synthetic collision",
    arguments = list(id = ellmer::type_string())
  )
  combined <- c(tools, list(host_alias = collision))
  expect_identical(
    anyDuplicated(vapply(combined, function(tool) tool@name, character(1))) >
      0L,
    TRUE
  )
  chat <- ellmer::chat_openai_compatible(
    base_url = "https://graft.invalid",
    model = "gpt-4o-mini",
    credentials = function() "offline-test"
  )
  expect_snapshot(chat$set_tools(combined))
  expect_identical(chat$get_tools()$graft_get, collision)
  clean_chat <- chat$clone()
  clean_chat$set_tools(list())
  expect_snapshot(
    error = TRUE,
    deputy::Agent$new(chat = clean_chat, tools = combined)
  )
  module <- dsprrr::react(
    dsprrr::signature("question -> answer"),
    tools = combined,
    chat = chat
  )
  expect_equal(sum(module$list_tools() == "graft_get"), 2L)
})

test_that("long Unicode content survives host offloading without gaining verification", {
  skip_if_not_installed("deputy")
  withr::local_options(lifecycle_verbosity = "quiet")
  store <- local_narrative_store()
  record <- narrative_fixture()$narrative_records()$knowledge[
    2L,
    ,
    drop = FALSE
  ]
  record$body <- paste(
    rep(
      "## Café\n\nA synthetic narrative paragraph — with uncertainty.",
      2000L
    ),
    collapse = "\n\n"
  )
  graft_ingest(
    store,
    list(knowledge = record),
    graft_provenance("host", idempotency_key = "long")
  )
  tools <- graft_tools(graft_at(store, graft_snapshot(store)))
  expected <- tools$graft_get(record$id)
  expect_identical(expected$result$record$body, record$body)
  expect_identical(expected$truncated, FALSE)
  server <- local_host_responses(
    list(list(name = "graft_get", arguments = list(id = record$id))),
    "> A synthetic narrative paragraph — with uncertainty."
  )
  chat <- host_chat(server)
  agent <- deputy::Agent$new(
    chat = chat,
    tools = tools,
    context_policy = deputy::ContextPolicy(
      max_tokens = NULL,
      max_tool_result_bytes = 1024L,
      offload_dir = withr::local_tempdir()
    )
  )
  agent$run_sync("Read the long narrative.")
  value <- host_result_values(chat)[[1]]
  expect_match(value, "Tool result offloaded by Deputy", fixed = TRUE)
  reference <- regmatches(value, regexpr("deputy://tool-result/[^\n ]+", value))
  resolved <- agent$resolve_tool_result(reference)
  expect_identical(resolved, expected)
  expect_lt(nchar(value), nchar(record$body))
  expect_identical(graft_verify(chat)$label[[1]], "untrusted")
})

test_that("the ellmer list-result deprecation remains an explicit compatibility limitation", {
  withr::local_options(lifecycle_verbosity = "warning")
  store <- local_narrative_store()
  server <- local_host_responses(
    list(list(
      name = "graft_get",
      arguments = list(id = "knowledge:preference")
    )),
    "An uncited response."
  )
  chat <- host_chat(server)
  expect_warning(
    run_graft_host("ellmer", chat, graft_tools(store)),
    class = "lifecycle_warning_deprecated"
  )
  expect_identical(graft_verify(chat)$label[[1]], "untrusted")
})
