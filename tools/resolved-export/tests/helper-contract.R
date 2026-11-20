# Helpers for the non-executing proposed resolved-export contract ------------

resolved_contract_grain <- function() {
  list(
    status = "proposed",
    origin = "fixture-only",
    tables = list(
      sales = list(
        definitions = list(
          emea = list(grain = "row", value_type = "boolean"),
          total = list(grain = "aggregate", value_type = "number"),
          doubled = list(grain = "row", value_type = "number"),
          constant = list(grain = "scalar", value_type = "number"),
          total_doubled = list(grain = "aggregate", value_type = "number")
        )
      )
    )
  )
}

resolved_contract_bindings <- function(fixture) {
  list(
    dictionary = list(
      path = fixture$dictionary,
      sha256 = fixture$dictionary_sha256
    ),
    sources = list(
      sales = list(
        path = fixture$parquet,
        sha256 = fixture$parquet_sha256
      )
    ),
    export = list(
      path = fixture$export_path,
      sha256 = fixture$export_sha256
    ),
    report = list(
      path = fixture$validation$html,
      sha256 = fixture$validation$sha256
    ),
    validation = list(
      status = if (identical(fixture$validation$status, 0L)) "pass" else "fail",
      level = "data",
      profiling = FALSE,
      observed_status = fixture$validation$status
    )
  )
}

resolved_contract_fixture <- function(fixture) {
  list(
    export = fixture$export,
    grain = resolved_contract_grain(),
    bindings = resolved_contract_bindings(fixture)
  )
}

resolved_contract_admitted <- function(fixture) {
  input <- resolved_contract_fixture(fixture)
  do.call(
    resolved_proposal_admit,
    c(input, list(backend = "duckdb"))
  )
}

resolved_contract_binding_for <- function(path) {
  list(path = path, sha256 = upstream_file_sha256(path))
}

resolved_contract_cached_fixture <- local({
  cached <- NULL
  function() {
    if (is.null(cached)) {
      cached <<- upstream_test_fixture(fixture_dir, evidence_dir)
    }
    cached
  }
})

resolved_contract_write_export <- function(export, fixture, suffix) {
  path <- file.path(fixture$output_dir, paste0("contract-", suffix, ".json"))
  jsonlite::write_json(
    export,
    path,
    auto_unbox = TRUE,
    null = "null",
    pretty = FALSE,
    digits = NA
  )
  upstream_path(path, "contract export", must_work = TRUE)
}

resolved_contract_input <- function(
  fixture,
  export = fixture$export,
  suffix = NULL
) {
  if (is.null(suffix)) {
    return(resolved_contract_fixture(fixture))
  }
  export_path <- resolved_contract_write_export(export, fixture, suffix)
  list(
    export = export,
    grain = resolved_contract_grain(),
    bindings = within(resolved_contract_bindings(fixture), {
      export <- resolved_contract_binding_for(export_path)
    })
  )
}

resolved_contract_admit_input <- function(input) {
  resolved_proposal_admit(
    export = input$export,
    grain = input$grain,
    bindings = input$bindings,
    backend = "duckdb"
  )
}

resolved_contract_invalid_input <- function(fixture) {
  invalid <- upstream_fixture_invalid_values(fixture)
  export <- upstream_export(invalid$dictionary)
  validation <- upstream_validate_data(invalid)
  list(
    export = export,
    grain = resolved_contract_grain(),
    bindings = list(
      dictionary = resolved_contract_binding_for(invalid$dictionary),
      sources = list(sales = resolved_contract_binding_for(invalid$parquet)),
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
}
