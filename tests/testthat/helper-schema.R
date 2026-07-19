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

plain_linkml_schema_path <- function() {
  test_path(
    "fixtures",
    "plain-linkml",
    "personinfo.linkml.yaml"
  )
}

example_schema_path <- function(name) {
  filename <- paste0(name, ".linkml.yaml")
  development_path <- test_path(
    "..",
    "..",
    "inst",
    "extdata",
    filename
  )
  if (file.exists(development_path)) {
    return(normalizePath(
      development_path,
      winslash = "/",
      mustWork = TRUE
    ))
  }

  installed_path <- system.file(
    "extdata",
    filename,
    package = "graft"
  )
  if (!nzchar(installed_path)) {
    stop("The installed example schema is unavailable.", call. = FALSE)
  }
  normalizePath(installed_path, winslash = "/", mustWork = TRUE)
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

  source <- readLines(path, warn = FALSE)
  if (!any(grepl("graft-core.linkml", source, fixed = TRUE))) {
    return(path)
  }
  source <- stage_test_schema_core(source, dirname(path))
  writeLines(source, path)
  path
}

stage_test_schema_core <- function(source, directory) {
  import <- grepl("graft-core.linkml", source, fixed = TRUE)
  if (sum(import) != 1L) {
    stop("Expected exactly one graft core schema import.", call. = FALSE)
  }
  copied <- file.copy(
    graft_core_schema_path(),
    file.path(directory, "graft-core.linkml.yaml"),
    overwrite = TRUE
  )
  if (!isTRUE(copied)) {
    stop("Failed to stage the graft core schema.", call. = FALSE)
  }
  source[import] <- "  - graft-core.linkml"
  source
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
