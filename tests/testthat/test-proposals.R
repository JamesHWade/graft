test_that("proposal types reuse public contracts without leaking metadata", {
  document <- jsonlite::fromJSON(
    system.file("extdata/team-directory.data-dict.json", package = "graft"),
    simplifyVector = FALSE
  )
  document$description <- "secret-prose"
  document$tables[[2]]$columns[[3]]$display <- "restricted"
  store <- local_dictionary_store(document)
  type <- graft_proposal_type(store, tables = c("person", "employment"))
  expect_s7_class(type, ellmer::TypeJsonSchema)
  schema <- type@json
  expect_named(schema$properties, c("person", "employment"))
  row <- schema$properties$person$items
  expect_named(row$properties, c("id", "full_name"))
  expect_identical(row$additionalProperties, FALSE)
  expect_identical(row$properties$id$type, "string")
  expect_identical(schema$properties$person$maxItems, 100L)
  expect_match(
    schema$properties$employment$items$properties$person_id$description,
    "person primary id",
    fixed = TRUE
  )
  expect_identical(
    grepl("secret-|job_title|examples|origin", canonical_json(schema)),
    FALSE
  )
  selected <- graft_proposal_type(
    store,
    tables = "person",
    fields = list(person = c("id", "full_name"))
  )
  expect_identical(selected@json$properties$person, schema$properties$person)
})

