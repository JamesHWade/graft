test_that("graft_calculate() composes same-table definitions", {
  store <- local_definition_store()

  total <- graft_calculate(
    store,
    metrics = c("entity_count", "named_count")
  )
  expect_identical(names(total), c("entity_count", "named_count"))
  expect_identical(total$entity_count, 3)
  expect_identical(total$named_count, 3)

  grouped <- graft_calculate(
    store,
    metrics = "entity_count",
    dimensions = "label"
  )
  expect_identical(grouped$label, c("acid", "solvent"))
  expect_identical(grouped$entity_count, c(1, 2))

  filtered <- graft_calculate(
    store,
    metrics = "entity_count",
    filters = "solvent_filter"
  )
  expect_identical(filtered$entity_count, 2)

  derived <- graft_calculate(
    store,
    metrics = "entity_count",
    dimensions = "lowercase_label"
  )
  expect_identical(derived$lowercase_label, c("acid", "solvent"))
})

test_that("graft_calculate() binds predicates and records definition closure", {
  store <- local_definition_store()

  result <- graft_calculate(
    store,
    metrics = c("entity_count", "has_solvent"),
    where = list(list(value = "acid", op = "!=", column = "label"))
  )

  expect_identical(result$entity_count, 2)
  expect_identical(result$has_solvent, TRUE)
  definitions <- attr(result, "definitions")
  expect_identical(definitions$id, sort(definitions$id, method = "radix"))
  expect_setequal(
    graft_definitions(store)$name[
      graft_definitions(store)$id %in% definitions$id
    ],
    c("entity_count", "has_solvent", "solvent_filter")
  )
})

