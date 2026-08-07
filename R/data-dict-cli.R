is_data_dict_document <- function(path) {
  if (
    !data_dict_is_scalar_text(path) || !file.exists(path) || dir.exists(path)
  ) {
    return(FALSE)
  }

  extension <- data_dict_file_extension(path)
  if (!extension %in% c("json", "yaml", "yml")) {
    return(FALSE)
  }
  if (
    extension %in%
      c("yaml", "yml") &&
      tolower(basename(path)) %in% c("data-dict.yaml", "data-dict.yml")
  ) {
    return(TRUE)
  }

  document <- tryCatch(
    if (identical(extension, "json")) {
      jsonlite::fromJSON(
        path,
        simplifyVector = FALSE
      )
    } else {
      yaml::read_yaml(path, eval.expr = FALSE)
    },
    error = \(error) NULL
  )
  data_dict_has_resolved_header(document)
}

locate_data_dict_cli <- function() {
  configured <- getOption("graft.data_dict_cli", NULL)
  if (!is.null(configured)) {
    return(resolve_data_dict_cli(configured, "option `graft.data_dict_cli`"))
  }

  configured <- Sys.getenv("GRAFT_DATA_DICT_CLI", unset = "")
  if (nzchar(configured)) {
    return(resolve_data_dict_cli(
      configured,
      "environment variable `GRAFT_DATA_DICT_CLI`"
    ))
  }

  path <- data_dict_path_lookup("data-dict")
  if (!data_dict_is_scalar_text(path)) {
    abort_schema_error(
      paste0(
        "Could not find the data-dict CLI. Install `data-dict` or set ",
        "option `graft.data_dict_cli` or environment variable ",
        "`GRAFT_DATA_DICT_CLI`."
      ),
      cli = "data-dict"
    )
  }
  path
}

read_data_dict_contract <- function(path) {
  source_path <- normalize_data_dict_path(path)
  source_format <- data_dict_file_extension(source_path)
  if (!source_format %in% c("json", "yaml", "yml")) {
    abort_schema_error(
      paste0(
        "Data-dict source `",
        source_path,
        "` must be YAML or resolved JSON."
      ),
      schema_path = source_path
    )
  }
  snapshot <- data_dict_source_snapshot(source_path)

  cli_version <- NULL
  cli_digest <- NULL
  source_spec_version <- NULL
  if (identical(source_format, "json")) {
    document <- read_resolved_data_dict_json(snapshot$text, source_path)
    source_format <- "resolved_json"
  } else {
    source <- validate_data_dict_graft_yaml(snapshot$text, source_path)
    if (
      is.list(source) &&
        data_dict_is_scalar_text(source[["$version"]])
    ) {
      source_spec_version <- source[["$version"]]
    }
    cli <- locate_data_dict_cli()
    cli_digest <- data_dict_file_digest(cli)
    snapshot_file <- write_data_dict_source_snapshot(
      snapshot$bytes,
      source_path
    )
    on.exit(unlink(snapshot_file$directory, recursive = TRUE), add = TRUE)
    document <- export_data_dict_spec(
      cli,
      snapshot_file$path,
      schema_path = source_path
    )
    data_dict_assert_cli_unchanged(cli, cli_digest, "export-spec")
    cli_version <- data_dict_cli_version(cli)
    data_dict_assert_cli_unchanged(cli, cli_digest, "version")
    source_format <- "yaml"
  }
  validate_resolved_data_dict(document, source_path)

  list(
    document = document,
    source_digest = snapshot$digest,
    provider = list(
      name = "data-dict",
      export_format_version = document[["$version"]],
      source_spec_version = source_spec_version,
      cli_version = cli_version,
      cli_digest = cli_digest,
      revision = data_dict_revision(),
      source_path = source_path,
      source_format = source_format
    )
  )
}

