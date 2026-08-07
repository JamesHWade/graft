test_that("data-dict documents are detected without false JSON positives", {
  directory <- withr::local_tempdir()
  yaml_path <- file.path(directory, "custom.yaml")
  json_path <- file.path(directory, "resolved.json")
  generic_json <- file.path(directory, "generic.json")
  linkml_path <- file.path(directory, "schema.yaml")
  canonical_path <- file.path(directory, "data-dict.yml")
  writeLines(c("$version: 0.1.0", "tables: []"), yaml_path)
  writeLines('{"$version":"0.1.0","tables":[]}', json_path)
  writeLines('{"name":"not-a-data-dict"}', generic_json)
  writeLines(c("name: example", "classes: {}"), linkml_path)
  writeLines("[", canonical_path)

  expect_identical(is_data_dict_document(yaml_path), TRUE)
  expect_identical(is_data_dict_document(json_path), TRUE)
  expect_identical(is_data_dict_document(generic_json), FALSE)
  expect_identical(is_data_dict_document(linkml_path), FALSE)
  expect_identical(is_data_dict_document(canonical_path), TRUE)
})

test_that("data-dict YAML never inherits ambient expression evaluation", {
  marker <- ".graft_yaml_eval_marker"
  if (exists(marker, envir = .GlobalEnv, inherits = FALSE)) {
    rm(list = marker, envir = .GlobalEnv)
  }
  withr::defer({
    if (exists(marker, envir = .GlobalEnv, inherits = FALSE)) {
      rm(list = marker, envir = .GlobalEnv)
    }
  })
  withr::local_options(yaml.eval.expr = TRUE)
  text <- paste(
    "$version: 0.1.0",
    "name: safe-yaml",
    "tables: []",
    paste0(
      'marker: !expr assign("',
      marker,
      '", TRUE, envir = .GlobalEnv)'
    ),
    sep = "\n"
  )
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(text, path)

  expect_identical(is_data_dict_document(path), TRUE)
  expect_type(validate_data_dict_graft_yaml(text, path), "list")
  expect_identical(exists(marker, envir = .GlobalEnv, inherits = FALSE), FALSE)
})

test_that("data-dict CLI lookup respects option, environment, and PATH", {
  seen <- character()
  withr::local_options(graft.data_dict_cli = "option-data-dict")
  withr::local_envvar(GRAFT_DATA_DICT_CLI = "env-data-dict")
  local_mocked_bindings(
    data_dict_path_lookup = function(command) {
      seen <<- c(seen, command)
      paste0("/resolved/", command)
    }
  )

  option_path <- locate_data_dict_cli()
  options(graft.data_dict_cli = NULL)
  environment_path <- locate_data_dict_cli()
  Sys.unsetenv("GRAFT_DATA_DICT_CLI")
  path_path <- locate_data_dict_cli()

  expect_identical(option_path, "/resolved/option-data-dict")
  expect_identical(environment_path, "/resolved/env-data-dict")
  expect_identical(path_path, "/resolved/data-dict")
  expect_identical(
    seen,
    c("option-data-dict", "env-data-dict", "data-dict")
  )
})

test_that("a missing data-dict CLI is a schema error", {
  withr::local_options(graft.data_dict_cli = NULL)
  withr::local_envvar(GRAFT_DATA_DICT_CLI = NA)
  local_mocked_bindings(data_dict_path_lookup = \(command) "")

  condition <- rlang::catch_cnd(locate_data_dict_cli())

  expect_s3_class(condition, "graft_schema_error")
  expect_match(conditionMessage(condition), "Could not find the data-dict CLI")
})

