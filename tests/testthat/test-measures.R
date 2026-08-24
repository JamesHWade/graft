test_that("every compiled schema carries the GraftDefinition system class", {
  schema <- graft_schema(tempest_manifest_path())
  contract <- schema@manifest$classes$GraftDefinition
  expect_identical(contract$role, "metadata")
  expect_identical(contract$view, "graft_definition")
  expect_identical(contract$id_policy, "deterministic")
  expect_identical(contract$origin_key_slots, list("target", "name"))
  expect_contains(
    names(contract$slots),
    c(
      "id",
      "name",
      "target",
      "expr",
      "label",
      "description",
      "details"
    )
  )
})

test_that("a proposed definition is discoverable from accepted state", {
  store <- local_graft_ingest_store()
  records <- list(
    GraftDefinition = data.frame(
      name = "entity-count",
      target = "Entity",
      expr = "ROW_COUNT()",
      label = "Entity count",
      description = "Number of accepted entities.",
      details = "Counts every accepted entity."
    )
  )
  plan <- graft_plan(
    store,
    records,
    graft_provenance(producer = "test", idempotency_key = "definition-v1")
  )
  expect_identical(nrow(plan@issues), 0L)
  graft_commit(store, plan)

  definitions <- graft_definitions(store)
  expect_identical(definitions$name, "entity-count")
  expect_identical(definitions$target, "Entity")
  expect_identical(definitions$kind, "metric")
  expect_identical(definitions$dependencies[[1L]], character())
  expect_contains(definitions$columns[[1L]], c("id", "label"))
  expect_match(definitions$id, "^graft:")

  fetched <- graft_get(store, definitions$id)
  expect_identical(fetched$class, "GraftDefinition")
  expect_identical(fetched$record$expr, "ROW_COUNT()")
})

test_that("plan-time validation rejects invalid definition graphs", {
  store <- local_graft_ingest_store()
  records <- list(
    GraftDefinition = data.frame(
      name = c("bad_expr", "bad_target", "label", "cycle_a", "cycle_b"),
      target = c("Entity", "Nope", "Entity", "Entity", "Entity"),
      expr = c(
        "MEDIAN(label)",
        "ROW_COUNT()",
        "LOWER(label)",
        "cycle_b + 1",
        "cycle_a + 1"
      )
    )
  )
  plan <- graft_plan(store, records, graft_provenance(producer = "test"))
  issues <- plan@issues[plan@issues$class == "GraftDefinition", ]
  expect_identical(
    issues$rule[issues$input_row == 1L],
    "definition_expr_function"
  )
  expect_identical(
    issues$rule[issues$input_row == 2L],
    "definition_target"
  )
  expect_identical(
    issues$rule[issues$input_row == 3L],
    "definition_column_shadow"
  )
  expect_setequal(
    issues$rule[issues$input_row %in% 4:5],
    rep("definition_cycle", 2L)
  )
})

test_that("incomplete definitions report ordinary plan issues", {
  store <- local_graft_ingest_store()

  plan <- graft_plan(
    store,
    list(
      GraftDefinition = data.frame(
        name = c(NA_character_, "missing_expr"),
        target = "Entity",
        expr = c("ROW_COUNT()", NA_character_)
      )
    ),
    graft_provenance(producer = "test")
  )

  issues <- plan@issues[plan@issues$class == "GraftDefinition", ]
  expect_identical(issues$input_row, c(1L, 1L, 2L))
  expect_identical(
    issues$rule,
    c("required", "deterministic_key_complete", "required")
  )
})

test_that("data-dict contract definitions seed accepted definitions", {
  document <- jsonlite::fromJSON(
    system.file(
      "extdata",
      "team-directory.data-dict.json",
      package = "graft",
      mustWork = TRUE
    ),
    simplifyVector = FALSE
  )
  table_names <- vapply(
    document$tables,
    \(table) table$name,
    character(1)
  )
  person <- match("person", table_names)
  document$tables[[person]]$definitions <- list(
    list(
      name = "headcount",
      label = "Headcount",
      description = "Number of people in the directory.",
      expr = "ROW_COUNT()"
    )
  )
  contract <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(
    document,
    contract,
    auto_unbox = TRUE,
    null = "null"
  )

  schema <- graft_schema(contract)
  store <- graft_open(schema, ":memory:", okf = "disabled")
  withr::defer(graft_close(store))

  definitions <- graft_definitions(store)
  expect_identical(definitions$name, "headcount")
  expect_identical(definitions$label, "Headcount")
  expect_identical(definitions$target, "person")
  expect_identical(definitions$kind, "metric")

  history <- graft_history(store, definitions$id)
  expect_identical(nrow(history), 1L)
})

