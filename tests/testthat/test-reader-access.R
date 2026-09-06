test_that("isolated Readers cannot discover each other's records or counts", {
  host <- local_reader_access()
  for (reader in c("alice", "bob")) {
    other <- if (reader == "alice") "bob" else "alice"
    access <- host[[reader]]
    values <- access(function(store) {
      snapshot <- graft_snapshot(store)
      view <- graft_at(store, snapshot)
      list(
        own = graft_get(view, "knowledge:preference"),
        search = graft_find(view, other),
        history = graft_history(
          view,
          paste0("knowledge:interpretation:", reader)
        ),
        changes = graft_changes(
          view,
          record_ids = paste0("source:trial-v1:", other)
        ),
        all_changes = graft_changes(view),
        dictionary = graft_dictionary(view, limit = 2L),
        page = graft_dictionary(view, limit = 2L, offset = 2L),
        source = graft_get(view, paste0("source:trial-v1:", reader)),
        support = graft_get(view, paste0("support:interpretation:", reader)),
        count = graft_calculate(view, "knowledge_count"),
        tools = names(graft_tools(view))
      )
    })
    expect_match(values$own$record$body, paste0("^", reader))
    expect_equal(nrow(values$search), 0L)
    expect_equal(nrow(values$history), 1L)
    expect_equal(nrow(values$changes), 0L)
    expect_equal(nrow(values$all_changes), if (reader == "alice") 8L else 7L)
    expect_identical(values$dictionary$receipt, values$page$receipt)
    expect_equal(nrow(values$page$result$entries), 2L)
    expect_identical(
      values$dictionary$receipt$store$id,
      host$locations[[reader]]$store_id
    )
    expect_identical(
      grepl(paste0("\\b", other, "\\b"), canonical_json(values)),
      FALSE
    )
    expect_identical(grepl("private-owner-", canonical_json(values)), FALSE)
    expect_equal(values$count$knowledge_count, if (reader == "alice") 4 else 3)
    expect_contains(values$tools, "graft_calculate")
    for (id in c(paste0("knowledge:interpretation:", other), "absent")) {
      error <- tryCatch(access(\(store) graft_get(store, id)), error = identity)
      expect_s3_class(error, "reader_knowledge_unavailable")
      expect_identical(
        conditionMessage(error),
        "Accepted knowledge is unavailable."
      )
      expect_null(error$parent)
      expect_error(
        access(\(store) graft_history(store, id)),
        class = "reader_knowledge_unavailable"
      )
    }
  }
})

test_that("foreign snapshots, relationships, and changed store mappings fail closed", {
  host <- local_reader_access()
  expect_error(
    host$alice(\(store) graft_at(store, host$locations$bob$snapshot)),
    class = "reader_knowledge_unavailable"
  )
  expect_error(
    host$alice(\(store) {
      graft_changes(store, since = host$locations$bob$snapshot)
    }),
    class = "reader_knowledge_unavailable"
  )
  plan <- host$alice(function(store) {
    graft_plan(
      store,
      list(
        support = data.frame(
          id = "support:foreign",
          knowledge_id = "knowledge:interpretation:alice",
          source_id = "source:trial-v1:bob",
          anchor = "paragraph:1"
        )
      ),
      graft_provenance("synthetic-host")
    )
  })
  expect_identical(plan@valid, FALSE)
  swapped <- host$locations$alice
  swapped$path <- host$locations$bob$path
  access <- host$example$reader_knowledge_access(
    "alice",
    \(reader) swapped,
    \(reader) "grant-1"
  )
  expect_error(access(graft_snapshot), class = "reader_knowledge_unavailable")
  missing <- host$locations$alice
  missing$path <- withr::local_tempfile(fileext = ".duckdb")
  access <- host$example$reader_knowledge_access(
    "alice",
    \(reader) missing,
    \(reader) "grant-1"
  )
  expect_error(access(graft_snapshot), class = "reader_knowledge_unavailable")
  expect_identical(file.exists(missing$path), FALSE)
  expect_error(
    host$alice(\(store) {
      graft_query(store, "neighbors", list(id = "source:trial-v1:bob"))
    }),
    class = "reader_knowledge_unavailable"
  )
})

test_that("revocation blocks construction and old tools without returning cached content", {
  host <- local_reader_access()
  tool <- host$example$reader_record_tool(
    host$alice,
    host$locations$alice$snapshot
  )
  expected <- tool("knowledge:preference")
  expect_match(expected, "alice Prefer short")
  host$grants$alice <- NULL
  expect_error(
    tool("knowledge:preference"),
    class = "reader_knowledge_unavailable"
  )
  expect_error(
    host$example$reader_record_tool(host$alice, host$locations$alice$snapshot),
    class = "reader_knowledge_unavailable"
  )
  host$grants$alice <- "alice-grant-2"
  expect_identical(tool("knowledge:preference"), expected)
  value <- "not released"
  expect_error(
    value <- host$alice(function(store) {
      result <- graft_get(store, "knowledge:preference")
      host$grants$alice <- "alice-grant-3"
      result
    }),
    class = "reader_knowledge_unavailable"
  )
  expect_identical(value, "not released")
  host$grants$alice <- NULL
  expect_match(
    host$bob(\(store) graft_get(store, "knowledge:preference"))$record$body,
    "^bob"
  )
  opened <- 0L
  denied <- host$example$reader_knowledge_access(
    "alice",
    function(reader) {
      opened <<- opened + 1L
      host$locations[[reader]]
    },
    \(reader) NULL
  )
  expect_error(denied(graft_snapshot), class = "reader_knowledge_unavailable")
  expect_identical(opened, 0L)
})