test_that("YAML is exported with pinned provider metadata", {
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(c("$version: 0.1.0", "tables: []"), path)
  source_digest <- data_dict_source_snapshot(path)$digest
  calls <- list()
  digest_calls <- 0L
  withr::local_options(
    graft.data_dict_cli = "configured-data-dict",
    graft.data_dict_revision = "d794c96"
  )
  local_mocked_bindings(
    data_dict_path_lookup = \(command) "/mock/data-dict",
    data_dict_file_digest = function(path) {
      digest_calls <<- digest_calls + 1L
      graft_sha256("mock-data-dict")
    },
    data_dict_system2 = function(command, args) {
      calls[[length(calls) + 1L]] <<- list(command = command, args = args)
      if (identical(args, "--version")) {
        return(list(
          status = 0L,
          stdout = "data-dict 0.0.1",
          stderr = character()
        ))
      }
      list(
        status = 0L,
        stdout = '{"$version":"0.2.0","tables":[]}',
        stderr = "S09 warning"
      )
    }
  )

  contract <- NULL
  expect_warning(
    contract <- read_data_dict_contract(path),
    "S09 warning",
    class = "graft_data_dict_warning"
  )

  expect_identical(contract$document[["$version"]], "0.2.0")
  expect_identical(contract$document$tables, list())
  expect_identical(contract$provider$name, "data-dict")
  expect_identical(contract$provider$export_format_version, "0.2.0")
  expect_identical(contract$provider$source_spec_version, "0.1.0")
  expect_identical(contract$provider$cli_version, "0.0.1")
  expect_identical(
    contract$provider$cli_digest,
    graft_sha256("mock-data-dict")
  )
  expect_identical(contract$provider$revision, "d794c96")
  expect_identical(contract$provider$source_format, "yaml")
  expect_identical(contract$source_digest, source_digest)
  expect_identical(
    contract$provider$source_path,
    normalizePath(path, winslash = "/")
  )
  expect_identical(calls[[1L]]$command, "/mock/data-dict")
  expect_identical(calls[[1L]]$args[[1L]], "export-spec")
  expect_match(calls[[1L]]$args[[2L]], basename(path), fixed = TRUE)
  expect_identical(calls[[2L]]$args, "--version")
  expect_identical(digest_calls, 3L)
})

test_that("resolved JSON is read without invoking the CLI", {
  path <- withr::local_tempfile(fileext = ".json")
  writeLines(
    paste0(
      '{"$version":"0.1.0","name":"people","tables":',
      '[{"name":"person","columns":[]}]}'
    ),
    path
  )
  withr::local_options(graft.data_dict_revision = NULL)
  withr::local_envvar(GRAFT_DATA_DICT_REVISION = "release-candidate")
  local_mocked_bindings(
    data_dict_system2 = \(...) stop("The CLI should not run.")
  )

  contract <- read_data_dict_contract(path)

  expect_identical(contract$document$name, "people")
  expect_identical(contract$document$tables[[1L]]$name, "person")
  expect_identical(contract$provider$export_format_version, "0.1.0")
  expect_null(contract$provider$source_spec_version)
  expect_null(contract$provider$cli_version)
  expect_null(contract$provider$cli_digest)
  expect_identical(contract$provider$revision, "release-candidate")
  expect_identical(contract$provider$source_format, "resolved_json")
  expect_identical(
    contract$source_digest,
    data_dict_source_snapshot(path)$digest
  )
})

test_that("resolved data-dict JSON rejects duplicate object keys", {
  text <- paste0(
    '{"$version":"0.1.0","$version":"0.1.0",',
    '"name":"duplicate","tables":[]}'
  )

  condition <- rlang::catch_cnd(
    read_resolved_data_dict_json(text, "duplicate.json")
  )

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "duplicate_json_key")
  expect_identical(condition$field, "$.$version")
})