test_that("definition kinds and types follow data-dict semantics", {
  store <- local_graft_ingest_store()
  valid <- graft_plan(
    store,
    list(
      GraftDefinition = data.frame(
        name = c("constant", "starts_with_s", "constant_plus_one"),
        target = "Entity",
        expr = c("1", "STARTS_WITH(label, 's')", "constant + 1")
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "definition-kinds")
  )
  expect_identical(nrow(valid@issues), 0L)
  graft_commit(store, valid)
  definitions <- graft_definitions(store)
  expect_identical(
    definitions$kind[
      match(
        c("constant", "starts_with_s", "constant_plus_one"),
        definitions$name
      )
    ],
    c("metric", "filter", "metric")
  )

  invalid <- graft_plan(
    store,
    list(
      GraftDefinition = data.frame(
        name = c("bad_sum", "mixed_grain"),
        target = "Entity",
        expr = c("SUM(label)", "ROW_COUNT() + label")
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "definition-types")
  )
  expect_identical(
    invalid@issues$rule,
    rep("definition_expr_type", 2L)
  )
})

test_that("column selections stay boolean and singular through composition", {
  store <- local_graft_ingest_store()
  plan <- graft_plan(
    store,
    list(
      GraftDefinition = data.frame(
        name = c("not_boolean", "first", "second", "both"),
        target = "Entity",
        expr = c(
          "COLUMNS([label])",
          "COLUMNS([id]) IS NOT NULL",
          "COLUMNS([label]) IS NOT NULL",
          "first AND second"
        )
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "selections")
  )

  expect_identical(
    plan@issues$rule[plan@issues$input_row == 1L],
    "definition_expr_type"
  )
  expect_identical(
    plan@issues$rule[plan@issues$input_row == 4L],
    "definition_expr_selection"
  )
})

test_that("changing a dependency cannot invalidate an accepted definition", {
  store <- local_graft_ingest_store()
  initial <- graft_plan(
    store,
    list(
      GraftDefinition = data.frame(
        name = c("label_length", "total_label_length"),
        target = "Entity",
        expr = c("LENGTH(label)", "SUM(label_length)")
      )
    ),
    graft_provenance(
      producer = "test",
      idempotency_key = "dependent-types-v1"
    )
  )
  expect_identical(nrow(initial@issues), 0L)
  graft_commit(store, initial)

  update <- graft_plan(
    store,
    list(
      GraftDefinition = data.frame(
        name = "label_length",
        target = "Entity",
        expr = "LOWER(label)"
      )
    ),
    graft_provenance(
      producer = "test",
      idempotency_key = "dependent-types-v2"
    )
  )

  expect_identical(update@issues$input_row, 1L)
  expect_identical(update@issues$rule, "definition_expr_type")
  expect_match(update@issues$message, "total_label_length", fixed = TRUE)
})

test_that("renaming or retargeting cannot strand accepted definitions", {
  changes <- list(
    rename = list(
      name = "renamed_label_length",
      target = "Entity",
      expr = "LENGTH(label)"
    ),
    retarget = list(
      name = "label_length",
      target = "Source",
      expr = "LENGTH(title)"
    )
  )
  for (change_name in names(changes)) {
    change <- changes[[change_name]]
    store <- local_graft_ingest_store()
    graft_ingest(
      store,
      list(
        GraftDefinition = data.frame(
          name = c("label_length", "total_label_length"),
          target = "Entity",
          expr = c("LENGTH(label)", "SUM(label_length)")
        )
      ),
      graft_provenance(
        producer = "test",
        idempotency_key = paste0("strand-dependent-v1-", change_name)
      )
    )
    definitions <- graft_definitions(store, target = "Entity")
    dependency_id <- definitions$id[
      match("label_length", definitions$name)
    ]
    update <- graft_plan(
      store,
      list(
        GraftDefinition = data.frame(
          id = dependency_id,
          name = change$name,
          target = change$target,
          expr = change$expr
        )
      ),
      graft_provenance(
        producer = "test",
        idempotency_key = paste0("strand-dependent-v2-", change_name)
      )
    )

    expect_identical(update@issues$input_row, 1L)
    expect_identical(update@issues$rule, "definition_expr_type")
    expect_match(update@issues$message, "total_label_length", fixed = TRUE)
  }
})

test_that("definition plans bind the complete accepted definition catalog", {
  store <- local_graft_ingest_store()
  graft_ingest(
    store,
    list(
      GraftDefinition = data.frame(
        name = c("helper", "total"),
        target = "Entity",
        expr = c("1", "ROW_COUNT()")
      )
    ),
    graft_provenance(
      producer = "test",
      idempotency_key = "definition-boundary-v1"
    )
  )
  unrelated <- graft_plan(
    store,
    list(
      Entity = data.frame(
        id = test_graft_id("definition-boundary-entity"),
        label = "base",
        preferred_name = "Boundary entity"
      )
    ),
    graft_provenance(
      producer = "entity-test",
      idempotency_key = "definition-boundary-entity"
    )
  )
  stale <- graft_plan(
    store,
    list(
      GraftDefinition = data.frame(
        name = "helper",
        target = "Entity",
        expr = "LOWER(label)"
      )
    ),
    graft_provenance(
      producer = "test",
      idempotency_key = "definition-boundary-stale"
    )
  )
  expect_identical(nrow(stale@issues), 0L)
  graft_ingest(
    store,
    list(
      GraftDefinition = data.frame(
        name = "total",
        target = "Entity",
        expr = "SUM(helper)"
      )
    ),
    graft_provenance(
      producer = "test",
      idempotency_key = "definition-boundary-v2"
    )
  )

  condition <- catch_graft_ingest_condition(graft_commit(store, stale))
  unrelated_result <- graft_commit(store, unrelated)

  expect_s3_class(condition, "graft_commit_plan_stale")
  expect_match(
    conditionMessage(condition),
    "definition catalog changed after planning",
    fixed = TRUE
  )
  definitions <- graft_definitions(store, target = "Entity")
  expect_identical(
    definitions$expr[match(c("helper", "total"), definitions$name)],
    c("1", "SUM(helper)")
  )
  expect_identical(unrelated_result$inserted, c(Entity = 1L))
})
