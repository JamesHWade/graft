test_that("measure_expr_check() accepts a simple aggregate over a known column", {
  result <- measure_expr_check("SUM(amount)", columns = "amount")
  expect_identical(result$issues, measure_expr_no_issues())
  expect_identical(result$sql, 'SUM("amount")')
})

test_that("measure_expr_check() rejects a non-whitelisted function", {
  result <- measure_expr_check("MEDIAN(amount)", columns = "amount")
  expect_identical(result$issues$rule, "measure_expr_function")
  expect_match(result$issues$message, "MEDIAN")
})

test_that("measure_expr_check() accepts the supported grammar", {
  columns <- c("amount", "species", "site")
  cases <- list(
    list("COUNT(*)", 'COUNT(*)'),
    list("count(distinct species)", 'COUNT(DISTINCT "species")'),
    list("SUM(amount) / COUNT(*)", 'SUM("amount") / COUNT(*)'),
    list("AVG(amount * 2 + 1)", 'AVG("amount" * 2 + 1)'),
    list("MIN((amount))", 'MIN(("amount"))'),
    list(
      "SUM(amount) > 10 AND COUNT(*) < 5",
      'SUM("amount") > 10 AND COUNT(*) < 5'
    ),
    list("COUNT(*) = 0 OR NOT TRUE", 'COUNT(*) = 0 OR NOT TRUE'),
    list("MAX(site != 'ridge')", "MAX(\"site\" != 'ridge')"),
    list("SUM(-amount)", 'SUM(-"amount")')
  )
  for (case in cases) {
    result <- measure_expr_check(case[[1L]], columns = columns)
    expect_identical(result$issues, measure_expr_no_issues(), info = case[[1L]])
    expect_identical(result$sql, case[[2L]], info = case[[1L]])
  }
})

test_that("measure_expr_check() rejects invalid expressions with specific rules", {
  columns <- c("amount", "species")
  cases <- list(
    list("LOWER(species)", "measure_expr_function"),
    list("SUM(missing)", "measure_expr_column"),
    list("SUM(DISTINCT amount)", "measure_expr_distinct"),
    list("SUM(amount", "measure_expr_parse"),
    list("SUM(amount)) ", "measure_expr_parse"),
    list("SUM(amount) extra", "measure_expr_parse"),
    list("amount ;", "measure_expr_parse"),
    list("", "measure_expr_parse"),
    list("SELECT 1", c("measure_expr_column", "measure_expr_parse"))
  )
  for (case in cases) {
    result <- measure_expr_check(case[[1L]], columns = columns)
    expect_identical(unique(result$issues$rule), case[[2L]], info = case[[1L]])
    expect_identical(result$sql, NA_character_, info = case[[1L]])
  }
})
