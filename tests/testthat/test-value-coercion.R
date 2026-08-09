test_that("exact numeric coercion respects DuckDB storage bounds", {
  expect_identical(coerce_exact_numeric(c(-0, 0), integer = TRUE), c("0", "0"))
  expect_identical(
    coerce_exact_numeric(c(-0, 0), integer = FALSE),
    c("0", "0")
  )
  expect_identical(
    coerce_exact_numeric(
      c(
        "9223372036854775807",
        "-9223372036854775808",
        "+00042"
      ),
      integer = TRUE
    ),
    c("9223372036854775807", "-9223372036854775808", "42")
  )
  expect_null(coerce_exact_numeric(
    c("9223372036854775808", "-9223372036854775809"),
    integer = TRUE
  ))

  expect_identical(
    coerce_exact_numeric(
      c(
        "999999999999999.999",
        "-999999999999999.999",
        "0001.2300"
      ),
      integer = FALSE
    ),
    c("999999999999999.999", "-999999999999999.999", "1.23")
  )
  expect_null(coerce_exact_numeric("1000000000000000", integer = FALSE))
  expect_null(coerce_exact_numeric("0.0001", integer = FALSE))
})

test_that("malformed generic timestamps become validation failures", {
  expect_null(coerce_timestamp("not-a-date"))
  expect_null(coerce_timestamp(c("2024-01-01", "not-a-date")))
  expect_null(coerce_timestamp("2024-01-01T00:00:00Zjunk"))
  expect_null(coerce_timestamp("2024-01-01 00:00:00junk"))
  expect_null(coerce_timestamp("2024-01-01junk"))
  expect_null(coerce_timestamp("2024-02-31"))
  expect_null(coerce_timestamp("2024-01-01T00:00:00.1234567"))
})

test_that("generic timestamps accept only complete supported forms", {
  values <- c(
    "2024-01-01",
    "2024-01-01 00:00:00.123456",
    "2024-01-01T00:00:00.123456",
    "2024-01-01T00:00:00.123456Z",
    "2024-01-01T00:00:00-05:00"
  )

  expect_s3_class(coerce_timestamp(values), "POSIXct")
})

test_that("LinkML URI ranges reject invalid references", {
  valid <- c(
    "https://example.org/a?b=c#d",
    "schema:Thing",
    "http://[::1]/",
    "http://[2001:db8::1]/resource",
    "http://[v1.fe80]/"
  )
  expect_identical(
    coerce_linkml_reference(valid),
    valid
  )
  expect_identical(
    coerce_linkml_reference("_local:Thing", "uriorcurie"),
    "_local:Thing"
  )
  expect_null(coerce_linkml_reference("_local:Thing", "uri"))

  invalid <- c(
    "not a uri",
    "relative",
    "relative/path",
    "#fragment",
    "?query",
    "//host/path",
    "https://example.org/%ZZ",
    "[",
    "]",
    "http://[",
    "http://[:::1]/",
    "http://[gggg::1]/",
    "http://[192.168.1.1]/",
    ":",
    "::",
    "a#b#c",
    "abc\n",
    "abc\r\n"
  )
  for (value in invalid) {
    expect_null(coerce_linkml_reference(value, "uriorcurie"))
  }

  store <- local_graft_ingest_store()
  plan <- graft_plan(
    store,
    list(
      Source = data.frame(
        id = test_graft_id("invalid-uri"),
        uri = "relative/path"
      )
    ),
    graft_provenance("uri-validation")
  )

  expect_identical(plan@valid, FALSE)
  expect_in("type_uri", plan@issues$rule)
})

test_that("planning rejects exact numbers DuckDB cannot preserve", {
  schema <- modified_ingest_schema(
    as_graft_schema_internal(graft_schema(tempest_manifest_path()))
  )
  schema$manifest$classes$Run$slots$run_identifier$range <- "integer"
  schema$manifest$classes$Run$slots$run_identifier$duckdb_type <- "BIGINT"
  schema$manifest$slots$run_identifier$range <- "integer"
  schema$manifest$slots$run_identifier$duckdb_type <- "BIGINT"
  schema$manifest$classes$Run$slots$name$range <- "decimal"
  schema$manifest$classes$Run$slots$name$duckdb_type <- "DECIMAL"
  schema$manifest$slots$name$range <- "decimal"
  schema$manifest$slots$name$duckdb_type <- "DECIMAL"
  schema <- refresh_schema_structural_digest(schema)
  store <- local_graft_ingest_store(schema = new_graft_schema(schema))

  plan <- graft_plan(
    store,
    list(
      Run = data.frame(
        run_identifier = c(
          "9223372036854775808",
          "-9223372036854775809"
        ),
        name = c("1000000000000000", "0.0001")
      )
    ),
    graft_provenance(
      "numeric-boundary",
      idempotency_key = "numeric-boundary-invalid"
    )
  )

  expect_identical(plan@valid, FALSE)
  expect_equal(sum(plan@issues$rule == "type_bigint"), 2L)
  expect_equal(sum(plan@issues$rule == "type_decimal"), 2L)

  valid <- graft_plan(
    store,
    list(
      Run = data.frame(
        run_identifier = "-9223372036854775808",
        name = "-999999999999999.999"
      )
    ),
    graft_provenance(
      "numeric-boundary",
      idempotency_key = "numeric-boundary-valid"
    )
  )
  expect_identical(valid@valid, TRUE)
  graft_commit(store, valid)
  valid_id <- valid@changes$record_id[[1L]]
  record <- graft_get(store, valid_id, include = character())$record
  expect_identical(record$run_identifier, "-9223372036854775808")
  expect_identical(record$name, "-999999999999999.999")
})