test_that("reopened tools preserve pinned receipts after an accepted correction", {
  host <- local_reader_access()
  tool <- host$example$reader_record_tool(
    host$alice,
    host$locations$alice$snapshot
  )
  before <- tool("knowledge:preference")
  location <- host$locations$alice
  writer <- graft_open(
    graft_schema(location$schema),
    location$path,
    okf = "disabled"
  )
  withr::defer(graft_close(writer))
  record <- narrative_fixture()$narrative_records()$knowledge[3L, ]
  record$body <- "alice Prefer reading in the evening."
  record$owner_binding <- "private-owner-alice"
  graft_ingest(
    writer,
    list(knowledge = record),
    graft_provenance("synthetic-host")
  )
  after <- graft_snapshot(writer)
  graft_close(writer)
  expect_identical(tool("knowledge:preference"), before)
  current <- host$example$reader_record_tool(host$alice, after)
  expect_match(current("knowledge:preference"), "evening")
  changes <- host$alice(\(store) {
    graft_changes(
      store,
      since = host$locations$alice$snapshot
    )
  })
  expect_identical(changes$record_id, "knowledge:preference")
  expect_identical(changes$action, "update")
})

test_that("agent tool calls bind to the authenticated host rather than an argument", {
  withr::local_options(lifecycle_verbosity = "error")
  host <- local_reader_access()
  tool <- host$example$reader_record_tool(
    host$alice,
    host$locations$alice$snapshot
  )
  server <- local_host_responses(
    list(
      list(name = "graft_get", arguments = list(id = "knowledge:preference")),
      list(
        name = "graft_get",
        arguments = list(id = "knowledge:interpretation:bob")
      ),
      list(
        name = "graft_get",
        arguments = list(id = "knowledge:preference", reader = "bob")
      ),
      list(name = "graft_find", arguments = list(query = "bob"))
    ),
    "The available record belongs to Alice."
  )
  chat <- host_chat(server)
  chat$set_tools(list(graft_get = tool))
  expect_warning(
    chat$chat("Read accepted knowledge.", echo = "none"),
    class = "ellmer_tool_failure"
  )
  values <- host_result_values(chat)
  expect_identical(values[[1L]], tool("knowledge:preference"))
  expect_identical(
    grepl("bob private|bob Prefer|private-owner-", canonical_json(values)),
    FALSE
  )
  expect_identical(graft_verify(chat)$label[[1L]], "untrusted")
  expect_named(chat$get_tools(), "graft_get")
})

test_that("fresh workers rebind trusted locations and reject another Reader's basis", {
  host <- local_reader_access()
  basis <- host$alice(function(store) {
    reuse_example()$capture_reuse_basis(
      store,
      "knowledge:preference",
      data.frame(outcome = character(), dependency = character())
    )
  })
  checkpoint <- withr::local_tempfile(fileext = ".rds")
  saveRDS(basis, checkpoint)
  result <- callr::r(
    function(checkout, locations, checkpoint) {
      if (!is.null(checkout)) {
        pkgload::load_all(checkout, quiet = TRUE)
      }
      example <- new.env()
      sys.source(
        system.file("examples/reader-access.R", package = "graft"),
        example
      )
      sys.source(
        system.file("examples/reuse-basis.R", package = "graft"),
        example
      )
      basis <- readRDS(checkpoint)
      read <- function(reader) {
        access <- example$reader_knowledge_access(
          reader,
          \(reader) locations[[reader]],
          \(reader) "worker-grant-1"
        )
        tryCatch(
          access(\(store) example$read_reuse_basis(store, basis, \(ids) TRUE)),
          reader_knowledge_unavailable = conditionMessage
        )
      }
      list(alice = read("alice"), bob = read("bob"))
    },
    args = list(
      checkout = if (pkgload::is_dev_package("graft")) {
        normalizePath(test_path("../.."))
      } else {
        NULL
      },
      locations = host$locations,
      checkpoint = checkpoint
    )
  )
  expect_match(result$alice[[1L]]$body, "^alice")
  expect_identical(result$bob, "Accepted knowledge is unavailable.")
  expect_named(
    basis,
    c("version", "snapshot", "roots", "records", "dependencies")
  )
})

test_that("a real Deputy run retains the authorized Reader's receipt and citation", {
  skip_if_not_installed("deputy")
  withr::local_options(lifecycle_verbosity = "error")
  host <- local_reader_access()
  tool <- host$example$reader_record_tool(host$bob, host$locations$bob$snapshot)
  server <- local_host_responses(
    list(list(
      name = "graft_get",
      arguments = list(id = "knowledge:preference")
    )),
    "> bob Prefer short reading sessions in the morning; this is a preference, not source evidence."
  )
  chat <- host_chat(server)
  run_graft_host("deputy", chat, list(graft_get = tool))
  expect_identical(host_result_values(chat), list(tool("knowledge:preference")))
  expect_identical(graft_verify(chat)$label[[1L]], "cited")
  expect_identical(
    grepl("alice|private-owner-", canonical_json(host_result_values(chat))),
    FALSE
  )
})
