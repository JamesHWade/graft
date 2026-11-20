test_that("admission and request return a non-executing proposed closure", {
  fixture <- resolved_contract_cached_fixture()
  input <- resolved_contract_fixture(fixture)
  proposal <- resolved_contract_admitted(fixture)

  expect_identical(proposal$status, "proposed")
  expect_identical(proposal$executable, FALSE)
  expect_identical(
    proposal$composition,
    "unavailable-in-current-export"
  )
  expect_identical(proposal$identity$sources$sales$path, fixture$parquet)
  expect_identical(
    proposal$tables$sales$definitions$total$translations,
    input$export$tables[[1L]]$definitions[[2L]]$translations
  )

  request <- resolved_proposal_request(
    proposal,
    metrics = c("constant", "total_doubled"),
    dimensions = "doubled",
    filters = "emea"
  )
  expect_identical(request$executable, FALSE)
  expect_identical(
    request$composition,
    "unavailable-in-current-export"
  )
  expect_identical(
    request$dependency_closure,
    c("constant", "doubled", "total_doubled", "emea")
  )
  expect_identical(
    request$definitions$total_doubled$expression,
    input$export$tables[[1L]]$definitions[[5L]]$expression
  )
  expect_null(request$sql)
  expect_null(request$compiled)
})

test_that("current export without proposed grain metadata is refused", {
  fixture <- resolved_contract_cached_fixture()
  expect_error(
    resolved_proposal_admit(
      export = fixture$export,
      grain = NULL,
      bindings = resolved_contract_bindings(fixture)
    ),
    class = "resolved_proposal_metadata_error",
    regexp = "Hand-authored grain metadata"
  )
})

test_that("host bindings verify dictionary, source, export, and report bytes", {
  fixture <- resolved_contract_cached_fixture()
  bindings <- resolved_contract_bindings(fixture)
  paths <- c(
    dictionary = bindings$dictionary$path,
    source = bindings$sources$sales$path,
    export = bindings$export$path,
    report = bindings$report$path
  )
  for (name in names(paths)) {
    stale <- file.path(fixture$output_dir, paste0("stale-", name))
    bytes <- readBin(
      paths[[name]],
      what = "raw",
      n = file.info(paths[[name]])$size
    )
    writeBin(c(bytes, as.raw(0L)), stale)
    candidate <- bindings
    if (identical(name, "dictionary")) {
      candidate$dictionary$path <- stale
    } else if (identical(name, "source")) {
      candidate$sources$sales$path <- stale
    } else {
      candidate[[name]]$path <- stale
    }
    expect_error(
      resolved_proposal_admit(
        fixture$export,
        resolved_contract_grain(),
        candidate
      ),
      class = "resolved_proposal_identity_error",
      info = name
    )
  }
})

test_that("profiling and failed or non-data validation are not admission evidence", {
  fixture <- resolved_contract_cached_fixture()
  cases <- list(
    profiling = list(status = "pass", level = "profile", profiling = TRUE),
    failed = list(status = "fail", level = "data", profiling = FALSE),
    spec = list(status = "pass", level = "spec", profiling = FALSE),
    missing = NULL
  )
  for (name in names(cases)) {
    bindings <- resolved_contract_bindings(fixture)
    bindings$validation <- cases[[name]]
    expect_error(
      resolved_proposal_admit(
        fixture$export,
        resolved_contract_grain(),
        bindings
      ),
      class = "resolved_proposal_validation_error",
      info = name
    )
  }
})

test_that("an actual failed data-validation report refuses admission", {
  fixture <- resolved_contract_cached_fixture()
  input <- resolved_contract_invalid_input(fixture)
  expect_gt(input$bindings$validation$observed_status, 0L)
  expect_error(
    resolved_contract_admit_input(input),
    class = "resolved_proposal_validation_error",
    regexp = "successful data-validation"
  )
})

test_that("format and backend selection are explicit", {
  fixture <- resolved_contract_cached_fixture()
  invalid_version <- fixture$export
  invalid_version[["$version"]] <- "0.2.0"
  expect_error(
    resolved_proposal_admit(
      invalid_version,
      resolved_contract_grain(),
      resolved_contract_bindings(fixture)
    ),
    class = "resolved_proposal_schema_error",
    regexp = "Unsupported upstream export format"
  )
  expect_error(
    resolved_proposal_admit(
      fixture$export,
      resolved_contract_grain(),
      resolved_contract_bindings(fixture),
      backend = "SQL(snowflake)"
    ),
    class = "resolved_proposal_backend_error",
    regexp = "only `SQL\\(duckdb\\)`"
  )
  expect_type(
    resolved_proposal_admit(
      fixture$export,
      resolved_contract_grain(),
      resolved_contract_bindings(fixture),
      backend = "SQL(duckdb)"
    ),
    "list"
  )
})