data_dict_source_snapshot <- function(path) {
  connection <- tryCatch(
    file(path, open = "rb"),
    error = function(error) {
      abort_schema_error(
        paste0("Could not read data-dict source `", path, "`."),
        schema_path = path,
        parent = error
      )
    }
  )
  connection_open <- TRUE
  on.exit(if (connection_open) close(connection), add = TRUE)
  chunks <- list()
  repeat {
    chunk <- tryCatch(
      readBin(connection, what = "raw", n = 65536L),
      error = function(error) {
        abort_schema_error(
          paste0("Could not read data-dict source `", path, "`."),
          schema_path = path,
          parent = error
        )
      }
    )
    if (length(chunk) == 0L) {
      break
    }
    chunks[[length(chunks) + 1L]] <- chunk
  }
  bytes <- if (length(chunks) == 0L) {
    raw()
  } else {
    do.call(c, chunks)
  }
  text <- tryCatch(
    rawToChar(bytes),
    error = function(error) {
      abort_schema_error(
        paste0("Data-dict source `", path, "` is not valid text."),
        schema_path = path,
        parent = error
      )
    }
  )
  list(bytes = bytes, text = text, digest = graft_sha256(bytes))
}

write_data_dict_source_snapshot <- function(bytes, source_path) {
  directory <- tempfile("graft-data-dict-source-")
  if (!dir.create(directory)) {
    abort_schema_error(
      "Could not create a temporary data-dict source snapshot.",
      schema_path = source_path
    )
  }
  complete <- FALSE
  on.exit(
    if (!complete) unlink(directory, recursive = TRUE),
    add = TRUE
  )
  path <- file.path(directory, basename(source_path))
  connection <- tryCatch(
    file(path, open = "wb"),
    error = function(error) {
      abort_schema_error(
        "Could not create a temporary data-dict source snapshot.",
        schema_path = source_path,
        parent = error
      )
    }
  )
  connection_open <- TRUE
  on.exit(if (connection_open) close(connection), add = TRUE)
  tryCatch(
    writeBin(bytes, connection),
    error = function(error) {
      abort_schema_error(
        "Could not write a temporary data-dict source snapshot.",
        schema_path = source_path,
        parent = error
      )
    }
  )
  close(connection)
  connection_open <- FALSE
  complete <- TRUE
  list(path = path, directory = directory)
}

validate_data_dict_graft_yaml <- function(text, path) {
  source <- tryCatch(
    yaml::yaml.load(text, eval.expr = FALSE),
    error = \(error) NULL
  )
  if (!is.list(source) || !is.list(source$tables)) {
    return(invisible(source))
  }
  for (table_index in seq_along(source$tables)) {
    table <- source$tables[[table_index]]
    if (!is.list(table) || !is.list(table$columns)) {
      next
    }
    for (column_index in seq_along(table$columns)) {
      column <- table$columns[[column_index]]
      if (is.list(column) && data_dict_is_scalar_text(column$type)) {
        next
      }
      field <- paste0(
        "tables[",
        table_index,
        "].columns[",
        column_index,
        "].type"
      )
      abort_schema_error(
        paste0(
          "The graft-table-v1 profile requires every declared data-dict ",
          "column to have a type; `export-spec` omits untyped columns."
        ),
        schema_path = path,
        field = field,
        rule = "typed_columns"
      )
    }
  }
  invisible(source)
}

data_dict_file_digest <- function(path) {
  size <- file.info(path)$size
  if (is.na(size)) {
    abort_schema_error(
      paste0("Could not read data-dict executable `", path, "`."),
      cli_path = path
    )
  }
  bytes <- readBin(path, what = "raw", n = size)
  graft_sha256(bytes)
}

data_dict_assert_cli_unchanged <- function(path, expected_digest, operation) {
  observed_digest <- data_dict_file_digest(path)
  if (!identical(observed_digest, expected_digest)) {
    abort_schema_error(
      paste0(
        "The data-dict executable changed while running `",
        operation,
        "`; refusing to record inconsistent provider provenance."
      ),
      cli_path = path,
      operation = operation,
      rule = "cli_executable_changed",
      expected_cli_digest = expected_digest,
      observed_cli_digest = observed_digest
    )
  }
  invisible(observed_digest)
}

