test_that("dictionary discovery scopes meaning and distinguishes semantics", {
  store <- local_dictionary_store()
  value <- graft_dictionary(store, table = "person", field = "full_name")
  rows <- value$result$entries
  expect_setequal(rows$field[rows$field != ""], "full_name")
  expect_setequal(rows$table[rows$table != ""], "person")
  expect_identical(
    rows$value[rows$kind == "column" & rows$name == "description"],
    "Current display name for the person."
  )
  expect_identical(
    rows$value[rows$kind == "contract" & rows$name == "required"],
    "true"
  )
  expect_setequal(
    unique(rows$semantics),
    c("supported", "descriptive", "unsupported")
  )
  expect_identical(rows$name[rows$kind == "glossary"], "stable identifier")
  relations <- graft_dictionary(store, "employment", "person_id")$result$entries
  pairs <- jsonlite::fromJSON(
    relations$value[
      relations$kind == "relationship" & relations$name == "pairs"
    ],
    simplifyVector = FALSE
  )
  expect_identical(
    pairs[[1]]$left,
    list(table = "employment", column = "person_id")
  )
  expect_identical(pairs[[1]]$right, list(table = "person", column = "id"))
  expect_identical(value$truncated, FALSE)
  expect_identical(value$result$next_offset, NULL)
  expect_identical(
    graft_verification_receipt_valid("graft_dictionary", value),
    TRUE
  )
})

test_that("dictionary pages are deterministic and clip oversized prose", {
  store <- local_dictionary_store()
  view <- graft_at(store, graft_snapshot(store))
  whole <- graft_dictionary(view, "person", "full_name")
  first <- graft_dictionary(view, "person", "full_name", limit = 3)
  second <- graft_dictionary(
    view,
    "person",
    "full_name",
    limit = 3,
    offset = first$result$next_offset
  )
  expect_equal(first$result$entries, whole$result$entries[1:3, ])
  expected <- whole$result$entries[4:6, ]
  rownames(expected) <- NULL
  expect_equal(second$result$entries, expected)
  expect_identical(first$truncated, TRUE)
  expect_identical(first$receipt, second$receipt)
  empty <- graft_dictionary(view, offset = 1000000)
  expect_identical(nrow(empty$result$entries), 0L)
  expect_identical(empty$truncated, FALSE)
  document <- jsonlite::fromJSON(
    system.file("extdata/team-directory.data-dict.json", package = "graft"),
    simplifyVector = FALSE
  )
  document$description <- strrep("é", 2500)
  long <- graft_dictionary(local_dictionary_store(document))
  rows <- long$result$entries
  expect_identical(
    nchar(rows$value[rows$kind == "dataset" & rows$name == "description"]),
    2000L
  )
  expect_identical(any(rows$text_truncated), TRUE)
  expect_identical(long$truncated, TRUE)
})

test_that("restricted metadata and provider values stay out of every discovery consumer", {
  document <- jsonlite::fromJSON(
    system.file("extdata/team-directory.data-dict.json", package = "graft"),
    simplifyVector = FALSE
  )
  document$origin <- "secret-origin"
  document$relationships[[2]]$pairs[[1]]$left$origin <- "secret-pair-origin"
  document$tables[[2]]$source <- "secret-source"
  document$tables[[2]]$assertions <- list(list(
    expression = "job_title != \"secret\"",
    columns = list("job_title")
  ))
  document$tables[[2]]$columns[[2]]$assertions <- document$tables[[
    2
  ]]$assertions
  document$tables[[2]]$columns[[3]]$display <- "restricted"
  document$tables[[2]]$columns[[3]]$description <- "secret-description"
  document$tables[[2]]$columns[[2]]$examples <- list("secret-example")
  document$relationships[[1]]$pairs[[1]]$left$column <- "job_title"
  document$relationships[[1]]$pairs[[1]]$left$table <- "person"
  document$relationships[[1]]$join <- "person.job_title = person.id"
  document$relationships[[1]]$description <- "secret-relationship"
  # The relationship is descriptive; remove the now-unpaired foreign-key flag.
  document$tables[[3]]$columns[[2]]$constraints <- list("required")
  document$tables[[3]]$columns[[2]]$references <- NULL
  store <- local_dictionary_store(document)
  view <- graft_at(store, graft_snapshot(store))
  direct <- graft_dictionary(view)
  tool <- graft_tools(view)$graft_dictionary
  expect_identical(tool(), direct)
  expect_identical(grepl("secret-|job_title", canonical_json(direct)), FALSE)
  expect_snapshot(error = TRUE, graft_dictionary(view, "person", "job_title"))
})

