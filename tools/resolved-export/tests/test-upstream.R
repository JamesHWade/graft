test_that("upstream fixture preserves exact bytes and resolved metadata", {
  fixture <- upstream_test_fixture(fixture_dir)
  on.exit(upstream_test_cleanup_fixture(fixture), add = TRUE)

  expect_identical(
    fixture$dictionary_sha256,
    "2b9ac2432abf8236963f6125d164aa9d1b909c24f6895dad4ab150adc26adfaa"
  )
  expect_identical(
    fixture$parquet_sha256,
    "6eaf106b9009f4d416b1622b025f4e5ec226db5f81ed039b0e2c52566ff06016"
  )
  expect_identical(
    upstream_file_sha256(fixture$parquet),
    fixture$parquet_sha256
  )
  expect_identical(
    fixture$export_sha256,
    upstream_file_sha256(fixture$export_path)
  )
  expect_identical(
    fixture$export_raw,
    readBin(
      fixture$export_path,
      what = "raw",
      n = file.info(fixture$export_path)$size
    )
  )
  expect_identical(
    rawToChar(tail(fixture$export_raw, 1L)),
    "\n"
  )
  expect_equal(fixture$sales, upstream_sales())
  expect_identical(fixture$validation$status, 0L)
  expect_identical(file.exists(fixture$validation$html), TRUE)

  definitions <- upstream_definition_map(fixture$export)
  expect_length(definitions, 5L)
  expect_identical(definitions$emea$kind, "filter")
  expect_identical(definitions$emea$type, "boolean")
  expect_identical(definitions$total$kind, "metric")
  expect_identical(definitions$doubled$kind, "derived")
  expect_identical(definitions$total_doubled$definitions, list("doubled"))
  expect_length(
    Filter(
      \(translation) !is.null(translation$notes),
      definitions$total$translations
    ),
    length(definitions$total$translations)
  )
  sql_translation <- upstream_translation(definitions$total)
  expect_identical(sql_translation$target, "SQL(duckdb)")
  expect_length(sql_translation$notes, 1L)
  expect_match(sql_translation$notes[[1L]], "128 bits")
  expect_equal(upstream_test_sql(fixture, definitions$total), 35)
  expect_equal(
    upstream_test_sql(fixture, definitions$doubled),
    c(20, 40, NA, 10)
  )
  expect_equal(
    upstream_test_sql(fixture, definitions$constant),
    c(42, 42, 42, 42)
  )
  expect_equal(fixture$export_data$tables[[1L]]$rows, 4)
  expect_identical(
    is.list(fixture$export_data$tables[[1L]]$columns[[1L]]$profile),
    TRUE
  )
})

test_that("Commons reads the exact detached Parquet rows through public methods", {
  fixture <- upstream_test_fixture(fixture_dir)
  on.exit(upstream_test_cleanup_fixture(fixture), add = TRUE)
  before <- upstream_file_sha256(fixture$parquet)
  commons <- upstream_test_commons(fixture)

  total <- commons$metrics("total")
  expect_s3_class(total, "data.frame")
  expect_equal(total$total, 35)
  expect_null(attr(total, "commons_tag"))
  dependency <- commons$metrics("total_doubled")
  constant <- commons$metrics("constant")
  filtered <- commons$metrics("total", filters = "emea")
  row <- commons$run_sql(
    "SELECT id, {{doubled}} AS doubled FROM sales ORDER BY id"
  )
  expect_equal(dependency$total_doubled, 70)
  expect_equal(constant$constant, 42)
  expect_equal(filtered$total, 15)
  expect_equal(row$doubled, c(20, 40, NA, 10))

  definitions <- upstream_definition_map(fixture$export)
  bare <- list(
    total = upstream_test_sql(fixture, definitions$total),
    doubled = upstream_test_sql(fixture, definitions$doubled),
    constant = upstream_test_sql(fixture, definitions$constant)
  )
  evidence <- upstream_write_evidence(
    fixture,
    "baseline-results.json",
    list(
      commons = list(
        total = unname(total$total),
        filter_emea_total = unname(filtered$total),
        total_doubled = unname(dependency$total_doubled),
        constant = unname(constant$constant),
        doubled_rows = unname(row$doubled)
      ),
      bare_translation = lapply(bare, unname)
    )
  )
  expect_identical(file.exists(evidence$path), TRUE)
  expect_identical(upstream_file_sha256(fixture$parquet), before)
})