test_that("resolved data-dict structural collections remain JSON arrays", {
  cases <- list(
    tables = list(
      text = paste0(
        '{"$version":"0.1.0","name":"shape","tables":',
        '{"Thing":{"name":"Thing","columns":[]}}}'
      ),
      rule = "nonempty_tables"
    ),
    columns = list(
      text = paste0(
        '{"$version":"0.1.0","name":"shape","tables":[',
        '{"name":"Thing","columns":{"id":',
        '{"name":"id","type":"string",',
        '"constraints":["primary_key"]}}}]}'
      ),
      rule = "nonempty_columns"
    ),
    null_fields = list(
      text = paste0(
        '{"$version":"0.1.0","name":"shape","tables":[',
        '{"name":"Thing","columns":[',
        '{"name":"id","type":"string",',
        '"constraints":["primary_key"]},',
        '{"name":"payload","type":"string","fields":null}]}]}'
      ),
      rule = "unsupported_nested_fields"
    )
  )

  for (case in cases) {
    path <- withr::local_tempfile(fileext = ".json")
    writeLines(case$text, path, useBytes = TRUE)
    condition <- rlang::catch_cnd(graft_schema(path))
    expect_s3_class(condition, "graft_schema_error")
    expect_identical(condition$rule, case$rule)
  }
})

test_that("YAML preflight, export, and digest use one source snapshot", {
  path <- withr::local_tempfile(fileext = ".yaml")
  original <- c("$version: 0.1.0", "name: original", "tables: []")
  writeLines(original, path)
  expected_digest <- data_dict_source_snapshot(path)$digest
  exported_source <- NULL
  export_path <- NULL
  withr::local_options(graft.data_dict_cli = "configured-data-dict")
  local_mocked_bindings(
    data_dict_path_lookup = \(command) "/mock/data-dict",
    data_dict_file_digest = \(path) graft_sha256("mock-data-dict"),
    data_dict_system2 = function(command, args) {
      if (identical(args, "--version")) {
        return(list(
          status = 0L,
          stdout = "data-dict 0.0.1",
          stderr = character()
        ))
      }
      export_path <<- gsub("^['\"]|['\"]$", "", args[[2L]])
      exported_source <<- readLines(export_path, warn = FALSE)
      writeLines(
        c("$version: 9.9.9", "name: replacement", "tables: []"),
        path
      )
      list(
        status = 0L,
        stdout = '{"$version":"0.1.0","name":"original","tables":[]}',
        stderr = character()
      )
    }
  )

  contract <- read_data_dict_contract(path)

  expect_identical(contract$provider$source_spec_version, "0.1.0")
  expect_identical(contract$document$name, "original")
  expect_identical(contract$source_digest, expected_digest)
  expect_identical(exported_source, original)
  expect_identical(identical(export_path, normalizePath(path)), FALSE)
  expect_identical(basename(export_path), basename(path))
})

test_that("resolved JSON parsing and digest use one source snapshot", {
  path <- withr::local_tempfile(fileext = ".json")
  original <- '{"$version":"0.1.0","name":"original","tables":[]}'
  writeLines(original, path)
  expected_digest <- data_dict_source_snapshot(path)$digest
  local_mocked_bindings(
    read_resolved_data_dict_json = function(text, schema_path) {
      writeLines(
        '{"$version":"9.9.9","name":"replacement","tables":[]}',
        path
      )
      document <- jsonlite::fromJSON(text, simplifyVector = FALSE)
      validate_data_dict_json_numbers(document, text, schema_path)
      document
    }
  )

  contract <- read_data_dict_contract(path)

  expect_identical(contract$document$name, "original")
  expect_identical(contract$source_digest, expected_digest)
  expect_match(readLines(path, warn = FALSE), "replacement", fixed = TRUE)
})

test_that("resolved JSON fails closed on unsafe numeric metadata", {
  write_dictionary <- function(value) {
    path <- tempfile(fileext = ".json")
    withr::defer(unlink(path), envir = parent.frame())
    writeLines(
      paste0(
        '{"$version":"0.1.0","name":"exact","tables":[',
        '{"name":"Thing","columns":[',
        '{"name":"id","type":"string","constraints":["primary_key"]},',
        '{"name":"score","type":"number","examples":[',
        value,
        "]}]}]}"
      ),
      path
    )
    path
  }

  for (value in c(
    "9007199254740992",
    "-9007199254740992",
    "9223372036854775807"
  )) {
    condition <- rlang::catch_cnd(graft_schema(write_dictionary(value)))
    expect_s3_class(condition, "graft_schema_error")
    expect_identical(condition$rule, "unsafe_json_number")
    expect_match(condition$field, "examples")
    expect_identical(
      grepl("900719925474099", conditionMessage(condition), fixed = TRUE),
      FALSE
    )
  }

  positive <- graft_schema(write_dictionary("9007199254740991"))
  negative <- graft_schema(write_dictionary("-9007199254740991"))
  expect_identical(S7::S7_inherits(positive, GraftSchema), TRUE)
  expect_identical(S7::S7_inherits(negative, GraftSchema), TRUE)
})