read_resolved_data_dict_json <- function(text, path) {
  document <- tryCatch(
    jsonlite::fromJSON(
      text,
      simplifyVector = FALSE
    ),
    error = function(error) {
      abort_schema_error(
        paste0(
          "Could not parse resolved data-dict JSON `",
          path,
          "`: ",
          conditionMessage(error)
        ),
        schema_path = path,
        parent = error
      )
    }
  )
  data_dict_reject_duplicate_json_keys(document, path)
  validate_data_dict_json_numbers(document, text, path)
  document
}

validate_data_dict_json_numbers <- function(
  document,
  text,
  path,
  subject = "resolved data-dict"
) {
  data_dict_reject_unsafe_json_numbers(document)
  tokens <- data_dict_json_number_tokens(text)
  unsafe <- which(vapply(
    tokens,
    \(token) data_dict_json_number_exceeds_safe_magnitude(token$value),
    logical(1)
  ))
  if (length(unsafe) > 0L) {
    token <- tokens[[unsafe[[1L]]]]
    data_dict_abort(
      paste(
        paste0("The ", subject, " contains a JSON numeric token that cannot"),
        "cross the R boundary safely; use a quoted string contract instead."
      ),
      field = "$",
      rule = "unsafe_json_number",
      schema_path = path,
      character_offset = token$offset
    )
  }
  invisible(document)
}

data_dict_json_number_tokens <- function(text) {
  characters <- strsplit(text, "", fixed = TRUE)[[1L]]
  count <- length(characters)
  tokens <- list()
  index <- 1L
  in_string <- FALSE
  escaped <- FALSE
  while (index <= count) {
    character <- characters[[index]]
    if (in_string) {
      if (escaped) {
        escaped <- FALSE
      } else if (identical(character, "\\")) {
        escaped <- TRUE
      } else if (identical(character, '"')) {
        in_string <- FALSE
      }
      index <- index + 1L
      next
    }
    if (identical(character, '"')) {
      in_string <- TRUE
      index <- index + 1L
      next
    }
    if (!grepl("[-0-9]", character)) {
      index <- index + 1L
      next
    }
    remainder <- substr(text, index, nchar(text))
    match <- regexpr(
      "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?",
      remainder,
      perl = TRUE
    )
    match_length <- attr(match, "match.length", exact = TRUE)
    if (match[[1L]] != 1L || match_length <= 0L) {
      index <- index + 1L
      next
    }
    value <- substr(remainder, 1L, match_length)
    tokens[[length(tokens) + 1L]] <- list(value = value, offset = index)
    index <- index + match_length
  }
  tokens
}

data_dict_json_number_exceeds_safe_magnitude <- function(value) {
  match <- regexec(
    "^-?(0|[1-9][0-9]*)(?:\\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$",
    value,
    perl = TRUE
  )
  parts <- regmatches(value, match)[[1L]]
  if (length(parts) != 4L) {
    return(TRUE)
  }
  integer <- parts[[2L]]
  fraction <- parts[[3L]]
  exponent_text <- parts[[4L]]
  exponent <- if (nzchar(exponent_text)) {
    suppressWarnings(as.numeric(exponent_text))
  } else {
    0
  }
  digits <- paste0(integer, fraction)
  nonzero <- regexpr("[1-9]", digits)[[1L]]
  if (identical(nonzero, -1L)) {
    return(FALSE)
  }
  if (!is.finite(exponent)) {
    return(TRUE)
  }
  parsed <- tryCatch(
    jsonlite::fromJSON(paste0("[", value, "]"))[[1L]],
    error = \(error) NA_real_
  )
  if (!is.finite(parsed) || identical(parsed, 0)) {
    return(TRUE)
  }
  order <- nchar(integer) + exponent - nonzero
  if (order < 15) {
    return(FALSE)
  }
  if (order > 15) {
    return(TRUE)
  }

  significant <- substr(digits, nonzero, nchar(digits))
  candidate <- substr(paste0(significant, strrep("0", 16L)), 1L, 16L)
  limit <- "9007199254740991"
  difference <- utf8ToInt(candidate) - utf8ToInt(limit)
  first_difference <- which(difference != 0L)
  if (length(first_difference) > 0L) {
    return(difference[[first_difference[[1L]]]] > 0L)
  }
  remainder <- substr(significant, 17L, nchar(significant))
  nzchar(remainder) && grepl("[1-9]", remainder)
}

