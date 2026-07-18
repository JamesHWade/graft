tempest_schema_path <- function() {
  materialize_test_schema_import(test_path(
    "fixtures",
    "tempest-schema",
    "tempest-artifacts.linkml.yaml"
  ))
}

tempest_manifest_path <- function() {
  test_path(
    "fixtures",
    "tempest-schema",
    "tempest-artifacts.graft.json"
  )
}

invalid_schema_path <- function(name) {
  materialize_test_schema_import(
    test_path("fixtures", "invalid-records", name)
  )
}

graft_core_schema_path <- function() {
  development_path <- test_path(
    "..",
    "..",
    "inst",
    "schema",
    "graft-core.linkml.yaml"
  )
  if (file.exists(development_path)) {
    return(normalizePath(development_path, winslash = "/", mustWork = TRUE))
  }

  installed_path <- system.file(
    "schema",
    "graft-core.linkml.yaml",
    package = "graft"
  )
  if (!nzchar(installed_path)) {
    stop("The installed graft core schema is unavailable.", call. = FALSE)
  }
  normalizePath(installed_path, winslash = "/", mustWork = TRUE)
}

materialize_test_schema_import <- function(path) {
  relative_core <- file.path(
    dirname(path),
    "..",
    "..",
    "..",
    "..",
    "inst",
    "schema",
    "graft-core.linkml.yaml"
  )
  if (file.exists(relative_core)) {
    return(path)
  }

  core_import <- sub("\\.yaml$", "", graft_core_schema_path())
  source <- readLines(path, warn = FALSE)
  source <- sub(
    "../../../../inst/schema/graft-core.linkml",
    core_import,
    source,
    fixed = TRUE
  )
  writeLines(source, path)
  path
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
  redacted <- gsub(
    normalizePath(test_path("..", ".."), winslash = "/"),
    "<repo>",
    x,
    fixed = TRUE
  )
  sub(
    "<repo>/graft-tests/",
    "<repo>/tests/",
    redacted,
    fixed = TRUE
  )
}