test_that("resolved JSON checks unsafe numeric magnitude before rounding", {
  write_dictionary <- function(value) {
    path <- tempfile(fileext = ".json")
    withr::defer(unlink(path), envir = parent.frame())
    writeLines(
      paste0(
        '{"$version":"0.1.0","name":"exact","tables":[',
        '{"name":"Thing","columns":[',
        '{"name":"id","type":"string",',
        '"constraints":["primary_key"]},',
        '{"name":"score","type":"number","examples":[',
        value,
        "]}]}]}"
      ),
      path
    )
    path
  }

  condition <- rlang::catch_cnd(
    graft_schema(write_dictionary("9007199254740991.1"))
  )
  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "unsafe_json_number")
  expect_identical(condition$field, "$")
  expect_type(condition$character_offset, "integer")
  expect_identical(
    grepl("9007199254740991.1", conditionMessage(condition), fixed = TRUE),
    FALSE
  )

  safe <- graft_schema(write_dictionary("9007199254740991.0"))
  expect_identical(S7::S7_inherits(safe, GraftSchema), TRUE)
})

test_that("JSON numeric tokens exclude strings and compare exact magnitudes", {
  tokens <- data_dict_json_number_tokens(
    '{"text":"9007199254740991.1 and \\"1e99\\"","value":1}'
  )
  expect_identical(vapply(tokens, `[[`, character(1), "value"), "1")

  values <- c(
    "9007199254740991",
    "-9007199254740991",
    "9007199254740991.0",
    "9.007199254740991e15",
    "0.1",
    "2.5e-324",
    paste0("0e-", strrep("9", 500L)),
    "9007199254740991.1",
    "9007199254740992",
    "9.007199254740992e15",
    "90071992547409911e-1",
    "1e309",
    "1e-9999",
    paste0("1e-", strrep("9", 500L))
  )
  expect_identical(
    unname(vapply(
      values,
      data_dict_json_number_exceeds_safe_magnitude,
      logical(1)
    )),
    c(rep(FALSE, 7L), rep(TRUE, 7L))
  )
})

test_that("YAML preflight rejects columns export-spec would omit", {
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(
    c(
      "$version: 0.1.0",
      "tables:",
      "  - name: thing",
      "    columns:",
      "      - name: undocumented"
    ),
    path
  )
  local_mocked_bindings(
    locate_data_dict_cli = \() stop("The CLI should not run.")
  )

  condition <- rlang::catch_cnd(read_data_dict_contract(path))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "typed_columns")
  expect_identical(condition$field, "tables[1].columns[1].type")
})

test_that("resolved JSON top-level failures are classed schema errors", {
  path <- withr::local_tempfile(fileext = ".json")
  writeLines('{"$version":1,"tables":"not-an-array"}', path)

  condition <- rlang::catch_cnd(read_data_dict_contract(path))

  expect_s3_class(condition, "graft_schema_error")
  expect_setequal(condition$invalid_fields, c("$version", "tables"))
  expect_match(conditionMessage(condition), "invalid top-level field")
})

test_that("data-dict export diagnostics are preserved on failure", {
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(c("$version: 0.1.0", "tables: []"), path)
  withr::local_options(graft.data_dict_cli = "configured-data-dict")
  local_mocked_bindings(
    data_dict_path_lookup = \(command) "/mock/data-dict",
    data_dict_file_digest = \(path) graft_sha256("mock-data-dict"),
    data_dict_system2 = \(command, args) {
      list(status = 2L, stdout = character(), stderr = "S01 bad relation")
    }
  )

  condition <- rlang::catch_cnd(read_data_dict_contract(path))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$exit_status, 2L)
  expect_match(conditionMessage(condition), "S01 bad relation", fixed = TRUE)
})