test_that("validation failure remains distinct from profiling success", {
  fixture <- upstream_test_fixture(fixture_dir)
  on.exit(upstream_test_cleanup_fixture(fixture), add = TRUE)
  invalid <- upstream_fixture_invalid_values(fixture)
  validation <- upstream_validate_data(invalid)

  expect_gt(validation$status, 0L)
  expect_identical(file.exists(validation$html), TRUE)
  profile <- upstream_export(invalid$dictionary, "export-data")
  expect_length(profile$tables, 1L)

  source <- upstream_test_source(invalid)
  expect_s3_class(source, "commons_data_source")
  evidence <- upstream_write_evidence(
    fixture,
    "counterexample-invalid-values.json",
    list(
      data_validation = list(
        status = validation$status,
        report_sha256 = validation$sha256
      ),
      export_data = list(status = "succeeded", tables = length(profile$tables)),
      commons_constructor = list(
        status = "accepted",
        class = class(source)[[1L]]
      )
    )
  )
  expect_identical(file.exists(evidence$path), TRUE)
})

test_that("data-dict and Commons reject unresolved references", {
  fixture <- upstream_test_fixture(fixture_dir)
  on.exit(upstream_test_cleanup_fixture(fixture), add = TRUE)

  missing <- upstream_test_variant(
    fixture,
    "missing-reference",
    "missing_column + 1"
  )
  missing_data_dict <- upstream_test_validate_spec(missing$dictionary)
  expect_identical(missing_data_dict$ok, FALSE)
  expect_s3_class(missing_data_dict$error, "simpleError")
  expect_identical(missing_data_dict$diagnostic$code, "S20")
  expect_identical(
    missing_data_dict$diagnostic$message,
    "A definition may only reference columns/definitions from its table."
  )
  expect_match(
    missing_data_dict$diagnostic$detail,
    "column `missing_column` not found",
    fixed = TRUE
  )
  missing_commons <- upstream_capture(
    commons::data_source(
      sales = upstream_read_sales(missing$parquet),
      dictionary = missing$dictionary
    )
  )
  expect_identical(missing_commons$ok, FALSE)
  expect_s3_class(missing_commons$error, "commons_definition_invalid_error")
  expect_match(
    missing_commons$message,
    'Column "missing_column" not found.',
    fixed = TRUE
  )

  related <- upstream_test_variant(
    fixture,
    "related-reference",
    "other.revenue + 1",
    include_other = TRUE
  )
  related_data_dict <- upstream_test_validate_spec(related$dictionary)
  expect_identical(related_data_dict$ok, FALSE)
  expect_s3_class(related_data_dict$error, "simpleError")
  expect_identical(related_data_dict$diagnostic$code, "S20")
  expect_identical(
    related_data_dict$diagnostic$message,
    "A definition may only reference columns/definitions from its table."
  )
  expect_match(
    related_data_dict$diagnostic$detail,
    "column `other` not found",
    fixed = TRUE
  )
  sales <- upstream_read_sales(related$parquet)
  related_commons <- upstream_capture(
    commons::data_source(
      sales = sales,
      other = sales["revenue"],
      dictionary = related$dictionary
    )
  )
  expect_identical(related_commons$ok, FALSE)
  expect_s3_class(related_commons$error, "commons_definition_invalid_error")
  expect_match(
    related_commons$message,
    'Column "other" not found.',
    fixed = TRUE
  )
  evidence <- upstream_write_evidence(
    fixture,
    "counterexample-references.json",
    list(
      missing_reference = list(
        data_dict = list(
          status = "rejected",
          diagnostic_code = missing_data_dict$diagnostic$code,
          diagnostic_message = missing_data_dict$diagnostic$message,
          detail = missing_data_dict$diagnostic$detail
        ),
        commons = list(
          status = "rejected",
          class = missing_commons$class[[1L]],
          message = missing_commons$message
        )
      ),
      related_reference = list(
        data_dict = list(
          status = "rejected",
          diagnostic_code = related_data_dict$diagnostic$code,
          diagnostic_message = related_data_dict$diagnostic$message,
          detail = related_data_dict$diagnostic$detail
        ),
        commons = list(
          status = "rejected",
          class = related_commons$class[[1L]],
          message = related_commons$message
        )
      )
    )
  )
  expect_identical(file.exists(evidence$path), TRUE)
})