test_that("proposal schemas cover nullable scalar types enums and flat lists", {
  document <- jsonlite::fromJSON(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  document$tables[[1]]$columns <- c(
    document$tables[[1]]$columns,
    list(
      list(name = "active", type = "boolean"),
      list(name = "birthday", type = "date"),
      list(name = "seen", type = "datetime"),
      list(name = "category", type = "enum", values = list("staff", "guest"))
    )
  )
  store <- local_dictionary_store(document)
  properties <- graft_proposal_type(
    store,
    "person"
  )@json$properties$person$items$properties
  expect_identical(properties$age$anyOf[[1]]$type, "number")
  expect_identical(properties$active$anyOf[[1]]$type, "boolean")
  expect_identical(properties$birthday$anyOf[[1]]$format, "date")
  expect_match(properties$seen$anyOf[[1]]$description, "offset")
  expect_identical(properties$category$anyOf[[1]]$enum, list("staff", "guest"))
  expect_identical(properties$aliases$anyOf[[1]]$items$type, "string")
  expect_identical(properties$aliases$anyOf[[2]]$type, "null")
  expect_identical(properties$id$anyOf, NULL)
  proposal <- list(
    person = list(list(
      id = "person:lois",
      full_name = "Lois Lane",
      aliases = list("Lois", "Reporter"),
      age = 35,
      active = TRUE,
      birthday = "1990-01-01",
      seen = "2026-01-01T12:00:00Z",
      category = "staff"
    ))
  )
  plan <- graft_proposal_plan(
    store,
    proposal,
    graft_provenance("test", idempotency_key = "typed-proposal")
  )
  expect_identical(plan@valid, TRUE)
  proposal$person[[1]]$category <- "unknown"
  invalid <- graft_proposal_plan(
    store,
    proposal,
    graft_provenance("test", idempotency_key = "bad-enum")
  )
  expect_identical(invalid@valid, FALSE)
})

test_that("recorded producer output is corrected reviewed and committed idempotently", {
  store <- local_dictionary_store()
  type <- graft_proposal_type(store)
  payload <- list(
    organization = list(),
    person = list(list(id = "person:lois", full_name = NULL, job_title = NULL)),
    employment = list(list(
      id = "employment:lois",
      person_id = "person:lois",
      organization_id = "org:missing"
    ))
  )
  httr2::local_mocked_responses(function(req) {
    httr2::response(
      headers = list(`content-type` = "application/json"),
      body = charToRaw(canonical_json(list(
        id = "offline-message",
        type = "message",
        role = "assistant",
        model = "claude-sonnet-4-5",
        content = list(list(type = "text", text = canonical_json(payload))),
        stop_reason = "end_turn",
        usage = list(input_tokens = 1L, output_tokens = 1L)
      )))
    )
  })
  chat <- ellmer::chat_anthropic(
    model = "claude-sonnet-4-5",
    base_url = "https://graft.invalid",
    credentials = function() "offline-test"
  )
  raw <- chat$chat_structured("Propose records.", type = type, convert = FALSE)
  provenance <- graft_provenance(
    "offline-producer",
    idempotency_key = "proposal-1"
  )
  before <- graft_snapshot(store)
  invalid <- graft_proposal_plan(store, raw, provenance)
  expect_identical(invalid@valid, FALSE)
  expect_gt(nrow(invalid@issues), 0L)
  expect_identical(graft_snapshot(store)@batch_id, before@batch_id)
  payload$person[[1]]$full_name <- "Lois Lane"
  payload$organization <- list(list(id = "org:missing", name = "Daily Planet"))
  raw <- chat$chat_structured(
    "Correct the missing name and organization.",
    type = type,
    convert = FALSE
  )
  plan <- graft_proposal_plan(store, raw, provenance)
  expect_identical(plan@valid, TRUE)
  expect_identical(graft_snapshot(store)@batch_id, before@batch_id)
  expect_identical(nrow(plan@issues), 0L)
  graft_commit(store, plan)
  pinned <- graft_at(store, graft_snapshot(store))
  result <- graft_find(pinned, "Lois", class = "person")
  expect_identical(nrow(result), 1L)
  committed <- graft_snapshot(store)
  graft_commit(store, plan)
  expect_snapshot(
    error = TRUE,
    graft_commit(store, graft_proposal_plan(store, raw, provenance))
  )
  expect_identical(graft_snapshot(store)@batch_id, committed@batch_id)
  expect_identical(graft_find(pinned, "Lois", class = "person"), result)
  expect_identical(
    type@json$properties$person$items$properties$full_name$type,
    "string"
  )
})

test_that("malformed proposals fail without losing rows or fields", {
  store <- local_dictionary_store()
  provenance <- graft_provenance("test", idempotency_key = "malformed")
  valid <- list(
    person = list(list(id = "person:lois", full_name = "Lois Lane"))
  )
  expect_snapshot(
    error = TRUE,
    graft_proposal_plan(store, list(person = data.frame(id = "x")), provenance)
  )
  bad <- valid
  bad$person[[1]]$unknown <- "extra"
  expect_snapshot(error = TRUE, graft_proposal_plan(store, bad, provenance))
  bad <- valid
  bad$person[[1]]$full_name <- 3
  expect_snapshot(error = TRUE, graft_proposal_plan(store, bad, provenance))
  bad <- valid
  bad$person <- rep(bad$person, 2)
  expect_snapshot(
    error = TRUE,
    graft_proposal_plan(store, bad, provenance, max_rows = 1)
  )
  bad <- valid
  bad$person[[1]] <- structure(
    list("person:lois", "other"),
    names = c("id", "id")
  )
  expect_snapshot(error = TRUE, graft_proposal_plan(store, bad, provenance))
  empty <- graft_proposal_plan(store, list(person = list()), provenance)
  expect_identical(empty@valid, TRUE)
})

test_that("public selection cannot omit required fields or include restricted fields", {
  document <- jsonlite::fromJSON(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  document$tables[[1]]$columns[[4]]$display <- "restricted"
  store <- local_dictionary_store(document)
  expect_snapshot(
    error = TRUE,
    graft_proposal_type(store, "person", fields = list(person = "id"))
  )
  expect_snapshot(
    error = TRUE,
    graft_proposal_type(
      store,
      "person",
      fields = list(person = c("id", "full_name", "age"))
    )
  )
  expect_snapshot(
    error = TRUE,
    graft_proposal_plan(
      store,
      list(
        person = list(list(id = "person:lois", full_name = "Lois", age = 4))
      ),
      graft_provenance("test", idempotency_key = "restricted")
    )
  )
  document$tables[[1]]$columns[[4]]$constraints <- list("required")
  required <- local_dictionary_store(document)
  expect_snapshot(error = TRUE, graft_proposal_type(required, "person"))
  fixture <- local_retrieval_store()
  expect_snapshot(error = TRUE, graft_proposal_type(fixture$store))
})

test_that("proposal planning requires provenance replay keys and preserves list element types", {
  document <- jsonlite::fromJSON(
    data_dict_personinfo_export_path(),
    simplifyVector = FALSE
  )
  store <- local_dictionary_store(document)
  rows <- list(
    person = list(list(
      id = "person:lois",
      full_name = "Lois",
      aliases = list(NULL, "Reporter")
    ))
  )
  provenance <- graft_provenance("test", idempotency_key = "list-proposal")
  expect_snapshot(error = TRUE, graft_proposal_plan(store, rows, provenance))
  rows$person[[1]]$aliases <- list(list("nested"))
  expect_snapshot(error = TRUE, graft_proposal_plan(store, rows, provenance))
  rows$person[[1]]$aliases <- list("Reporter")
  expect_snapshot(
    error = TRUE,
    graft_proposal_plan(store, rows, graft_provenance("test"))
  )
})