test_that("new definitions may compose accepted sibling definitions", {
  store <- local_definition_store()
  plan <- graft_plan(
    store,
    list(
      GraftDefinition = data.frame(
        name = "all_solvent",
        target = "Entity",
        expr = "ALL(solvent_filter)"
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "all-solvent-v1")
  )

  expect_identical(nrow(plan@issues), 0L)
  graft_commit(store, plan)
  result <- graft_calculate(store, metrics = "all_solvent")
  expect_identical(result$all_solvent, FALSE)
  definitions <- graft_definitions(store)
  names <- definitions$name[
    definitions$id %in% attr(result, "definitions")$id
  ]
  expect_setequal(names, c("all_solvent", "solvent_filter"))
})

test_that("graft_calculate() over a pinned view ignores later commits", {
  store <- local_definition_store()
  snapshot <- graft_snapshot(store)
  view <- graft_at(store, snapshot)

  graft_ingest(
    store,
    list(
      Entity = data.frame(
        id = test_graft_id("definition-entity-d"),
        label = "acid",
        preferred_name = "Formic acid"
      )
    ),
    graft_provenance(producer = "fixture", idempotency_key = "entities-v2")
  )

  expect_identical(
    graft_calculate(store, metrics = "entity_count")$entity_count,
    4
  )
  expect_identical(
    graft_calculate(view, metrics = "entity_count")$entity_count,
    3
  )
})

test_that("graft_calculate() rejects invalid requests with classed errors", {
  store <- local_definition_store()
  expect_snapshot(error = TRUE, graft_calculate(store, metrics = "nope"))
  expect_snapshot(
    error = TRUE,
    graft_calculate(
      store,
      metrics = "entity_count",
      dimensions = "nope"
    )
  )
  expect_snapshot(
    error = TRUE,
    graft_calculate(
      store,
      metrics = "entity_count",
      where = list(list(column = "label", op = "=", value = 1))
    )
  )
})

test_that("graft_calculate() parses predicate values by contract type", {
  fixture <- local_retrieval_store()
  graft_ingest(
    fixture$store,
    list(
      GraftDefinition = data.frame(
        name = "evidence_count",
        target = "ClaimEvidence",
        expr = "ROW_COUNT()"
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "evidence-count")
  )

  result <- graft_calculate(
    fixture$store,
    metrics = "evidence_count",
    where = list(list(column = "page_start", op = "=", value = "4"))
  )
  expect_identical(result$evidence_count, 1)

  ambiguous <- rlang::catch_cnd(graft_calculate(
    fixture$store,
    metrics = "evidence_count",
    where = list(list(column = "page_start", op = "=", value = "4.5"))
  ))
  non_finite <- rlang::catch_cnd(graft_calculate(
    fixture$store,
    metrics = "evidence_count",
    where = list(list(column = "page_start", op = "=", value = "Inf"))
  ))
  expect_s3_class(ambiguous, "graft_calculation_error")
  expect_identical(ambiguous$rule, "calculation_where_value")
  expect_s3_class(non_finite, "graft_calculation_error")
  expect_identical(non_finite$rule, "calculation_where_value")
})

test_that("graft_calculate() validates timestamps and enums before execution", {
  fixture <- local_retrieval_store()
  graft_ingest(
    fixture$store,
    list(
      GraftDefinition = data.frame(
        name = "claim_count",
        target = "Claim",
        expr = "ROW_COUNT()"
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "claim-count")
  )

  valid <- graft_calculate(
    fixture$store,
    metrics = "claim_count",
    where = list(list(column = "status", op = "=", value = "active"))
  )
  invalid_timestamp <- rlang::catch_cnd(graft_calculate(
    fixture$store,
    metrics = "claim_count",
    where = list(list(
      column = "created_at",
      op = "=",
      value = "2025-02-30T12:00:00Z"
    ))
  ))
  invalid_enum <- rlang::catch_cnd(graft_calculate(
    fixture$store,
    metrics = "claim_count",
    where = list(list(column = "status", op = "=", value = "unknown"))
  ))

  expect_identical(valid$claim_count, 2)
  expect_s3_class(invalid_timestamp, "graft_calculation_error")
  expect_identical(invalid_timestamp$rule, "calculation_where_value")
  expect_s3_class(invalid_enum, "graft_calculation_error")
  expect_identical(invalid_enum$rule, "calculation_where_value")
})

test_that("predicate date and time parsing rejects normalized invalid values", {
  manifest <- list(enums = list())
  date_slot <- list(enum = NULL, duckdb_type = "DATE")
  time_slot <- list(enum = NULL, duckdb_type = "TIME")
  integer_slot <- list(enum = NULL, duckdb_type = "BIGINT")

  invalid_date <- rlang::catch_cnd(definition_where_value(
    "2025-02-30",
    date_slot,
    manifest
  ))
  invalid_time <- rlang::catch_cnd(definition_where_value(
    "25:00:00",
    time_slot,
    manifest
  ))
  exact_integer <- definition_where_value(
    "9223372036854775807",
    integer_slot,
    manifest
  )
  invalid_integer <- rlang::catch_cnd(definition_where_value(
    "9223372036854775808",
    integer_slot,
    manifest
  ))

  expect_s3_class(invalid_date, "graft_calculation_error")
  expect_identical(invalid_date$rule, "calculation_where_value")
  expect_s3_class(invalid_time, "graft_calculation_error")
  expect_identical(invalid_time$rule, "calculation_where_value")
  expect_identical(exact_integer, "9223372036854775807")
  expect_s3_class(invalid_integer, "graft_calculation_error")
  expect_identical(invalid_integer$rule, "calculation_where_value")
})

test_that("graft_calculate() fails instead of truncating grouped results", {
  store <- local_definition_store()
  limits <- graft_retrieval_limits
  limits$calculation_rows <- 1L
  local_mocked_bindings(graft_retrieval_limits = limits)

  condition <- rlang::catch_cnd(graft_calculate(
    store,
    metrics = "entity_count",
    dimensions = "label"
  ))

  expect_s3_class(condition, "graft_calculation_error")
  expect_identical(condition$rule, "calculation_row_bound")
})

test_that("graft_calculate() preserves empty-table semantics", {
  store <- local_graft_ingest_store()
  graft_ingest(
    store,
    list(
      GraftDefinition = data.frame(
        name = c("entity_count", "one"),
        target = "Entity",
        expr = c("ROW_COUNT()", "1")
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "empty-count")
  )

  total <- graft_calculate(store, metrics = c("entity_count", "one"))
  grouped <- graft_calculate(
    store,
    metrics = "entity_count",
    dimensions = "label"
  )

  expect_identical(total$entity_count, 0)
  expect_identical(total$one, 1L)
  expect_identical(nrow(grouped), 0L)
})

test_that("quoted definition names compose during evaluation", {
  store <- local_definition_store()
  plan <- graft_plan(
    store,
    list(
      GraftDefinition = data.frame(
        name = c('label"length', "total_quoted_length"),
        target = "Entity",
        expr = c("LENGTH(label)", 'SUM(`label"length`)')
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "quoted-name")
  )

  expect_identical(nrow(plan@issues), 0L)
  graft_commit(store, plan)
  result <- graft_calculate(store, metrics = "total_quoted_length")
  expect_identical(result$total_quoted_length, 18)
})

test_that("normalized public relations are valid definition targets", {
  fixture <- local_retrieval_store()
  plan <- graft_plan(
    fixture$store,
    list(
      GraftDefinition = data.frame(
        name = "about_count",
        target = "claim__about",
        expr = "ROW_COUNT()"
      )
    ),
    graft_provenance(producer = "test", idempotency_key = "about-count")
  )
  expect_identical(nrow(plan@issues), 0L)
  graft_commit(fixture$store, plan)

  definitions <- graft_definitions(fixture$store, target = "claim__about")
  result <- graft_calculate(fixture$store, metrics = "about_count")

  expect_identical(definitions$target, "claim__about")
  expect_identical(result$about_count, 3)
})