test_that("R-language definitions expose the upstream compiler boundary", {
  fixture <- upstream_test_fixture(fixture_dir)
  on.exit(upstream_test_cleanup_fixture(fixture), add = TRUE)
  variant <- upstream_test_variant(
    fixture,
    "r-language",
    "!is.na(revenue)",
    language = "r"
  )

  data_dict <- upstream_test_validate_spec(variant$dictionary)
  expect_identical(data_dict$ok, TRUE)
  commons <- upstream_capture(
    commons::data_source(
      sales = upstream_read_sales(variant$parquet),
      dictionary = variant$dictionary
    )
  )
  expect_identical(commons$ok, FALSE)
  expect_s3_class(commons$error, "commons_definition_invalid_error")
  expect_match(commons$message, "Invalid definition expression")
  evidence <- upstream_write_evidence(
    fixture,
    "counterexample-r-language.json",
    list(
      data_dict = list(status = "accepted"),
      commons = list(
        status = "rejected",
        class = commons$class[[1L]],
        message = commons$message
      )
    )
  )
  expect_identical(file.exists(evidence$path), TRUE)
})

test_that("Commons refuses a mixed-grain metric dimension", {
  fixture <- upstream_test_fixture(fixture_dir)
  on.exit(upstream_test_cleanup_fixture(fixture), add = TRUE)
  variant <- upstream_test_variant(
    fixture,
    "mixed-grain",
    "SUM(revenue) + revenue",
    definitions = list(
      upstream_test_definition("total", "SUM(revenue)"),
      upstream_test_definition("probe", "SUM(revenue) + revenue")
    )
  )
  data_dict <- upstream_test_validate_spec(variant$dictionary)
  expect_identical(data_dict$ok, TRUE)
  expect_s3_class(upstream_test_source(variant), "commons_data_source")
  metrics_error <- upstream_test_commons_metrics_error(
    variant,
    metric = "total",
    dimensions = "probe"
  )
  expect_identical(metrics_error$ok, FALSE)
  expect_s3_class(metrics_error$error, "rlang_error")
  expect_match(metrics_error$message, "grain")
  evidence <- upstream_write_evidence(
    fixture,
    "counterexample-mixed-grain.json",
    list(
      data_dict = list(status = "accepted"),
      commons_constructor = list(status = "accepted"),
      commons_metrics = list(
        status = "rejected",
        class = metrics_error$class[[1L]],
        message = metrics_error$message
      )
    )
  )
  expect_identical(file.exists(evidence$path), TRUE)
})

test_that("file measures remain callable alongside dictionary definitions", {
  fixture <- upstream_test_fixture(fixture_dir)
  on.exit(upstream_test_cleanup_fixture(fixture), add = TRUE)
  measure_file <- upstream_write_measure_file(fixture$output_dir)
  layer <- commons::semantic_layer(measure_file)
  commons <- upstream_test_commons(fixture, semantic_layer = layer)

  expect_equal(commons$measure("authored_total"), 35)
  expect_equal(commons$metrics("total")$total, 35)
})