export_data_dict_spec <- function(cli, path, schema_path = path) {
  result <- run_data_dict_process(
    cli,
    c("export-spec", shQuote(path)),
    operation = "export-spec",
    schema_path = schema_path
  )
  if (!identical(result$status, 0L)) {
    abort_schema_error(
      paste0(
        "data-dict could not export `",
        schema_path,
        "`: ",
        data_dict_process_diagnostics(result)
      ),
      schema_path = schema_path,
      cli_path = cli,
      exit_status = result$status,
      cli_output = c(result$stdout, result$stderr)
    )
  }

  text <- paste(result$stdout, collapse = "\n")
  document <- tryCatch(
    jsonlite::fromJSON(
      text,
      simplifyVector = FALSE
    ),
    error = function(error) {
      abort_schema_error(
        paste0(
          "data-dict returned invalid resolved JSON for `",
          schema_path,
          "`: ",
          conditionMessage(error)
        ),
        schema_path = schema_path,
        cli_path = cli,
        parent = error
      )
    }
  )
  data_dict_reject_duplicate_json_keys(document, schema_path)
  validate_data_dict_json_numbers(document, text, schema_path)
  diagnostics <- trimws(result$stderr[nzchar(trimws(result$stderr))])
  if (length(diagnostics) > 0L) {
    rlang::warn(
      paste0(
        "data-dict exported the contract with diagnostics:\n",
        paste(diagnostics, collapse = "\n")
      ),
      class = c("graft_data_dict_warning", "graft_schema_warning"),
      schema_path = schema_path,
      cli_path = cli,
      cli_output = diagnostics
    )
  }
  document
}

data_dict_cli_version <- function(cli) {
  result <- run_data_dict_process(
    cli,
    "--version",
    operation = "version"
  )
  if (!identical(result$status, 0L)) {
    abort_schema_error(
      paste0(
        "Could not determine the data-dict CLI version: ",
        data_dict_process_diagnostics(result)
      ),
      cli_path = cli,
      exit_status = result$status,
      cli_output = c(result$stdout, result$stderr)
    )
  }

  output <- paste(result$stdout, collapse = "\n")
  match <- regexec(
    "(?:^|[[:space:]])data-dict[[:space:]]+([^[:space:]]+)",
    output
  )
  parts <- regmatches(output, match)[[1L]]
  if (length(parts) != 2L || !nzchar(parts[[2L]])) {
    abort_schema_error(
      paste0(
        "Could not parse the data-dict CLI version from `",
        output,
        "`."
      ),
      cli_path = cli,
      cli_output = output
    )
  }
  parts[[2L]]
}

validate_resolved_data_dict <- function(document, path) {
  invalid <- character()
  if (!is.list(document) || is.data.frame(document)) {
    invalid <- "document"
  } else {
    if (!"$version" %in% names(document)) {
      invalid <- c(invalid, "$version (missing)")
    } else if (!data_dict_is_scalar_text(document[["$version"]])) {
      invalid <- c(invalid, "$version")
    }
    if (!"tables" %in% names(document)) {
      invalid <- c(invalid, "tables (missing)")
    } else if (
      !is.list(document$tables) ||
        is.data.frame(document$tables) ||
        !all(vapply(document$tables, is.list, logical(1)))
    ) {
      invalid <- c(invalid, "tables")
    }
  }

  if (length(invalid) > 0L) {
    abort_schema_error(
      paste0(
        "Resolved data-dict document `",
        path,
        "` has an invalid top-level field: ",
        paste(invalid, collapse = ", "),
        "."
      ),
      schema_path = path,
      invalid_fields = invalid
    )
  }
  invisible(document)
}

