# Test helpers for the offline upstream fixture ------------------------------

upstream_test_fixture <- function(fixture_dir, evidence_dir = NULL) {
  if (is.null(evidence_dir)) {
    caller <- parent.frame()
    if (exists("evidence_dir", envir = caller, inherits = TRUE)) {
      evidence_dir <- get("evidence_dir", envir = caller, inherits = TRUE)
    }
  }
  if (!is.null(evidence_dir)) {
    evidence_dir <- upstream_directory(evidence_dir, "evidence_dir")
    output_dir <- tempfile("resolved-export-", tmpdir = evidence_dir)
  } else {
    output_dir <- tempfile("resolved-export-")
  }
  dir.create(output_dir)
  fixture <- upstream_fixture(fixture_dir, output_dir)
  fixture$evidence_dir <- evidence_dir
  fixture$cleanup <- is.null(evidence_dir)
  fixture
}

upstream_test_cleanup_fixture <- function(fixture) {
  if (isTRUE(fixture$cleanup)) {
    unlink(fixture$output_dir, recursive = TRUE, force = TRUE)
  }
  invisible(NULL)
}

upstream_test_source <- function(fixture) {
  commons::data_source(
    sales = upstream_read_sales(fixture$parquet),
    dictionary = fixture$dictionary
  )
}

upstream_test_commons <- function(fixture, semantic_layer = NULL) {
  args <- list(data_sources = list(warehouse = upstream_test_source(fixture)))
  if (!is.null(semantic_layer)) {
    args$semantic_layer <- semantic_layer
  }
  do.call(commons::commons, args)
}

upstream_test_variant <- function(
  fixture,
  name,
  expr,
  language = NULL,
  include_other = FALSE,
  definitions = NULL
) {
  if (is.null(definitions)) {
    definitions <- list(list(name = "probe", expr = expr))
  }
  upstream_fixture_variant(
    fixture,
    name = name,
    definitions = definitions,
    include_other = include_other,
    language = language
  )
}

upstream_test_validate_spec <- function(dictionary) {
  result <- upstream_capture(datadict::dd_run(c("validate-spec", dictionary)))
  if (!isTRUE(result$ok)) {
    lines <- strsplit(result$message, "\n", fixed = TRUE)[[1L]]
    headline <- lines[grepl("^error\\[[A-Z][0-9]+\\]:", lines)][[1L]]
    detail <- lines[grepl("not found$", lines)]
    result$diagnostic <- list(
      code = sub("^error\\[([^]]+)\\].*$", "\\1", headline),
      message = sub("^error\\[[^]]+\\]:\\s*", "", headline),
      detail = if (length(detail) > 0L) detail[[1L]] else NA_character_
    )
  }
  result
}

upstream_test_definition <- function(name, expr) {
  list(name = name, expr = expr)
}

upstream_test_sql <- function(fixture, definition) {
  translation <- upstream_translation(definition)
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT ",
      translation$code,
      " AS value FROM read_parquet(",
      DBI::dbQuoteString(con, fixture$parquet),
      ")"
    )
  )$value
}

upstream_test_commons_metrics_error <- function(fixture, metric, dimensions) {
  commons <- upstream_test_commons(fixture)
  upstream_capture(commons$metrics(metric, dimensions = dimensions))
}
