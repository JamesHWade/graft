#' Compile a LinkML schema into a graft manifest
#'
#' `kg_compile_schema()` is the only public graft operation that requires
#' Python. It uses `linkml_runtime.SchemaView` to resolve the complete import
#' closure and writes a canonical JSON manifest. Loading the result with
#' [kg_schema()] does not require Python.
#'
#' Ordinary LinkML schemas do not need to import graft's core schema or use
#' graft annotations. Concrete classes receive conservative node, identity,
#' label, search, and timestamp defaults in the compiled manifest. Import
#' `graft-core.linkml` only when a schema needs graft-specific statement,
#' evidence, source, mention, edge, or metadata behavior.
#'
#' @param schema Path to a root LinkML YAML schema.
#' @param output Output path for the compiled `.graft.json` manifest. If
#'   `NULL`, the path is derived from `schema`.
#'
#' @return A [kg_schema()] object loaded from the compiled manifest.
#' @export
kg_compile_schema <- function(schema, output = NULL) {
  error_call <- rlang::caller_call()
  schema <- normalize_schema_input(schema)
  output <- normalize_manifest_output(schema, output)
  compiler <- graft_compiler_path()

  tryCatch(
    {
      reticulate::py_require("linkml-runtime>=1.9,<2")
      compiler_module <- reticulate::import_from_path(
        "compile_schema",
        path = dirname(compiler),
        convert = TRUE
      )
      compiler_module$compile_schema(schema, output)
    },
    error = function(error) {
      abort_schema_error(
        paste0(
          "Failed to compile LinkML schema `",
          schema,
          "`: ",
          conditionMessage(error)
        ),
        schema_path = schema,
        output_path = output,
        call = error_call
      )
    }
  )

  kg_schema(output)
}

normalize_schema_input <- function(schema) {
  if (
    !is.character(schema) ||
      length(schema) != 1L ||
      is.na(schema) ||
      !nzchar(schema)
  ) {
    abort_schema_error(
      "`schema` must be one non-empty path.",
      argument = "schema"
    )
  }
  if (!file.exists(schema)) {
    abort_schema_error(
      paste0("LinkML schema does not exist: `", schema, "`."),
      schema_path = schema
    )
  }
  normalizePath(schema, winslash = "/", mustWork = TRUE)
}

normalize_manifest_output <- function(schema, output) {
  if (is.null(output)) {
    output <- sub(
      "\\.(linkml\\.)?ya?ml$",
      ".graft.json",
      schema,
      ignore.case = TRUE
    )
    if (identical(output, schema)) {
      output <- paste0(schema, ".graft.json")
    }
  }
  if (
    !is.character(output) ||
      length(output) != 1L ||
      is.na(output) ||
      !nzchar(output)
  ) {
    abort_schema_error(
      "`output` must be one non-empty path or `NULL`.",
      argument = "output"
    )
  }
  normalizePath(
    file.path(dirname(output), basename(output)),
    winslash = "/",
    mustWork = FALSE
  )
}

graft_compiler_path <- function() {
  path <- system.file("python", "compile_schema.py", package = "graft")
  if (!nzchar(path)) {
    development_path <- file.path("inst", "python", "compile_schema.py")
    if (file.exists(development_path)) {
      path <- development_path
    }
  }
  if (!nzchar(path) || !file.exists(path)) {
    abort_schema_error("The graft LinkML compiler script is unavailable.")
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}
