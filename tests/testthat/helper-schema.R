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

refresh_schema_structural_digest <- function(schema) {
  schema$manifest$fingerprints$structural_digest <-
    manifest_structural_digest(schema$manifest)
  schema$manifest$fingerprints$build_digest <-
    manifest_build_digest(schema$manifest)
  schema
}

plain_linkml_schema_path <- function(name = "personinfo.linkml.yaml") {
  test_path(
    "fixtures",
    "plain-linkml",
    name
  )
}

data_dict_personinfo_export_path <- function() {
  test_path(
    "fixtures",
    "data-dict",
    "personinfo",
    "data-dict.export.json"
  )
}

data_dict_tempest_export_path <- function() {
  test_path(
    "fixtures",
    "data-dict",
    "tempest",
    "data-dict.export.json"
  )
}

data_dict_test_source <- function(dictionary, content_digest = NULL) {
  if (is.null(content_digest)) {
    content_digest <- graft_sha256(canonical_json(dictionary))
  }
  data_dict_manifest_source(dictionary, content_digest)
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

graft_manifest_definition_path <- function() {
  development_path <- test_path(
    "..",
    "..",
    "inst",
    "schema",
    "graft-manifest.schema.json"
  )
  if (file.exists(development_path)) {
    return(normalizePath(development_path, winslash = "/", mustWork = TRUE))
  }

  installed_path <- system.file(
    "schema",
    "graft-manifest.schema.json",
    package = "graft"
  )
  if (!nzchar(installed_path)) {
    stop("The installed manifest schema is unavailable.", call. = FALSE)
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
