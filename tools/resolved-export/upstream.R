# Helpers for the offline upstream resolved-export fixture ------------------

upstream_required_packages <- function() {
  c(
    "DBI",
    "commons",
    "datadict",
    "digest",
    "duckdb",
    "jsonlite",
    "yaml"
  )
}

upstream_require_packages <- function() {
  required <- upstream_required_packages()
  missing <- required[
    !vapply(required, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing) > 0L) {
    stop(
      "The resolved-export fixture requires installed packages: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

upstream_path <- function(path, label, must_work = FALSE) {
  if (
    !is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)
  ) {
    stop(label, " must be one non-empty path.", call. = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = must_work)
}

upstream_directory <- function(path, label) {
  path <- upstream_path(path, label, must_work = TRUE)
  if (!dir.exists(path)) {
    stop(label, " must be a directory.", call. = FALSE)
  }
  path
}

upstream_file_sha256 <- function(path) {
  digest::digest(
    file = upstream_path(path, "path", must_work = TRUE),
    algo = "sha256"
  )
}

upstream_copy_bytes <- function(source, destination) {
  source <- upstream_path(source, "source", must_work = TRUE)
  destination <- upstream_path(destination, "destination")
  if (file.exists(destination) || dir.exists(destination)) {
    stop("Destination already exists: ", destination, call. = FALSE)
  }
  bytes <- readBin(source, what = "raw", n = file.info(source)$size)
  writeBin(bytes, destination)
  if (
    !identical(upstream_file_sha256(source), upstream_file_sha256(destination))
  ) {
    stop("Copied bytes do not match the source.", call. = FALSE)
  }
  destination
}

upstream_sales <- function() {
  data.frame(
    id = 1:4,
    revenue = c(10, 20, NA, 5),
    region = c("EMEA", "APAC", "EMEA", "EMEA"),
    stringsAsFactors = FALSE
  )
}

upstream_write_sales_parquet <- function(con, parquet) {
  parquet <- upstream_path(parquet, "parquet")
  if (file.exists(parquet) || dir.exists(parquet)) {
    stop("Parquet destination already exists: ", parquet, call. = FALSE)
  }
  staging <- tempfile("sales-", tmpdir = dirname(parquet), fileext = ".parquet")
  on.exit(unlink(staging), add = TRUE)
  DBI::dbExecute(
    con,
    paste0(
      "COPY sales TO ",
      DBI::dbQuoteString(con, staging),
      " (FORMAT PARQUET, COMPRESSION UNCOMPRESSED, ",
      "OVERWRITE_OR_IGNORE TRUE)"
    )
  )
  if (!file.rename(staging, parquet)) {
    stop("Could not publish the immutable Parquet file.", call. = FALSE)
  }
  upstream_path(parquet, "parquet", must_work = TRUE)
}

upstream_fixture_prepare <- function(fixture_dir, output_dir) {
  upstream_require_packages()
  fixture_dir <- upstream_directory(fixture_dir, "fixture_dir")
  output_dir <- upstream_directory(output_dir, "output_dir")
  source_dictionary <- file.path(fixture_dir, "fixtures", "data-dict.yaml")
  if (!file.exists(source_dictionary)) {
    stop("Missing resolved-export dictionary fixture.", call. = FALSE)
  }
  dictionary <- file.path(output_dir, "data-dict.yaml")
  parquet <- file.path(output_dir, "sales.parquet")
  upstream_copy_bytes(source_dictionary, dictionary)

  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "sales", upstream_sales())
  upstream_write_sales_parquet(con, parquet)

  list(
    output_dir = output_dir,
    dictionary = upstream_path(dictionary, "dictionary", must_work = TRUE),
    parquet = parquet,
    dictionary_sha256 = upstream_file_sha256(dictionary),
    parquet_sha256 = upstream_file_sha256(parquet)
  )
}

upstream_read_sales <- function(parquet) {
  upstream_require_packages()
  parquet <- upstream_path(parquet, "parquet", must_work = TRUE)
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbGetQuery(
    con,
    paste0(
      "SELECT * FROM read_parquet(",
      DBI::dbQuoteString(con, parquet),
      ") ORDER BY id"
    )
  )
}

upstream_write_export_raw <- function(raw, path) {
  path <- upstream_path(path, "raw export")
  if (file.exists(path) || dir.exists(path)) {
    existing <- readBin(path, what = "raw", n = file.info(path)$size)
    if (identical(existing, raw)) {
      return(upstream_path(path, "raw export", must_work = TRUE))
    }
    stop(
      "Raw export destination already contains different bytes.",
      call. = FALSE
    )
  }
  writeBin(raw, path)
  upstream_path(path, "raw export", must_work = TRUE)
}

upstream_export <- function(
  dictionary,
  command = "export-spec",
  raw_path = NULL
) {
  upstream_require_packages()
  dictionary <- upstream_path(dictionary, "dictionary", must_work = TRUE)
  if (!command %in% c("export-spec", "export-data")) {
    stop("command must be export-spec or export-data.", call. = FALSE)
  }
  run <- datadict::dd_run(c(command, dictionary))
  json <- run$output[grepl("^\\s*\\{", run$output)]
  if (length(json) != 1L) {
    stop("Expected one JSON document from data-dict.", call. = FALSE)
  }
  if (is.null(raw_path)) {
    raw_path <- file.path(dirname(dictionary), paste0(command, ".json"))
  }
  # dd_run() captures output without line separators; retain the JSON document
  # as UTF-8 bytes with one LF so the evidence has a stated convention.
  raw <- charToRaw(paste0(json, "\n"))
  raw_path <- upstream_write_export_raw(raw, raw_path)
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  attr(parsed, "raw_path") <- raw_path
  attr(parsed, "raw_sha256") <- upstream_file_sha256(raw_path)
  attr(parsed, "raw_bytes") <- raw
  parsed
}

upstream_validate_data <- function(fixture, html = NULL) {
  upstream_require_packages()
  if (!is.list(fixture) || is.null(fixture$dictionary)) {
    stop("fixture must contain a dictionary path.", call. = FALSE)
  }
  if (is.null(html)) {
    html <- file.path(fixture$output_dir, "validation.html")
  }
  html <- upstream_path(html, "html")
  result <- datadict::dd_validate_data(
    fixture$dictionary,
    html = html,
    browse = FALSE
  )
  list(
    html = upstream_path(result$html, "validation report", must_work = TRUE),
    status = as.integer(result$status),
    sha256 = upstream_file_sha256(result$html)
  )
}

upstream_fixture <- function(fixture_dir, output_dir) {
  fixture <- upstream_fixture_prepare(fixture_dir, output_dir)
  fixture$validation <- upstream_validate_data(fixture)
  fixture$export <- upstream_export(fixture$dictionary)
  fixture$export_data <- upstream_export(fixture$dictionary, "export-data")
  fixture$export_path <- attr(fixture$export, "raw_path")
  fixture$export_sha256 <- attr(fixture$export, "raw_sha256")
  fixture$export_raw <- attr(fixture$export, "raw_bytes")
  fixture$export_data_path <- attr(fixture$export_data, "raw_path")
  fixture$export_data_sha256 <- attr(fixture$export_data, "raw_sha256")
  fixture$export_data_raw <- attr(fixture$export_data, "raw_bytes")
  fixture$sales <- upstream_read_sales(fixture$parquet)
  fixture
}

upstream_definition_map <- function(export) {
  definitions <- export$tables[[1L]]$definitions
  if (!is.list(definitions) || length(definitions) == 0L) {
    stop("The export did not contain table definitions.", call. = FALSE)
  }
  names <- vapply(definitions, `[[`, character(1), "name")
  if (anyNA(names) || anyDuplicated(names)) {
    stop("The export definitions must have unique names.", call. = FALSE)
  }
  setNames(definitions, names)
}

upstream_translation <- function(definition, target = "SQL(duckdb)") {
  translations <- definition$translations
  if (!is.list(translations)) {
    stop("The exported definition has no translations.", call. = FALSE)
  }
  matches <- Filter(
    \(translation) identical(translation$target, target),
    translations
  )
  if (length(matches) != 1L) {
    stop("Expected one translation for ", target, ".", call. = FALSE)
  }
  matches[[1L]]
}

upstream_fixture_variant <- function(
  fixture,
  name,
  definitions,
  include_other = FALSE,
  language = NULL
) {
  upstream_require_packages()
  if (
    !is.list(fixture) || is.null(fixture$output_dir) || is.null(fixture$parquet)
  ) {
    stop("fixture must contain output_dir and parquet paths.", call. = FALSE)
  }
  if (
    !is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)
  ) {
    stop("name must be one non-empty string.", call. = FALSE)
  }
  if (!is.list(definitions) || length(definitions) == 0L) {
    stop("definitions must be a non-empty list.", call. = FALSE)
  }
  output_dir <- file.path(fixture$output_dir, name)
  if (!dir.create(output_dir, recursive = FALSE, showWarnings = FALSE)) {
    stop("Could not create variant directory: ", output_dir, call. = FALSE)
  }
  dictionary <- file.path(output_dir, "data-dict.yaml")
  parquet <- file.path(output_dir, "sales.parquet")
  upstream_copy_bytes(fixture$parquet, parquet)
  dictionary_model <- yaml::read_yaml(fixture$dictionary)
  dictionary_model$tables[[1L]]$columns[[1L]]$constraints <- list(
    "primary_key"
  )
  dictionary_model$tables[[1L]]$columns[[3L]]$values <- as.list(
    dictionary_model$tables[[1L]]$columns[[3L]]$values
  )
  dictionary_model$tables[[1L]]$definitions <- definitions
  if (!is.null(language)) {
    dictionary_model$tables[[1L]]$definitions[[1L]]$language <- language
  }
  if (isTRUE(include_other)) {
    dictionary_model$tables[[2L]] <- list(
      name = "other",
      columns = list(list(
        name = "revenue",
        type = "number(quantity)",
        range = list(0, 100)
      ))
    )
  }
  yaml::write_yaml(dictionary_model, dictionary)
  list(
    output_dir = upstream_path(output_dir, "variant output", must_work = TRUE),
    dictionary = upstream_path(
      dictionary,
      "variant dictionary",
      must_work = TRUE
    ),
    parquet = upstream_path(parquet, "variant parquet", must_work = TRUE),
    dictionary_sha256 = upstream_file_sha256(dictionary),
    parquet_sha256 = upstream_file_sha256(parquet)
  )
}

upstream_fixture_invalid_values <- function(fixture) {
  upstream_require_packages()
  if (
    !is.list(fixture) || is.null(fixture$output_dir) || is.null(fixture$parquet)
  ) {
    stop("fixture must contain output_dir and parquet paths.", call. = FALSE)
  }
  variant <- file.path(fixture$output_dir, "invalid-values")
  if (!dir.create(variant, recursive = FALSE, showWarnings = FALSE)) {
    stop("Could not create invalid-values directory.", call. = FALSE)
  }
  dictionary <- file.path(variant, "data-dict.yaml")
  parquet <- file.path(variant, "sales.parquet")
  upstream_copy_bytes(fixture$dictionary, dictionary)
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(
    con,
    paste0(
      "CREATE TABLE sales AS SELECT * FROM read_parquet(",
      DBI::dbQuoteString(con, fixture$parquet),
      ")"
    )
  )
  DBI::dbExecute(
    con,
    "UPDATE sales SET revenue = -1, region = 'UNKNOWN' WHERE id = 1"
  )
  upstream_write_sales_parquet(con, parquet)
  list(
    output_dir = upstream_path(variant, "invalid output", must_work = TRUE),
    dictionary = upstream_path(
      dictionary,
      "invalid dictionary",
      must_work = TRUE
    ),
    parquet = upstream_path(parquet, "invalid parquet", must_work = TRUE),
    dictionary_sha256 = upstream_file_sha256(dictionary),
    parquet_sha256 = upstream_file_sha256(parquet)
  )
}

upstream_write_measure_file <- function(output_dir) {
  output_dir <- upstream_directory(output_dir, "measure output_dir")
  path <- file.path(output_dir, "authored-measure.R")
  if (file.exists(path) || dir.exists(path)) {
    stop("Measure destination already exists: ", path, call. = FALSE)
  }
  writeLines(
    c(
      "#' Authored revenue total",
      "#'",
      "#' @return The total revenue from the warehouse.",
      "#' @measure",
      "authored_total <- function(warehouse) {",
      "  DBI::dbGetQuery(",
      "    warehouse,",
      "    \"SELECT SUM(revenue) AS value FROM sales\"",
      "  )$value[[1L]]",
      "}"
    ),
    path,
    useBytes = TRUE
  )
  upstream_path(path, "measure file", must_work = TRUE)
}

upstream_capture <- function(expr) {
  tryCatch(
    list(ok = TRUE, value = force(expr)),
    error = function(error) {
      list(
        ok = FALSE,
        value = NULL,
        error = error,
        message = conditionMessage(error),
        class = class(error)
      )
    }
  )
}

upstream_write_evidence <- function(fixture, name, value) {
  if (!is.list(fixture) || is.null(fixture$output_dir)) {
    stop("fixture must contain an output directory.", call. = FALSE)
  }
  if (
    !is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)
  ) {
    stop("name must be one non-empty string.", call. = FALSE)
  }
  directory <- fixture$evidence_dir
  if (is.null(directory)) {
    directory <- fixture$output_dir
  }
  directory <- upstream_directory(directory, "evidence directory")
  path <- file.path(directory, name)
  if (file.exists(path) || dir.exists(path)) {
    stop("Evidence destination already exists: ", path, call. = FALSE)
  }
  jsonlite::write_json(
    value,
    path,
    auto_unbox = TRUE,
    pretty = TRUE,
    na = "null"
  )
  list(
    path = upstream_path(path, "evidence", must_work = TRUE),
    sha256 = upstream_file_sha256(path)
  )
}
