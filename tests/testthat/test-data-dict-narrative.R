test_that("the real producer exports narrative contracts and rejects invented extensions", {
  cli <- Sys.getenv("GRAFT_TEST_DATA_DICT_CLI")
  skip_if(!nzchar(cli), "Set GRAFT_TEST_DATA_DICT_CLI for producer checks")
  withr::local_options(graft.data_dict_cli = cli)
  path <- system.file(
    "extdata/narrative-knowledge.data-dict.yaml",
    package = "graft"
  )
  export <- system.file(
    if (
      identical(data_dict_system2(cli, "--version")$stdout, "data-dict 0.0.3")
    ) {
      "extdata/narrative-knowledge.data-dict-0.0.3.json"
    } else {
      "extdata/narrative-knowledge.data-dict.json"
    },
    package = "graft"
  )
  expect_equal(
    read_data_dict_contract(path)$document,
    read_data_dict_contract(export)$document
  )
  document <- narrative_dictionary_yaml()
  directory <- withr::local_tempdir()
  variant <- file.path(directory, "data-dict.yaml")
  document$graft <- list(authority = "model-written")
  yaml::write_yaml(document, variant)
  result <- data_dict_system2(cli, c("validate-spec", shQuote(variant)))
  expect_gt(result$status, 0L)
  expect_match(
    paste(result$stderr, result$stdout, collapse = "\n"),
    "Unknown property|unknown",
    ignore.case = TRUE
  )
})

test_that("upstream nested representations are distinct from the adapter profile", {
  cli <- Sys.getenv("GRAFT_TEST_DATA_DICT_CLI")
  skip_if(!nzchar(cli), "Set GRAFT_TEST_DATA_DICT_CLI for producer checks")
  withr::local_options(graft.data_dict_cli = cli)
  original <- narrative_dictionary_yaml()
  path <- withr::local_tempfile(fileext = ".yaml")
  for (column in list(
    list(
      name = "nested",
      type = "struct",
      fields = list(list(
        name = "text",
        type = "string",
        examples = list("synthetic")
      ))
    ),
    list(
      name = "nested",
      type = "list(list(string))",
      examples = list("synthetic")
    )
  )) {
    document <- original
    document$tables[[1]]$columns <- c(
      document$tables[[1]]$columns,
      list(column)
    )
    yaml::write_yaml(document, path)
    resolved <- read_data_dict_contract(path)
    expect_identical(
      tail(resolved$document$tables[[1]]$columns, 1)[[1]]$type,
      column$type
    )
    expect_snapshot(
      error = TRUE,
      graft_schema(path),
      transform = function(lines) {
        gsub(path, "<dictionary>", lines, fixed = TRUE)
      }
    )
  }
})

test_that("producer assertion enforcement is versioned separately from Graft policy", {
  cli <- Sys.getenv("GRAFT_TEST_DATA_DICT_CLI")
  skip_if(!nzchar(cli), "Set GRAFT_TEST_DATA_DICT_CLI for producer checks")
  directory <- withr::local_tempdir()
  records <- narrative_fixture()$narrative_records()
  records$knowledge$body[[1]] <- "short"
  document <- narrative_dictionary_yaml()
  document$tables[[1]]$columns <- Filter(
    function(column) column$name != "tags",
    document$tables[[1]]$columns
  )
  connection <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(connection, shutdown = TRUE))
  for (i in seq_along(document$tables)) {
    table <- document$tables[[i]]$name
    parquet <- file.path(directory, paste0(table, ".parquet"))
    data <- records[[table]]
    if (table == "knowledge") {
      data$tags <- NULL
    }
    DBI::dbWriteTable(connection, table, data)
    DBI::dbExecute(
      connection,
      paste(
        "COPY",
        DBI::dbQuoteIdentifier(connection, table),
        "TO",
        DBI::dbQuoteString(connection, parquet),
        "(FORMAT PARQUET)"
      )
    )
    document$tables[[i]]$source <- list(parquet = parquet)
  }
  path <- file.path(directory, "data-dict.yaml")
  yaml::write_yaml(document, path)
  result <- data_dict_system2(cli, c("validate-data", shQuote(path), "--json"))
  version <- data_dict_system2(cli, "--version")$stdout
  if (identical(version, "data-dict 0.0.1")) {
    expect_identical(result$status, 0L)
  } else {
    expect_gt(result$status, 0L)
    expect_match(paste(result$stdout, collapse = "\n"), "D07")
  }
  store <- local_narrative_store()
  plan <- graft_plan(
    store,
    records,
    graft_provenance("host", idempotency_key = "assertion-probe")
  )
  expect_identical(plan@valid, TRUE)
})
