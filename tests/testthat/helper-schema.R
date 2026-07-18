tempest_schema_path <- function() {
  test_path(
    "fixtures",
    "tempest-schema",
    "tempest-artifacts.linkml.yaml"
  )
}

tempest_manifest_path <- function() {
  test_path(
    "fixtures",
    "tempest-schema",
    "tempest-artifacts.graft.json"
  )
}

invalid_schema_path <- function(name) {
  test_path("fixtures", "invalid-records", name)
}

skip_if_no_linkml_runtime <- function() {
  available <- suppressWarnings(
    tryCatch(
      {
        reticulate::py_require("linkml-runtime>=1.9,<2")
        reticulate::py_module_available("linkml_runtime")
      },
      error = function(...) FALSE
    )
  )
  skip_if_not(
    isTRUE(available),
    "linkml-runtime is not available in the selected Python environment"
  )
}

redact_repo_path <- function(x) {
  gsub(
    normalizePath(test_path("..", ".."), winslash = "/"),
    "<repo>",
    x,
    fixed = TRUE
  )
}