test_that("real dictionary tools discover a field before a bounded read", {
  store <- local_dictionary_store()
  graft_ingest(
    store,
    list(person = data.frame(id = "person:lois", full_name = "Lois Lane")),
    graft_provenance("test", idempotency_key = "dictionary-person")
  )
  view <- graft_at(store, graft_snapshot(store))
  tools <- graft_tools(view)
  info <- tools$graft_dictionary(table = "person", field = "full_name")
  rows <- info$result$entries
  table <- unique(rows$table[rows$kind == "column"])
  read <- tools$graft_find(query = "Lois", class = table, limit = 1L)
  expect_identical(nrow(read$result), 1L)
  expect_identical(read$receipt, info$receipt)
  graft_ingest(
    store,
    list(person = data.frame(id = "person:lois", full_name = "Updated name")),
    graft_provenance("test", idempotency_key = "dictionary-person-v2")
  )
  expect_identical(
    tools$graft_dictionary(table = "person", field = "full_name"),
    info
  )
  expect_identical(
    graft_dictionary(store, "person", "full_name")$result,
    info$result
  )
  expect_gt(
    graft_dictionary(store)$receipt$boundary$commit_order,
    info$receipt$boundary$commit_order
  )
})

test_that("discovery validates selection and paging at the public boundary", {
  store <- local_dictionary_store()
  expect_snapshot(error = TRUE, graft_dictionary(store, field = "id"))
  expect_snapshot(error = TRUE, graft_dictionary(store, table = "missing"))
  expect_snapshot(error = TRUE, graft_dictionary(store, limit = 101))
  expect_snapshot(error = TRUE, graft_dictionary(store, offset = -1))
  fixture <- local_retrieval_store()
  expect_snapshot(error = TRUE, graft_dictionary(fixture$store))
})

test_that("dictionary evidence is cited rather than calculation evidence", {
  store <- local_dictionary_store()
  graft_ingest(
    store,
    list(
      GraftDefinition = data.frame(
        name = "people_count",
        target = "person",
        expr = "ROW_COUNT()"
      )
    ),
    graft_provenance("test", idempotency_key = "dictionary-count")
  )
  tools <- graft_tools(graft_at(store, graft_snapshot(store)))
  request <- ellmer::ContentToolRequest(
    id = "dictionary",
    name = "graft_dictionary",
    arguments = list(table = "person", field = "full_name"),
    tool = tools$graft_dictionary
  )
  value <- tools$graft_dictionary(table = "person", field = "full_name")
  calculate <- ellmer::ContentToolRequest(
    id = "count",
    name = "graft_calculate",
    arguments = list(metrics = "people_count"),
    tool = tools$graft_calculate
  )
  count <- tools$graft_calculate(metrics = "people_count")
  verify <- function(answer, calculation = FALSE, metadata = value) {
    requests <- list(request)
    results <- list(ellmer::ContentToolResult(
      value = metadata,
      request = request
    ))
    if (calculation) {
      requests <- c(requests, list(calculate))
      results <- c(
        results,
        list(ellmer::ContentToolResult(value = count, request = calculate))
      )
    }
    chat <- ellmer::chat_openai(model = "gpt-4o-mini")
    chat$set_turns(list(
      ellmer::UserTurn(list(ellmer::ContentText("Explain the field."))),
      ellmer::AssistantTurn(requests),
      ellmer::UserTurn(results),
      ellmer::AssistantTurn(list(ellmer::ContentText(answer)))
    ))
    graft_verify(chat)
  }
  quote <- '> Current display name for the person.'
  expect_identical(verify(quote)$label, "cited")
  expect_identical(verify(quote, calculation = TRUE)$label, "cited")
  expect_identical(verify("The field is a name.")$label, "untrusted")
  expect_identical(
    verify("The field is a name.", calculation = TRUE)$label,
    "untrusted"
  )
  bad <- value
  bad$receipt <- NULL
  expect_identical(
    verify(quote, metadata = bad)$reason_codes[[1]],
    "invalid_receipt"
  )
})

test_that("public assertions and units are descriptive and source metadata is omitted", {
  document <- jsonlite::fromJSON(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  document$tables[[1]]$columns[[4]]$units <- "years"
  document$tables[[1]]$columns[[4]]$assertions[[
    1
  ]]$origin <- "secret-assertion-origin"
  store <- local_dictionary_store(document)
  value <- graft_dictionary(store, "person", "age")
  rows <- value$result$entries
  expect_identical(rows$value[rows$name == "units"], "years")
  assertion <- rows[rows$kind == "column" & rows$name == "assertions", ]
  expect_match(assertion$value, "Age cannot be negative.", fixed = TRUE)
  expect_identical(assertion$semantics, "descriptive")
  expect_identical(
    grepl("secret-assertion-origin", canonical_json(value), fixed = TRUE),
    FALSE
  )
})

test_that("discovery does not turn range relationships into equality joins", {
  document <- jsonlite::fromJSON(
    system.file("extdata/team-directory.data-dict.json", package = "graft"),
    simplifyVector = FALSE
  )
  document$relationships[[1]]$join <- "employment.person_id >= person.id"
  rows <- graft_dictionary(
    local_dictionary_store(document),
    "employment",
    "person_id"
  )$result$entries
  expect_identical(
    any(rows$kind == "relationship" & rows$name == "join"),
    FALSE
  )
  expect_identical(sum(rows$kind == "relationship" & rows$name == "pairs"), 1L)
})