normalize_data_dict_path <- function(path) {
  if (!data_dict_is_scalar_text(path)) {
    abort_schema_error(
      "`path` must be one non-empty data-dict path.",
      argument = "path"
    )
  }
  if (!file.exists(path) || dir.exists(path)) {
    abort_schema_error(
      paste0("Data-dict source does not exist: `", path, "`."),
      schema_path = path
    )
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

resolve_data_dict_cli <- function(command, source) {
  if (!data_dict_is_scalar_text(command)) {
    abort_schema_error(
      paste0("The ", source, " must name one non-empty executable."),
      cli = command
    )
  }
  path <- data_dict_path_lookup(command)
  if (!data_dict_is_scalar_text(path)) {
    abort_schema_error(
      paste0("The data-dict CLI configured by ", source, " was not found."),
      cli = command
    )
  }
  path
}

run_data_dict_process <- function(
  command,
  args,
  operation,
  schema_path = NULL
) {
  tryCatch(
    data_dict_system2(command, args),
    error = function(error) {
      abort_schema_error(
        paste0(
          "Could not run `data-dict ",
          operation,
          "`: ",
          conditionMessage(error)
        ),
        schema_path = schema_path,
        cli_path = command,
        parent = error
      )
    }
  )
}

data_dict_system2 <- function(command, args) {
  stderr_path <- tempfile("graft-data-dict-stderr-")
  on.exit(unlink(stderr_path), add = TRUE)
  stdout <- suppressWarnings(
    system2(command, args, stdout = TRUE, stderr = stderr_path)
  )
  status <- attr(stdout, "status", exact = TRUE)
  if (is.null(status)) {
    status <- 0L
  }
  stderr <- if (file.exists(stderr_path)) {
    readLines(stderr_path, warn = FALSE)
  } else {
    character()
  }
  list(
    status = as.integer(status),
    stdout = unname(stdout),
    stderr = stderr
  )
}

data_dict_path_lookup <- function(command) {
  unname(Sys.which(command))
}

data_dict_revision <- function() {
  revision <- getOption("graft.data_dict_revision", NULL)
  if (!is.null(revision)) {
    if (
      is.character(revision) &&
        length(revision) == 1L &&
        !is.na(revision) &&
        !nzchar(trimws(revision))
    ) {
      return(NULL)
    }
    if (!data_dict_is_scalar_text(revision)) {
      abort_schema_error(
        paste0(
          "Option `graft.data_dict_revision` must be one non-empty ",
          "revision or `NULL`."
        ),
        option = "graft.data_dict_revision"
      )
    }
    return(trimws(revision))
  }

  revision <- Sys.getenv("GRAFT_DATA_DICT_REVISION", unset = "")
  if (!nzchar(trimws(revision))) {
    return(NULL)
  }
  trimws(revision)
}

data_dict_has_resolved_header <- function(document) {
  is.list(document) &&
    !is.data.frame(document) &&
    all(c("$version", "tables") %in% names(document))
}

data_dict_is_scalar_text <- function(value) {
  is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    nzchar(trimws(value))
}

data_dict_file_extension <- function(path) {
  filename <- basename(path)
  if (!grepl("\\.", filename)) {
    return("")
  }
  tolower(sub("^.*\\.", "", filename))
}

data_dict_process_diagnostics <- function(result) {
  diagnostics <- c(result$stderr, result$stdout)
  diagnostics <- trimws(diagnostics[nzchar(trimws(diagnostics))])
  if (length(diagnostics) == 0L) {
    return("no diagnostics were emitted")
  }
  paste(diagnostics, collapse = "\n")
}
