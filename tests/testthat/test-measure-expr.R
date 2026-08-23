test_that("definition_expr_check() accepts a simple aggregate over a known column", {
  result <- definition_expr_check("SUM(amount)", columns = "amount")
  expect_identical(result$issues, definition_expr_no_issues())
  expect_identical(result$sql, 'SUM("amount")')
})

test_that("definition_expr_check() rejects a non-whitelisted function", {
  result <- definition_expr_check("MEDIAN(amount)", columns = "amount")
  expect_identical(result$issues$rule, "definition_expr_function")
  expect_match(result$issues$message, "MEDIAN")
})

test_that("definition_expr_check() accepts the data-dict grammar", {
  columns <- c("amount", "species", "site", "observed", "eligible")
  cases <- list(
    list("ROW_COUNT()", "COUNT(*)"),
    list("COUNT_DISTINCT(species)", 'COUNT(DISTINCT "species")'),
    list("SUM(amount) / ROW_COUNT()", 'SUM("amount") / COUNT(*)'),
    list("AVG(amount * 2 + 1)", 'AVG("amount" * 2 + 1)'),
    list("MIN((amount))", 'MIN(("amount"))'),
    list(
      "SUM(CASE WHEN eligible THEN amount ELSE 0 END)",
      'SUM(CASE WHEN "eligible" THEN "amount" ELSE 0 END)'
    ),
    list(
      "species IN ('oak', 'pine') AND site IS NOT NULL",
      '"species" IN (\'oak\', \'pine\') AND "site" IS NOT NULL'
    ),
    list(
      "STARTS_WITH(LOWER(TRIM(species)), 'a')",
      'STARTS_WITH(LOWER(TRIM("species")), \'a\')'
    ),
    list(
      "observed >= NOW() - INTERVAL(2, weeks)",
      '"observed" >= CURRENT_TIMESTAMP - (2 * INTERVAL 1 WEEK)'
    ),
    list("amount BETWEEN -10 AND 10", '"amount" BETWEEN -10 AND 10'),
    list(
      "ANY(eligible) OR ALL(eligible)",
      'BOOL_OR("eligible") OR BOOL_AND("eligible")'
    )
  )
  for (case in cases) {
    result <- definition_expr_check(case[[1L]], columns = columns)
    expect_identical(
      result$issues,
      definition_expr_no_issues(),
      info = case[[1L]]
    )
    expect_identical(result$sql, case[[2L]], info = case[[1L]])
  }
})

test_that("definition_expr_check() expands data-dict column selections", {
  columns <- c("q1", "q2", "created", "amount")

  listed <- definition_expr_check(
    "COLUMNS([q1, q2]) IS NOT NULL",
    columns = columns
  )
  all_columns <- definition_expr_check(
    "COLUMNS(*) IS NOT NULL",
    columns = columns
  )
  selected <- definition_expr_check(
    "COLUMNS('^q') IS NOT NULL",
    columns = columns
  )

  expect_identical(
    listed$sql,
    '"q1" IS NOT NULL AND "q2" IS NOT NULL'
  )
  expect_match(all_columns$sql, '"amount" IS NOT NULL', fixed = TRUE)
  expect_identical(
    selected$sql,
    '"q1" IS NOT NULL AND "q2" IS NOT NULL'
  )

  compound <- definition_expr_check(
    "COLUMNS([q1, q2]) IS NULL OR created IS NOT NULL",
    columns = columns
  )
  expect_identical(
    compound$sql,
    paste0(
      '("q1" IS NULL OR "created" IS NOT NULL) AND ',
      '("q2" IS NULL OR "created" IS NOT NULL)'
    )
  )
})

test_that("definition_expr_check() rejects invalid expressions with specific rules", {
  columns <- c("amount", "species")
  cases <- list(
    list("MEDIAN(amount)", "definition_expr_function"),
    list("ROW_COUNT(amount)", "definition_expr_function"),
    list("SUM(missing)", "definition_expr_column"),
    list(
      "SUM(DISTINCT amount)",
      c("definition_expr_column", "definition_expr_parse")
    ),
    list("SUM(amount", "definition_expr_parse"),
    list("SUM(amount)) ", "definition_expr_parse"),
    list("SUM(amount) extra", "definition_expr_parse"),
    list("amount ;", "definition_expr_parse"),
    list("", "definition_expr_parse"),
    list("SELECT 1", c("definition_expr_column", "definition_expr_parse"))
  )
  for (case in cases) {
    result <- definition_expr_check(case[[1L]], columns = columns)
    expect_identical(unique(result$issues$rule), case[[2L]], info = case[[1L]])
    expect_identical(result$sql, NA_character_, info = case[[1L]])
  }
})