test_that("CLI replacement during export aborts provenance capture", {
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(c("$version: 0.1.0", "tables: []"), path)
  calls <- character()
  digests <- c(
    graft_sha256("original-data-dict"),
    graft_sha256("replacement-data-dict")
  )
  digest_index <- 0L
  withr::local_options(graft.data_dict_cli = "configured-data-dict")
  local_mocked_bindings(
    data_dict_path_lookup = \(command) "/mock/data-dict",
    data_dict_file_digest = function(path) {
      digest_index <<- digest_index + 1L
      digests[[digest_index]]
    },
    data_dict_system2 = function(command, args) {
      calls <<- c(calls, args[[1L]])
      list(
        status = 0L,
        stdout = '{"$version":"0.1.0","tables":[]}',
        stderr = character()
      )
    }
  )

  condition <- rlang::catch_cnd(read_data_dict_contract(path))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "cli_executable_changed")
  expect_identical(condition$operation, "export-spec")
  expect_identical(condition$expected_cli_digest, digests[[1L]])
  expect_identical(condition$observed_cli_digest, digests[[2L]])
  expect_identical(calls, "export-spec")
})

test_that("CLI replacement during version lookup aborts provenance capture", {
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(c("$version: 0.1.0", "tables: []"), path)
  calls <- character()
  original <- graft_sha256("original-data-dict")
  replacement <- graft_sha256("replacement-data-dict")
  digests <- c(original, original, replacement)
  digest_index <- 0L
  withr::local_options(graft.data_dict_cli = "configured-data-dict")
  local_mocked_bindings(
    data_dict_path_lookup = \(command) "/mock/data-dict",
    data_dict_file_digest = function(path) {
      digest_index <<- digest_index + 1L
      digests[[digest_index]]
    },
    data_dict_system2 = function(command, args) {
      calls <<- c(calls, args[[1L]])
      if (identical(args, "--version")) {
        return(list(
          status = 0L,
          stdout = "data-dict 0.0.1",
          stderr = character()
        ))
      }
      list(
        status = 0L,
        stdout = '{"$version":"0.1.0","tables":[]}',
        stderr = character()
      )
    }
  )

  condition <- rlang::catch_cnd(read_data_dict_contract(path))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "cli_executable_changed")
  expect_identical(condition$operation, "version")
  expect_identical(condition$expected_cli_digest, original)
  expect_identical(condition$observed_cli_digest, replacement)
  expect_identical(calls, c("export-spec", "--version"))
})

test_that("CLI exports also fail closed on unsafe numeric metadata", {
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines(
    c("$version: 0.1.0", "name: exact", "tables: []"),
    path
  )
  withr::local_options(graft.data_dict_cli = "configured-data-dict")
  local_mocked_bindings(
    data_dict_path_lookup = \(command) "/mock/data-dict",
    data_dict_file_digest = \(path) graft_sha256("mock-data-dict"),
    data_dict_system2 = function(command, args) {
      if (identical(args, "--version")) {
        return(list(
          status = 0L,
          stdout = "data-dict 0.0.1",
          stderr = character()
        ))
      }
      list(
        status = 0L,
        stdout = paste0(
          '{"$version":"0.1.0","name":"exact","tables":[',
          '{"name":"Thing","columns":[',
          '{"name":"id","type":"string",',
          '"constraints":["primary_key"]},',
          '{"name":"score","type":"number",',
          '"examples":[9007199254740992]}]}]}'
        ),
        stderr = character()
      )
    }
  )

  condition <- rlang::catch_cnd(graft_schema(path))

  expect_s3_class(condition, "graft_schema_error")
  expect_identical(condition$rule, "unsafe_json_number")
})
