test_that("kg_records is lazy and rejects non-manifest classes", {
  fixture <- local_retrieval_store()
  records <- kg_records(fixture$store, "Entity")

  expect_s3_class(records, "tbl_lazy")
  expect_s3_class(records, "tbl_sql")
  expect_identical(attr(records, "graft_record_class"), "Entity")
  expect_match(dbplyr::remote_query(records), "FROM entity")
  expect_identical(
    nrow(DBI::dbReadTable(fixture$store$connection, "entity")),
    2L
  )

  condition <- catch_graft_ingest_condition(
    kg_records(fixture$store, "_graft_identifiers")
  )
  expect_s3_class(condition, "graft_validation_error")
  expect_identical(condition$rule, "public_concrete_class")
})

test_that("identifier lookup uses declared exact normalization", {
  fixture <- local_retrieval_store()

  inchikey <- kg_lookup(
    fixture$store,
    "inchikey",
    " xlyofnoqvpjjnp-uhfffaoysa-n "
  )
  canonical <- kg_lookup(
    fixture$store,
    "canonical_url",
    "https://example.com/reports/Result?Study=ABC#different"
  )
  identifiers <- kg_identifiers(fixture$store, fixture$ids$source)

  expect_identical(inchikey$record_id, fixture$ids$entity)
  expect_identical(inchikey$class, "Entity")
  expect_true(inchikey$status %in% c("primary", "equivalent"))
  expect_identical(canonical$record_id, fixture$ids$source)
  expect_identical(
    canonical$normalized_value,
    "https://example.com/reports/Result?Study=ABC"
  )
  expect_setequal(
    identifiers$namespace,
    c("canonical_url", "content_hash", "doi")
  )
  expect_named(
    identifiers,
    c(
      "record_id",
      "class",
      "namespace",
      "value",
      "normalized_value",
      "status",
      "assigned_by",
      "confidence",
      "created_at"
    )
  )
})

test_that("kg_get hydrates exactly one record and related data", {
  fixture <- local_retrieval_store()

  result <- kg_get(fixture$store, fixture$ids$entity)

  expect_s3_class(result, "kg_record")
  expect_identical(result$class, "Entity")
  expect_identical(result$record$preferred_name, "Polyethylene")
  expect_gte(nrow(result$identifiers), 1L)
  expect_identical(nrow(result$claims), 3L)
  expect_identical(result$evidence$id, fixture$ids$evidence)
  expect_identical(
    result$store_schema_digest,
    store_schema_digest(fixture$store)
  )

  condition <- catch_graft_ingest_condition(
    kg_get(fixture$store, test_graft_id("not-found"))
  )
  expect_s3_class(condition, "graft_reference_error")
  expect_identical(condition$rule, "record_exists")
})

test_that("kg_select validates the full structured query", {
  fixture <- local_retrieval_store()

  result <- kg_select(
    fixture$store,
    "Entity",
    c("id", "preferred_name"),
    filters = list(list(
      field = "preferred_name",
      operator = "contains",
      value = "poly"
    )),
    order_by = list(list(field = "preferred_name", direction = "desc")),
    limit = 1
  )

  expect_identical(result$id, fixture$ids$entity)
  expect_identical(attr(result, "limit"), 1L)
  expect_identical(attr(result, "truncated"), FALSE)
  expect_identical(
    names(formals(kg_select)),
    c("store", "class", "fields", "filters", "order_by", "limit")
  )

  bad_field <- catch_graft_ingest_condition(
    kg_select(fixture$store, "Entity", "_graft_identifiers")
  )
  bad_operator <- catch_graft_ingest_condition(
    kg_select(
      fixture$store,
      "Entity",
      "id",
      filters = list(list(field = "id", operator = "sql", value = "x"))
    )
  )
  bad_type <- catch_graft_ingest_condition(
    kg_select(
      fixture$store,
      "Entity",
      "id",
      filters = list(list(
        field = "preferred_name",
        operator = "eq",
        value = 1
      ))
    )
  )
  bad_limit <- catch_graft_ingest_condition(
    kg_select(fixture$store, "Entity", "id", limit = 1001)
  )
  sql_member <- catch_graft_ingest_condition(
    kg_select(
      fixture$store,
      "Entity",
      "id",
      filters = list(list(
        field = "id",
        operator = "eq",
        value = fixture$ids$entity,
        sql = "OR TRUE"
      ))
    )
  )

  expect_s3_class(bad_field, "graft_validation_error")
  expect_s3_class(bad_operator, "graft_validation_error")
  expect_identical(bad_operator$rule, "supported_filter_operator")
  expect_s3_class(bad_type, "graft_validation_error")
  expect_identical(bad_type$rule, "filter_value_type")
  expect_s3_class(bad_limit, "graft_limit_error")
  expect_identical(bad_limit$hard_limit, 1000L)
  expect_s3_class(sql_member, "graft_validation_error")
  expect_identical(sql_member$rule, "filter_shape")
})

test_that("kg_unresolved returns only unresolved mention records", {
  fixture <- local_retrieval_store()

  unresolved <- kg_unresolved(
    fixture$store,
    source_id = fixture$ids$source,
    limit = 10
  )

  expect_identical(unresolved$id, fixture$ids$unresolved)
  expect_identical(unresolved$class, "EntityMention")
  expect_true(is.na(unresolved$entity_id))
})