test_that("typed definitions, duplicate names, and references are checked", {
  fixture <- resolved_contract_cached_fixture()
  missing_column_type <- fixture$export
  missing_column_type$tables[[1L]]$columns[[1L]]$type <- NULL
  expect_error(
    resolved_contract_admit_input(resolved_contract_input(
      fixture,
      missing_column_type,
      "missing-column-type"
    )),
    class = "resolved_proposal_type_error",
    regexp = "Column .* needs a supported type"
  )
  non_boolean_filter <- fixture$export
  non_boolean_filter$tables[[1L]]$definitions[[1L]]$type <- "string"
  expect_error(
    resolved_contract_admit_input(resolved_contract_input(
      fixture,
      non_boolean_filter,
      "non-boolean-filter"
    )),
    class = "resolved_proposal_type_error",
    regexp = "must have boolean type"
  )
  missing_type <- fixture$export
  nested_reference <- fixture$export
  nested_reference$tables[[1L]]$definitions[[3L]]$columns <- list(
    "revenue.missing_field"
  )
  expect_error(
    resolved_contract_admit_input(resolved_contract_input(
      fixture,
      nested_reference,
      "nested-reference"
    )),
    class = "resolved_proposal_reference_error",
    regexp = "references missing columns"
  )
  missing_type$tables[[1L]]$definitions[[1L]]$type <- NULL
  missing_type_input <- resolved_contract_input(
    fixture,
    missing_type,
    "missing-type"
  )
  expect_error(
    resolved_contract_admit_input(missing_type_input),
    class = "resolved_proposal_type_error",
    regexp = "supported typed `type`"
  )

  duplicate <- fixture$export
  duplicate$tables[[1L]]$definitions[[2L]]$name <-
    duplicate$tables[[1L]]$definitions[[1L]]$name
  duplicate_input <- resolved_contract_input(fixture, duplicate, "duplicate")
  expect_error(
    resolved_contract_admit_input(duplicate_input),
    class = "resolved_proposal_reference_error",
    regexp = "duplicate"
  )

  missing_reference <- fixture$export
  missing_reference$tables[[1L]]$definitions[[5L]]$definitions <-
    list("not_exported")
  missing_reference_input <- resolved_contract_input(
    fixture,
    missing_reference,
    "missing-reference"
  )
  expect_error(
    resolved_contract_admit_input(missing_reference_input),
    class = "resolved_proposal_reference_error",
    regexp = "missing definitions"
  )
})

test_that("dependency cycles and selected translation refusals fail clearly", {
  fixture <- resolved_contract_cached_fixture()
  cyclic <- fixture$export
  cyclic$tables[[1L]]$definitions[[3L]]$definitions <- list("total_doubled")
  cyclic_input <- resolved_contract_input(fixture, cyclic, "cyclic")
  expect_error(
    resolved_contract_admit_input(cyclic_input),
    class = "resolved_proposal_reference_error",
    regexp = "cyclic"
  )

  no_target <- fixture$export
  total <- no_target$tables[[1L]]$definitions[[2L]]
  target <- vapply(total$translations, `[[`, character(1), "target")
  total$translations <- total$translations[target != "SQL(duckdb)"]
  no_target$tables[[1L]]$definitions[[2L]] <- total
  no_target_input <- resolved_contract_input(fixture, no_target, "no-target")
  expect_error(
    resolved_contract_admit_input(no_target_input),
    class = "resolved_proposal_translation_error",
    regexp = "no `SQL\\(duckdb\\)` translation"
  )

  refused <- fixture$export
  total <- refused$tables[[1L]]$definitions[[2L]]
  target <- vapply(total$translations, `[[`, character(1), "target")
  index <- which(target == "SQL(duckdb)")[[1L]]
  translation <- total$translations[[index]]
  translation$code <- NULL
  translation$error <- "fixture target refusal"
  total$translations[[index]] <- translation
  refused$tables[[1L]]$definitions[[2L]] <- total
  refused_input <- resolved_contract_input(fixture, refused, "refused")
  expect_error(
    resolved_contract_admit_input(refused_input),
    class = "resolved_proposal_translation_error",
    regexp = "fixture target refusal"
  )
})

test_that("raw export paths never select host input paths", {
  fixture <- resolved_contract_cached_fixture()
  export <- fixture$export
  export$tables[[1L]]$source$parquet <- "/hostile/export-relative-path.parquet"
  input <- resolved_contract_input(fixture, export, "host-path")
  proposal <- resolved_contract_admit_input(input)
  expect_identical(proposal$identity$sources$sales$path, fixture$parquet)
  expect_identical(
    resolved_proposal_request(proposal, metrics = "total")$table,
    "sales"
  )
})

test_that("grain is explicit, scalar and aggregate remain distinct, and mixed is refused", {
  fixture <- resolved_contract_cached_fixture()
  proposal <- resolved_contract_admitted(fixture)
  request <- resolved_proposal_request(
    proposal,
    metrics = c("constant", "total")
  )
  expect_identical(
    vapply(
      request$definitions[c("constant", "total")],
      `[[`,
      character(1),
      "grain"
    ),
    c(constant = "scalar", total = "aggregate")
  )

  missing <- resolved_contract_grain()
  missing$tables$sales$definitions$total <- NULL
  expect_error(
    resolved_proposal_admit(
      fixture$export,
      missing,
      resolved_contract_bindings(fixture)
    ),
    class = "resolved_proposal_metadata_error",
    regexp = "cover exactly"
  )

  mixed <- resolved_contract_grain()
  mixed$tables$sales$definitions$total$grain <- "mixed"
  expect_error(
    resolved_proposal_admit(
      fixture$export,
      mixed,
      resolved_contract_bindings(fixture)
    ),
    class = "resolved_proposal_grain_error",
    regexp = "Mixed-grain"
  )

  forged <- proposal
  forged$tables$sales$definitions$total$grain <- "mixed"
  expect_error(
    resolved_proposal_request(forged, metrics = "total"),
    class = "resolved_proposal_grain_error",
    regexp = "Mixed-grain"
  )
})

test_that("request roles follow supplied grain instead of the lossy kind", {
  fixture <- resolved_contract_cached_fixture()
  proposal <- resolved_contract_admitted(fixture)
  expect_error(
    resolved_proposal_request(proposal, dimensions = "total"),
    class = "resolved_proposal_role_error",
    regexp = "row-grain dimension"
  )
  expect_error(
    resolved_proposal_request(proposal, filters = "total"),
    class = "resolved_proposal_role_error",
    regexp = "boolean filter"
  )
  expect_error(
    resolved_proposal_request(proposal, metrics = "doubled"),
    class = "resolved_proposal_role_error",
    regexp = "scalar or aggregate metric"
  )
  expect_error(
    resolved_proposal_request(proposal, dimensions = "emea"),
    class = "resolved_proposal_role_error",
    regexp = "row-grain dimension"
  )
  non_boolean <- proposal
  non_boolean$tables$sales$definitions$emea$type <- "string"
  expect_error(
    resolved_proposal_request(non_boolean, filters = "emea"),
    class = "resolved_proposal_role_error",
    regexp = "boolean filter"
  )
})

test_that("language, canonical form, fidelity, notes, and errors remain unchanged", {
  fixture <- resolved_contract_cached_fixture()
  variant <- upstream_test_variant(
    fixture,
    "contract-r-language",
    "!is.na(revenue)",
    language = "r"
  )
  export <- upstream_export(variant$dictionary)
  validation <- upstream_validate_data(variant)
  expect_identical(validation$status, 0L)
  definition <- upstream_definition_map(export)$probe
  input <- list(
    export = export,
    grain = list(
      status = "proposed",
      origin = "fixture-only",
      tables = list(
        sales = list(
          definitions = list(
            probe = list(grain = "row", value_type = "boolean")
          )
        )
      )
    ),
    bindings = list(
      dictionary = resolved_contract_binding_for(variant$dictionary),
      sources = list(sales = resolved_contract_binding_for(variant$parquet)),
      export = resolved_contract_binding_for(attr(export, "raw_path")),
      report = resolved_contract_binding_for(validation$html),
      validation = list(
        status = if (identical(validation$status, 0L)) "pass" else "fail",
        level = "data",
        profiling = FALSE,
        observed_status = validation$status
      )
    )
  )
  proposal <- resolved_contract_admit_input(input)
  selected <- resolved_proposal_request(proposal, filters = "probe")
  retained <- selected$definitions$probe
  expect_identical(retained$expression, definition$expression)
  expect_identical(retained$language, definition$language)
  expect_identical(retained$canonical, definition$canonical)
  expect_identical(retained$fidelity, definition$fidelity)
  expect_identical(retained$notes, definition$notes)
  expect_identical(retained$translations, definition$translations)
  expect_match(retained$expression, "!is.na", fixed = TRUE)
  expect_match(retained$canonical, "IS NOT NULL", fixed = TRUE)
  expect_identical(identical(retained$expression, retained$canonical), FALSE)
})

test_that("a separately created Commons source remains usable after refusal", {
  fixture <- resolved_contract_cached_fixture()
  proposal <- resolved_contract_admitted(fixture)
  measure_file <- upstream_write_measure_file(fixture$output_dir)
  layer <- commons::semantic_layer(measure_file)
  commons <- upstream_test_commons(fixture, semantic_layer = layer)
  before <- list(
    total = commons$metrics("total")$total,
    measure = commons$measure("authored_total")
  )
  expect_error(
    resolved_proposal_request(proposal, dimensions = "total"),
    class = "resolved_proposal_role_error"
  )
  after <- list(
    total = commons$metrics("total")$total,
    measure = commons$measure("authored_total")
  )
  expect_identical(before, after)
  expect_identical(before$measure, 35)
})

test_that("proposed metadata and selection do not absorb file measures", {
  fixture <- resolved_contract_cached_fixture()
  proposal <- resolved_contract_admitted(fixture)
  request <- resolved_proposal_request(proposal, metrics = "total")
  expect_null(proposal$file_measures)
  expect_null(request$file_measures)
  expect_identical(names(request$roles), c("metrics", "dimensions", "filters"))
})
